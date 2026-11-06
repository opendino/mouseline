import AppKit
import MGesturesCore
import os

private let log = Logger(subsystem: "dev.mgestures.app", category: "actions")

/// System-wide actions (Mission Control, show desktop, lock, display sleep) and app actions
/// (hide, quit) that do not go through the Accessibility API.
@MainActor
enum SystemActions {
    private static let missionControlApp = "/System/Applications/Mission Control.app"

    // MARK: - System

    static func missionControl() {
        let url = URL(fileURLWithPath: missionControlApp)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { log.error("Could not open Mission Control: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// Runs the Mission Control executable with the argument "1", which shows the desktop.
    /// This is undocumented but long-standing behavior (it has worked for many macOS
    /// releases). It needs no keyboard shortcut, so it keeps working when the user has
    /// changed or removed the "Show Desktop" shortcut in System Settings.
    static func showDesktop() {
        launch(missionControlApp + "/Contents/MacOS/Mission Control", arguments: ["1"])
    }

    /// Posts ⌃⌘Q, the system "Lock Screen" shortcut (also in the Apple menu).
    /// Unlike the private `SACLockScreenImmediate` API this needs nothing beyond the
    /// Accessibility permission the app already has for posting events.
    static func lockScreen() {
        let keyQ: CGKeyCode = 0x0C // kVK_ANSI_Q
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = CGEventFlags(rawValue: KeyCombo.controlMask | KeyCombo.commandMask)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyQ, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    static func sleepDisplay() {
        launch("/usr/bin/pmset", arguments: ["displaysleepnow"])
    }

    // MARK: - Apps

    static func hideFrontmostApp() {
        guard let app = frontmostOtherApp() else { return }
        if !app.hide() { log.debug("Could not hide \(app.bundleIdentifier ?? "?", privacy: .public)") }
    }

    /// Quits the frontmost app. Finder is hidden instead: it is meant to always run, and
    /// terminating it only makes it relaunch (and its windows close) a moment later.
    static func quitFrontmostApp() {
        guard let app = frontmostOtherApp() else { return }
        if app.bundleIdentifier == "com.apple.finder" {
            app.hide()
            return
        }
        if !app.terminate() { log.debug("Could not quit \(app.bundleIdentifier ?? "?", privacy: .public)") }
    }

    /// The frontmost app, unless it is mgestures itself (e.g. the Settings window is in front):
    /// a gesture must never hide or quit the app that is listening for gestures.
    private static func frontmostOtherApp() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return app
    }

    // MARK: - Helpers

    /// Starts a helper executable without waiting for it; output is discarded.
    static func launch(_ path: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            log.error("Could not start \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
