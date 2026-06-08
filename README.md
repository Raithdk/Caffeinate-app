# Caffinate

A tiny macOS **menu bar** app that keeps your Mac awake on demand. It's a friendly
front-end for the built-in `caffeinate` command — click the coffee cup in your menu
bar, and your Mac won't fall asleep until you say otherwise (or a timer runs out).

No Dock icon, no window — just an icon in the top bar.

---

## What it does

- **Lives in the menu bar.** A coffee-cup icon sits in the top-right of your screen.
  - ☕ **Outlined cup** → inactive (your Mac sleeps normally)
  - ☕ **Filled cup** → active (your Mac is kept awake)
- **Click the icon** to open a small menu where you can:
  - **Turn On / Turn Off** — start or stop keeping the Mac awake (runs indefinitely).
  - **Set a timer** — pick a duration, or **Until a time…** to stay awake until a clock
    time you type; it stops automatically when time runs out.
  - **See live status** — a status line shows time remaining (with a timer) or time elapsed (indefinite).
  - **Quit** the app.
- **No Dock clutter.** The app runs as a menu-bar-only accessory (`LSUIElement`), so it
  never shows up in the Dock or app switcher.

### The menu

```
Inactive                    ← live status: "Active until 16:00 — 1h 30m left" or "Active — 2m 10s elapsed"
─────────────
Turn On / Turn Off          ← simple toggle (stays on indefinitely)
─────────────
Timer
   Indefinite               ← ✓ marks the currently running choice
   30 minutes
   1 hour
   2 hours
   4 hours
   Until 16:00              ← one-click: stay awake until 4 PM
   Until a time…            ← stay awake until a clock time you type (e.g. 16:00)
─────────────
Schedule
   Auto-start daily until 16:00  ✓   ← recurring: keep awake until this time
   Weekdays only (Mon–Fri)       ✓   ← skip weekends (on by default)
   Change daily time…                ← pick the daily stop time
─────────────
Launch at Login        ✓
─────────────
Check for Updates…       ← compares your version against the latest GitHub release
Quit
```

Picking a timer preset starts a session right away (or restarts a running one with the
new duration). **Until a time…** pops up a small prompt where you type a 24-hour time
(`16:00`, `9:30`, even `1600` or `16` all work); if that time has already passed today,
it counts as tomorrow. When the timer elapses, the Mac is allowed to sleep again and the
icon returns to the outlined cup automatically.

### Daily auto-start (recurring)

Turn on **Auto-start daily until 16:00** and the app keeps your Mac awake until that
time *every day*, automatically:

- **Each morning when you open your Mac**, it starts a session that runs until the daily
  time (e.g. open the lid at 07:30 → awake until 16:00).
- At the daily time it stops, and your Mac sleeps normally for the rest of the day.
- Use **Change daily time…** to set a different stop time.
- **Weekdays only (Mon–Fri)** is **on by default**, so opening your Mac on a Saturday or
  Sunday won't start a session. Turn it off to have the schedule run all seven days.

The setting is remembered across restarts. Enabling it also turns on **Launch at Login**
automatically, since the app has to be running to start the session each day. It re-arms
on launch and whenever the Mac wakes from sleep, recomputing the remaining time so the
stop time stays accurate even if the Mac slept partway through the day. A manual session
you start yourself is never overridden by the schedule.

---

## How it works under the hood

The app wraps macOS's built-in `/usr/bin/caffeinate` tool.

- **Turn On** runs: `caffeinate -d -i`
- **A timer preset** runs: `caffeinate -d -i -t <seconds>`

What the flags mean:

| Flag         | Effect                                                            |
|--------------|-------------------------------------------------------------------|
| `-d`         | Prevent the **display** from sleeping                             |
| `-i`         | Prevent the system from **idle** sleeping                         |
| `-t <secs>`  | Run for `<secs>` seconds, then exit automatically (the "timer")   |

