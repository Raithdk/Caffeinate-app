import AppKit
import ServiceManagement

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var caffeinateProcess: Process?
    private var startDate: Date?
    private var timeout: TimeInterval?   // nil = indefinite; otherwise auto-stop after N seconds
    private var ticker: Timer?

    // Timer presets shown in the menu, in seconds. nil = indefinite (no -t).
    private let presets: [(label: String, seconds: TimeInterval?)] = [
        ("Indefinite", nil),
        ("30 minutes", 30 * 60),
        ("1 hour", 60 * 60),
        ("2 hours", 2 * 60 * 60),
        ("4 hours", 4 * 60 * 60),
    ]

    // Menu items we update dynamically.
    private let statusMenuItem = NSMenuItem(title: "Inactive", action: nil, keyEquivalent: "")
    private let toggleMenuItem = NSMenuItem(title: "Turn On", action: #selector(toggle), keyEquivalent: "t")
    private var presetMenuItems: [NSMenuItem] = []
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = buildMenu()   // clicking the icon opens the menu
        updateUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopCaffeinate()
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)
        menu.addItem(.separator())

        let header = NSMenuItem(title: "Timer", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for (index, preset) in presets.enumerated() {
            let item = NSMenuItem(title: preset.label, action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.indentationLevel = 1
            menu.addItem(item)
            presetMenuItems.append(item)
        }

        let until16Item = NSMenuItem(title: "Until 16:00", action: #selector(selectUntilSixteen), keyEquivalent: "")
        until16Item.target = self
        until16Item.indentationLevel = 1
        menu.addItem(until16Item)

        let untilItem = NSMenuItem(title: "Until a time…", action: #selector(selectUntilTime), keyEquivalent: "")
        untilItem.target = self
        untilItem.indentationLevel = 1
        menu.addItem(untilItem)

        menu.addItem(.separator())

        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: - Actions

    @objc private func toggle() {
        if isActive {
            stopCaffeinate()
        } else {
            // Plain toggle starts an indefinite session.
            startCaffeinate(timeout: nil)
        }
        updateUI()
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        let seconds = presets[sender.tag].seconds
        // Restart with the chosen timeout (also turns it on if currently off).
        stopCaffeinate()
        startCaffeinate(timeout: seconds)
        updateUI()
    }

    @objc private func selectUntilSixteen() {
        startUntil("16:00")
    }

    /// Start a session that runs until the given clock time (today, or tomorrow if past).
    private func startUntil(_ timeText: String) {
        let now = Date()
        guard let target = targetDate(from: timeText, now: now) else { return }
        let seconds = target.timeIntervalSince(now)
        guard seconds >= 1 else { return }
        stopCaffeinate()
        startCaffeinate(timeout: seconds)
        updateUI()
    }

    @objc private func selectUntilTime() {
        // Suggest the next round hour as the default.
        let now = Date()
        let cal = Calendar.current
        let suggested = cal.date(byAdding: .hour, value: 1, to: now).map {
            cal.date(bySetting: .minute, value: 0, of: $0) ?? $0
        } ?? now

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let alert = NSAlert()
        alert.messageText = "Stay awake until…"
        alert.informativeText = "Enter a time (24-hour, e.g. 16:00). If it's already past, it counts as tomorrow."
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = formatter.string(from: suggested)
        alert.accessoryView = field

        // Accessory app needs to come forward to show a modal window.
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard targetDate(from: field.stringValue, now: now) != nil else {
            let err = NSAlert()
            err.messageText = "Couldn't read that time"
            err.informativeText = "Please use a 24-hour time like 16:00 or 9:30."
            err.runModal()
            return
        }

        startUntil(field.stringValue)
    }

    /// Parse "HH:mm" (also tolerates "16", "16.00", "1600") into the next occurrence
    /// of that clock time at or after `now` — today if still ahead, otherwise tomorrow.
    private func targetDate(from text: String, now: Date) -> Date? {
        let digits = text.split(whereSeparator: { !$0.isNumber }).map(String.init)
        let hour: Int
        let minute: Int
        switch digits.count {
        case 1 where digits[0].count >= 3:   // "1600"
            let s = digits[0]
            guard let h = Int(s.prefix(s.count - 2)), let m = Int(s.suffix(2)) else { return nil }
            hour = h; minute = m
        case 1:                               // "16"
            guard let h = Int(digits[0]) else { return nil }
            hour = h; minute = 0
        case 2...:                            // "16:00", "16.00"
            guard let h = Int(digits[0]), let m = Int(digits[1]) else { return nil }
            hour = h; minute = m
        default:
            return nil
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        let cal = Calendar.current
        guard var target = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
        if target <= now {
            target = cal.date(byAdding: .day, value: 1, to: target) ?? target
        }
        return target
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Failed to change login item: \(error)")
        }
        updateUI()
    }

    // MARK: - Caffeinate control

    private var isActive: Bool {
        caffeinateProcess?.isRunning == true
    }

    private func startCaffeinate(timeout: TimeInterval?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // -d -i: prevent display + idle sleep while still allowing manual lock.
        // -t <seconds>: caffeinate's built-in timeout, after which it self-exits.
        var args = ["-d", "-i"]
        if let timeout {
            args += ["-t", String(Int(timeout))]
        }
        process.arguments = args

        process.terminationHandler = { [weak self] _ in
            // Fires both on manual .terminate() and when -t elapses on its own.
            DispatchQueue.main.async {
                self?.caffeinateProcess = nil
                self?.startDate = nil
                self?.timeout = nil
                self?.updateUI()
            }
        }

        do {
            try process.run()
            caffeinateProcess = process
            startDate = Date()
            self.timeout = timeout
        } catch {
            caffeinateProcess = nil
            startDate = nil
            self.timeout = nil
            NSLog("Failed to launch caffeinate: \(error)")
        }
    }

    private func stopCaffeinate() {
        ticker?.invalidate()
        ticker = nil
        if let process = caffeinateProcess, process.isRunning {
            process.terminationHandler = nil   // avoid re-entrant UI update
            process.terminate()
        }
        caffeinateProcess = nil
        startDate = nil
        timeout = nil
    }

    // MARK: - UI

    private func updateUI() {
        let active = isActive

        // Icon: filled coffee cup when active, outlined when inactive.
        let symbolName = active ? "cup.and.saucer.fill" : "cup.and.saucer"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Caffeinate")
        image?.isTemplate = true
        statusItem.button?.image = image

        toggleMenuItem.title = active ? "Turn Off" : "Turn On"

        launchAtLoginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off

        // Check the preset that matches the running session (if any).
        for (index, item) in presetMenuItems.enumerated() {
            let matches = active && presets[index].seconds == timeout
            item.state = matches ? .on : .off
        }

        if active {
            startTicker()
            updateStatusText()
        } else {
            ticker?.invalidate()
            ticker = nil
            statusMenuItem.title = "Inactive"
        }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatusText()
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func updateStatusText() {
        guard let start = startDate else {
            statusMenuItem.title = "Active"
            return
        }
        let elapsed = Date().timeIntervalSince(start)

        if let timeout {
            let remaining = max(0, timeout - elapsed)
            let endFormatter = DateFormatter()
            endFormatter.dateFormat = "HH:mm"
            let endTime = endFormatter.string(from: start.addingTimeInterval(timeout))
            statusMenuItem.title = "Active until \(endTime) — \(format(remaining)) left"
        } else {
            statusMenuItem.title = "Active — \(format(elapsed)) elapsed"
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%dh %02dm %02ds", h, m, s)
            : String(format: "%dm %02ds", m, s)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon, menu bar only
let delegate = AppDelegate()
app.delegate = delegate
app.run()
