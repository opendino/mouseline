import AppKit
import MGesturesCore
import os

private let log = Logger(subsystem: "dev.mgestures.app", category: "actions")

/// Executes the action bound to a gesture.
@MainActor
enum ActionRunner {
    static func run(_ action: ActionConfig) {
        switch action.kind {
        case .none:
            break
        // Window
        case .tileLeft: WindowManager.perform(.tileLeft)
        case .tileRight: WindowManager.perform(.tileRight)
        case .tileTop: WindowManager.perform(.tileTop)
        case .tileBottom: WindowManager.perform(.tileBottom)
        case .maximize: WindowManager.perform(.maximize)
        case .center: WindowManager.perform(.center)
        case .moveToNextDisplay: WindowManager.perform(.moveToNextDisplay)
        case .toggleFullScreen: WindowManager.perform(.toggleFullScreen)
        case .minimize: WindowManager.perform(.minimize)
        case .closeWindow: WindowManager.perform(.close)
        // App
        case .hideApp: SystemActions.hideFrontmostApp()
        case .quitApp: SystemActions.quitFrontmostApp()
        case .openApplication: openApplication(action)
        // Navigation
        case .navigateBack: navigate(back: true)
        case .navigateForward: navigate(back: false)
        case .openURL:
            guard let url = URL(string: action.url.trimmingCharacters(in: .whitespaces)), url.scheme != nil else {
                log.error("Invalid URL: \(action.url, privacy: .public)")
                return
            }
            NSWorkspace.shared.open(url)
        // System
        case .missionControl: SystemActions.missionControl()
        case .showDesktop: SystemActions.showDesktop()
        case .lockScreen: SystemActions.lockScreen()
        case .sleepDisplay: SystemActions.sleepDisplay()
        // Media
        case .playPause: MediaKeys.press(.play)
        case .nextTrack: MediaKeys.press(.next)
        case .previousTrack: MediaKeys.press(.previous)
        case .volumeUp: MediaKeys.press(.soundUp)
        case .volumeDown: MediaKeys.press(.soundDown)
        case .mute: MediaKeys.press(.mute)
        // Custom
        case .keyboardShortcut:
            if let combo = action.shortcut { postShortcut(combo) }
        case .shellCommand:
            runShell(action.command)
        case .appleScript:
            runAppleScript(action.script)
        }
    }

    /// Apple's own apps ignore the extra mouse buttons but all use ⌘[ / ⌘] for back and
    /// forward. Everywhere else mouse buttons 4/5 are sent: browsers and most other apps
    /// understand them, and they do not collide with editor shortcuts (⌘[ is "outdent" there).
    private static let keyboardNavigationApps: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.apple.finder",
        "com.apple.systempreferences", "com.apple.AppStore", "com.apple.Music",
        "com.apple.podcasts", "com.apple.TV", "com.apple.helpviewer",
    ]

    private static func navigate(back: Bool) {
        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, keyboardNavigationApps.contains(id) {
            // kVK_ANSI_LeftBracket / kVK_ANSI_RightBracket
            postShortcut(KeyCombo(keyCode: back ? 0x21 : 0x1E, modifiers: KeyCombo.commandMask, display: back ? "⌘[" : "⌘]"))
        } else {
            // Mouse buttons 4/5 are numbered 3/4 in CGEvent.
            postMouseButton(back ? 3 : 4)
        }
    }

    private static func postMouseButton(_ number: Int64) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: .center)
            event?.setIntegerValueField(.mouseEventButtonNumber, value: number)
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func postShortcut(_ combo: KeyCombo) {
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = CGEventFlags(rawValue: combo.modifiers)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(combo.keyCode), keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func openApplication(_ action: ActionConfig) {
        let path = (action.appPath as NSString).expandingTildeInPath
        guard !path.isEmpty else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = splitArguments(action.appArguments)
        configuration.createsNewApplicationInstance = action.newInstance
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration) { _, error in
            if let error { log.error("Could not open \(path, privacy: .public): \(error.localizedDescription, privacy: .public)") }
        }
    }

    private static func runShell(_ command: String) {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Login shell, so the user's PATH (e.g. Homebrew) is available.
        SystemActions.launch("/bin/zsh", arguments: ["-lc", command])
    }

    /// Runs AppleScript source with NSAppleScript.
    ///
    /// NSAppleScript is not thread-safe, so it runs on the main thread — but on a later turn
    /// of the run loop, so the gesture handling (HUD, event tap callback) finishes first and a
    /// slow script never delays it. A long-running script does block the UI while it runs.
    ///
    /// Sending Apple Events from a hardened-runtime app requires the
    /// `com.apple.security.automation.apple-events` entitlement, configured in
    /// Support/mgestures.entitlements. On top of that, macOS asks the user for Automation
    /// consent once per target app (System Settings → Privacy & Security → Automation);
    /// until it is granted, scripts that control that app fail with error -1743.
    private static func runAppleScript(_ source: String) {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        DispatchQueue.main.async {
            guard let script = NSAppleScript(source: source) else {
                log.error("Could not create AppleScript")
                return
            }
            var errorInfo: NSDictionary?
            script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown error"
                let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
                log.error("AppleScript failed (\(number)): \(message, privacy: .public)")
            }
        }
    }
}