You can still **manually lock your screen** (the app does not block that) — it only
prevents *automatic* sleep. When you turn it off (or the timer ends), the `caffeinate`
process is stopped and your normal sleep settings take over again.

---

## Requirements

- macOS 13 (Ventura) or later
- Xcode command-line tools (provides the `swiftc` compiler), for building from source:
  ```sh
  xcode-select --install
  ```

---

## Install (recommended)

One command builds it, installs it to `/Applications`, and launches it:

```sh
cd caffinate-app
./install.sh
```

The script also clears the macOS quarantine flag, so you won't get the
"Apple could not verify…" Gatekeeper warning. The coffee-cup icon appears in your
menu bar — click it to get started.

**Start at login:** open the menu and toggle **Launch at Login** — no System Settings
detour needed. (You can still manage it later under System Settings → General →
Login Items.)

### Uninstall

```sh
./uninstall.sh
```

Quits the app and removes it from `/Applications`.

---

## Build & run without installing

If you'd rather just build and run it in place (e.g. while developing):

```sh
cd caffinate-app
./build.sh
open build/Caffinate.app
```

`build.sh` compiles the Swift source, assembles `build/Caffinate.app`, and ad-hoc
code-signs it so macOS will run it locally.

---

## Checking for updates

Click the menu bar icon and choose **Check for Updates…**. The app asks GitHub for the
latest published [release](https://github.com/Raithdk/Caffeinate-app/releases) and
compares it to your installed version:

- **Update available** → offers to open the release page so you can download it.
- **Up to date** → tells you you're on the latest version.
- **No releases yet / offline** → lets you know, and can open the releases page anyway.

> Releases are published automatically — see below.

---

## Quitting

Click the menu bar icon and choose **Quit** (or press <kbd>⌘Q</kbd> while the menu is
open). Quitting always stops the underlying `caffeinate` process, so nothing is left
keeping your Mac awake.

---

## Automatic releases

Every push to `main` publishes a new GitHub Release automatically, via
[`.github/workflows/release.yml`](.github/workflows/release.yml):

- A macOS Actions runner builds the app with `./build.sh`.
- The version is **auto-incremented** — the workflow reads the latest release tag and
  bumps the last number (e.g. `v1.3` → `v1.4`), stamps it into `Info.plist`, and builds
  with it. No manual version bumping.
- The built app is zipped and attached to the release, with auto-generated release notes.

So **Check for Updates…** in the app will see each new release right after a push. The
workflow uses the repo's built-in `GITHUB_TOKEN`, so there's nothing to configure.

> The published `.app` is ad-hoc signed, not notarized — fine for personal use; other
> people downloading it will see a Gatekeeper prompt on first open.

---

## Project layout

```
caffinate-app/
├── Sources/
│   └── main.swift      # the whole app (AppKit, NSStatusItem menu bar item)
├── Info.plist          # bundle config; LSUIElement = true hides the Dock icon
├── build.sh            # compiles + bundles + signs into build/Caffinate.app
├── install.sh          # build + install to /Applications + launch
├── uninstall.sh        # quit + remove from /Applications
├── .github/workflows/
│   └── release.yml     # auto-publishes a versioned release on every push to main
└── README.md
```

---

## Troubleshooting

- **"Apple could not verify…" / Gatekeeper warning.** The app is only ad-hoc signed
  (not notarized). If macOS blocks it, right-click the app → **Open**, then confirm; or
  allow it under **System Settings → Privacy & Security**.
- **Icon doesn't appear.** Make sure the app is actually running
  (`pgrep -f Caffinate`). The menu bar may be full — try widening it or removing other
  menu bar items.
- **Mac still sleeps.** Some sleep is forced regardless (e.g. low battery, closing the
  lid on some models). `caffeinate` prevents *idle* and *display* sleep, not these.

---

## Tech

- **Language:** Swift
- **Framework:** AppKit (`NSStatusItem` for the menu bar item)
- **Sleep control:** spawns/terminates the system `caffeinate` binary via `Process`
