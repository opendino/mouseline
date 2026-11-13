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
    ///
    /// The shortcut is matched on the character typed, so the key that types "q" on the
    /// current layout is used: on Turkish F the US Q key types "f" (⌃⌘F is full screen), and
    /// on AZERTY "q" is where US layouts have A.
    static func lockScreen() {
        let keyQ = KeyboardLayout.keyCode(for: "q") ?? 0x0C // kVK_ANSI_Q
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
    ///
    /// With `logFailures`, a non-zero exit is logged together with the end of what the
    /// helper wrote to standard error (osascript reports script errors there).
    static func launch(_ path: String, arguments: [String], logFailures: Bool = false) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errorPipe: Pipe? = logFailures ? Pipe() : nil
        if let errorPipe {
            process.standardError = errorPipe
        } else {
            process.standardError = FileHandle.nullDevice
        }
        do {
            try process.run()
        } catch {
            log.error("Could not start \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let errorPipe else { return }
        let name = URL(fileURLWithPath: path).lastPathComponent
        // Read on a background thread until the helper exits: draining the pipe as it goes
        // means a chatty helper can never block on a full pipe buffer.
        DispatchQueue.global(qos: .utility).async {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus != 0 else { return }
            let output = String(decoding: data.suffix(2000), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            log.error("\(name, privacy: .public) exited with status \(process.terminationStatus): \(output, privacy: .public)")
        }
    }
}
