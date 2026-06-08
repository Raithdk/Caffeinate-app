import AppKit
import ServiceManagement

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var caffeinateProcess: Process?
    private var startDate: Date?
    private var timeout: TimeInterval?   // nil = indefinite; otherwise auto-stop after N seconds
    private var ticker: Timer?
    private var isDailySession = false   // true if the current session was started by the daily schedule

    // Persisted "auto-start every day until <time>" settings.
    private let defaults = UserDefaults.standard
    private var dailyEnabled: Bool {
        get { defaults.bool(forKey: "dailyEnabled") }
        set { defaults.set(newValue, forKey: "dailyEnabled") }
    }
    private var dailyTime: String {
        get { defaults.string(forKey: "dailyTime") ?? "16:00" }
        set { defaults.set(newValue, forKey: "dailyTime") }
    }
    private var weekdaysOnly: Bool {
        get { defaults.bool(forKey: "weekdaysOnly") }   // default registered as true on launch
        set { defaults.set(newValue, forKey: "weekdaysOnly") }
    }

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
    private let dailyMenuItem = NSMenuItem(title: "Auto-start daily", action: #selector(toggleDaily), keyEquivalent: "")
    private let weekdaysMenuItem = NSMenuItem(title: "Weekdays only (Mon–Fri)", action: #selector(toggleWeekdays), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["weekdaysOnly": true])   // weekdays-only is on by default

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = buildMenu()   // clicking the icon opens the menu

        // Re-arm the daily schedule whenever the Mac wakes from sleep (e.g. you open
        // the lid the next morning) — this is what restarts it for the new day.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        applyDailySchedule()   // arm on launch (e.g. when launched at login)
        updateUI()
    }

    @objc private func systemDidWake() {
        applyDailySchedule()
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

        let scheduleHeader = NSMenuItem(title: "Schedule", action: nil, keyEquivalent: "")
        scheduleHeader.isEnabled = false
        menu.addItem(scheduleHeader)

        dailyMenuItem.target = self
        dailyMenuItem.indentationLevel = 1
        menu.addItem(dailyMenuItem)

        weekdaysMenuItem.target = self
        weekdaysMenuItem.indentationLevel = 1
        menu.addItem(weekdaysMenuItem)

        let changeDailyItem = NSMenuItem(title: "Change daily time…", action: #selector(changeDailyTime), keyEquivalent: "")
        changeDailyItem.target = self
        changeDailyItem.indentationLevel = 1
        menu.addItem(changeDailyItem)

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

    // MARK: - Daily schedule

    @objc private func toggleDaily() {
        dailyEnabled.toggle()
        if dailyEnabled {
            // The schedule only works if the app launches when you log in, so turn
            // that on automatically.
            if SMAppService.mainApp.status != .enabled {
                try? SMAppService.mainApp.register()
            }
            applyDailySchedule()
        } else if isActive && isDailySession {
            // Turning the schedule off stops only a session it started itself.
            stopCaffeinate()
        }
        updateUI()
    }

    @objc private func toggleWeekdays() {
        weekdaysOnly.toggle()
        // Re-evaluate immediately: e.g. if it's the weekend and we just turned this on
        // while an auto session is running, it should stop now.
        applyDailySchedule()
        updateUI()
    }

    @objc private func changeDailyTime() {
        let alert = NSAlert()
        alert.messageText = "Auto-start every day until…"
        alert.informativeText = "Enter a 24-hour time (e.g. 16:00). Each day your Mac is kept awake until this time."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = dailyTime
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard let (h, m) = parseHourMinute(field.stringValue) else {
            let err = NSAlert()
            err.messageText = "Couldn't read that time"
            err.informativeText = "Please use a 24-hour time like 16:00 or 9:30."
            err.runModal()
            return
        }

        dailyTime = String(format: "%02d:%02d", h, m)
        if dailyEnabled { applyDailySchedule() }
        updateUI()
    }

    /// Start/stop the auto session so it matches the daily setting for *today*.
    /// Called on launch and on wake — this is what makes it recur each day.
    private func applyDailySchedule() {
        guard dailyEnabled, let target = todayOccurrence(of: dailyTime, now: Date()) else { return }
        let now = Date()

        // On weekends (when weekdays-only is on) the schedule never starts; stop an
        // auto session if one is somehow running, and do nothing else.
        if weekdaysOnly && isWeekend(now) {
            if isActive && isDailySession { stopCaffeinate() }
            updateUI()
            return
        }

        if now < target {
            // Should be awake until target. Start it, or — if a previous auto session
            // is running — restart to correct for any time spent asleep.
            if !isActive || isDailySession {
                stopCaffeinate()
                startCaffeinate(timeout: target.timeIntervalSince(now), daily: true)
            }
        } else if isActive && isDailySession {
            // Past today's time: stop, but only an auto-started session.
            stopCaffeinate()
        }
        updateUI()
    }

    // MARK: - Time parsing

    /// Parse "HH:mm" (also tolerates "16", "16.00", "1600") into an (hour, minute) pair.
    private func parseHourMinute(_ text: String) -> (hour: Int, minute: Int)? {
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
        return (hour, minute)
    }

    /// Next occurrence of the clock time at or after `now` — today if ahead, else tomorrow.
    private func targetDate(from text: String, now: Date) -> Date? {
        guard let (h, m) = parseHourMinute(text) else { return nil }
        let cal = Calendar.current
        guard var target = cal.date(bySettingHour: h, minute: m, second: 0, of: now) else { return nil }
        if target <= now {
            target = cal.date(byAdding: .day, value: 1, to: target) ?? target
        }
        return target
    }

    /// True on Saturday or Sunday (so the schedule runs Mon–Fri only).
    private func isWeekend(_ date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)   // 1 = Sun … 7 = Sat
        return weekday == 1 || weekday == 7
    }

    /// Today's occurrence of the clock time (no rolling to tomorrow).
    private func todayOccurrence(of text: String, now: Date) -> Date? {
        guard let (h, m) = parseHourMinute(text) else { return nil }
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: now)
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

    private func startCaffeinate(timeout: TimeInterval?, daily: Bool = false) {
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
                self?.isDailySession = false
                self?.updateUI()
            }
        }

        do {
            try process.run()
            caffeinateProcess = process
            startDate = Date()
            self.timeout = timeout
            self.isDailySession = daily
        } catch {
            caffeinateProcess = nil
            startDate = nil
            self.timeout = nil
            self.isDailySession = false
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
        isDailySession = false
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

        dailyMenuItem.title = "Auto-start daily until \(dailyTime)"
        dailyMenuItem.state = dailyEnabled ? .on : .off

        weekdaysMenuItem.state = weekdaysOnly ? .on : .off
        weekdaysMenuItem.isEnabled = dailyEnabled

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
