import AppKit
import ApplicationServices
import MouseLineCore
import os

private let log = Logger(subsystem: "app.mouseline", category: "actions")

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
        case .openURL: openURL(action.url)
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

    /// Back/forward go to the app under the cursor, not the frontmost one: the stroke is drawn
    /// over a window, the mouse-button path reaches that window anyway, and the swallowed
    /// trigger click never activates it.
    ///
    /// Apple's apps get their own Back/Forward menu item pressed through the Accessibility API.
    /// That works on every keyboard layout and needs no focus change. If no such item is found,
    /// ⌘[ / ⌘] is typed with the key that produces the character on the current layout; when
    /// no key does without modifiers (German, Turkish), mouse buttons are sent rather than a
    /// keystroke that would mean something else there (on Turkish F the US "[" key types "q").
    private static func navigate(back: Bool) {
        let character: Character = back ? "[" : "]"
        let location = CGEvent(source: nil)?.location ?? .zero
        if let target = AppLocator.application(at: location),
           let id = target.bundleIdentifier, keyboardNavigationApps.contains(id) {
            if MenuShortcut.press(commandCharacter: character, in: target) { return }
            if let keyCode = KeyboardLayout.keyCode(for: character) {
                let combo = KeyCombo(keyCode: keyCode, modifiers: KeyCombo.commandMask, display: "⌘" + String(character))
                postShortcut(combo, to: target)
                return
            }
        }
        // Mouse buttons 4/5 are numbered 3/4 in CGEvent.
        postMouseButton(back ? 3 : 4)
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

    /// Arrow, navigation and function keys carry the Fn flag when typed on a real keyboard
    /// (the arrows also NumericPad). The recorder keeps only ⌘⌥⌃⇧, and system hot keys such as
    /// ⌃→ ("Move right a space") are registered with the Fn bit, so without it they never fire.
    private static let functionKeyCodes: Set<UInt16> = [
        123, 124, 125, 126, // arrows
        115, 119, 116, 121, 117, 114, // Home, End, Page Up, Page Down, Forward Delete, Help
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, // F1–F12
        105, 107, 113, 106, 64, 79, 80, 90, // F13–F20
    ]
    private static let arrowKeyCodes: ClosedRange<UInt16> = 123...126

    /// Posts `combo` at the HID level, so it goes to the frontmost app (and system hot keys
    /// see it). With a `target` that is not frontmost, it is posted to that process instead:
    /// a navigation keystroke must not reach the frontmost app, where ⌘[ may mean "outdent".
    private static func postShortcut(_ combo: KeyCombo, to target: NSRunningApplication? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        var flags = CGEventFlags(rawValue: combo.modifiers)
        if functionKeyCodes.contains(combo.keyCode) { flags.insert(.maskSecondaryFn) }
        if arrowKeyCodes.contains(combo.keyCode) { flags.insert(.maskNumericPad) }
        let targetPID: pid_t? = target.flatMap { app in
            app.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier ? nil : app.processIdentifier
        }
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(combo.keyCode), keyDown: keyDown)
            event?.flags = flags
            if let targetPID {
                event?.postToPid(targetPID)
            } else {
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    /// Opens the Open URL action's text. Plain host names ("github.com") get https://; other
    /// schemes (mailto:, tel:, app URL schemes) are kept. A URL that cannot be opened beeps,
    /// since the HUD has already shown the action's name and would otherwise look like success.
    private static func openURL(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let url = normalizedURL(trimmed) else {
            log.error("Invalid URL: \(text, privacy: .public)")
            NSSound.beep()
            return
        }
        if !NSWorkspace.shared.open(url) {
            log.error("Could not open URL: \(url.absoluteString, privacy: .public)")
            NSSound.beep()
        }
    }

    private static func normalizedURL(_ text: String) -> URL? {
        let withScheme = hasScheme(text) ? text : "https://" + text
        if let url = URL(string: withScheme), url.scheme != nil { return url }
        // Before macOS 14, URL(string:) rejects spaces and non-ASCII characters (…/wiki/İstanbul)
        // instead of encoding them. "%" and "#" stay as they are, so existing escapes and
        // fragments survive.
        var allowed = CharacterSet.urlFragmentAllowed
        allowed.insert(charactersIn: "%#[]")
        guard let encoded = withScheme.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: encoded), url.scheme != nil
        else { return nil }
        return url
    }

    /// Whether `text` starts with a URL scheme. "example.com:8080" and "localhost:3000" are a
    /// host and port, not a scheme.
    private static func hasScheme(_ text: String) -> Bool {
        if text.contains("://") { return true }
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[..<colon]
        guard let first = scheme.first, first.isASCII, first.isLetter,
              scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-".contains($0)) }),
              scheme.lowercased() != "localhost"
        else { return false }
        let rest = text[text.index(after: colon)...]
        let port = rest.prefix(while: { $0.isASCII && $0.isNumber })
        let isPort = !port.isEmpty && (port.endIndex == rest.endIndex || rest[port.endIndex] == "/")
        return !isPort
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

    /// Runs AppleScript source with /usr/bin/osascript, without waiting for it.
    ///
    /// It runs out of process because the event taps are serviced by the main run loop: an
    /// in-process NSAppleScript (main-thread only) running `delay 3`, or waiting up to two
    /// minutes on a busy app, would stall right and middle clicks system-wide until macOS
    /// disabled the tap. Failures are logged with osascript's error message.
    ///
    /// macOS asks for Automation consent once per target app (System Settings → Privacy &
    /// Security → Automation); until it is granted, scripts that control that app fail with
    /// error -1743. osascript is MouseLine' child process, so MouseLine is the responsible
    /// process: the prompt and the Settings entry name MouseLine, which keeps the
    /// `com.apple.security.automation.apple-events` entitlement (Support/MouseLine.entitlements)
    /// for that reason.
    private static func runAppleScript(_ source: String) {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        SystemActions.launch("/usr/bin/osascript", arguments: ["-e", source], logFailures: true)
    }
}

/// Presses an app's own menu item by its ⌘ shortcut through the Accessibility API.
///
/// The menu item is found by its key equivalent character, not by posting the key, so the
/// keyboard layout does not matter, and the item is pressed in the app even when it is not
/// frontmost.
@MainActor
private enum MenuShortcut {
    private struct CacheKey: Hashable {
        let pid: pid_t
        let character: Character
    }

    /// Found items per app, so the menu bar is walked once per app rather than per gesture.
    /// A stale entry (the app rebuilt its menu) fails to press and is looked up again.
    private static var cache: [CacheKey: AXUIElement] = [:]

    /// Short, so a hung app costs half a second instead of the default six (the event taps
    /// wait on the main thread meanwhile).
    private static let messagingTimeout: Float = 0.5

    /// Menu bar item → menu → item → submenu → item.
    private static let maxDepth = 5
    /// Upper bound on elements visited, for apps with huge menus (bookmarks, history).
    private static let maxElements = 1500

    /// Presses the item whose shortcut is ⌘ + `commandCharacter` (no other modifiers).
    /// Returns false when there is no such item or it could not be pressed.
    static func press(commandCharacter: Character, in app: NSRunningApplication) -> Bool {
        let key = CacheKey(pid: app.processIdentifier, character: commandCharacter)
        if let item = cache[key] {
            if AXUIElementPerformAction(item, kAXPressAction as CFString) == .success { return true }
            cache[key] = nil
        }
        guard let item = findItem(commandCharacter: String(commandCharacter), in: app.processIdentifier),
              AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        else { return false }
        if cache.count > 32 { cache.removeAll() }
        cache[key] = item
        return true
    }

    /// Breadth-first, so items in the top-level menus (where Back/Forward live) are found
    /// before any submenu is opened up.
    private static func findItem(commandCharacter: String, in pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBarValue, CFGetTypeID(menuBarValue) == AXUIElementGetTypeID()
        else { return nil }
        let menuBar = menuBarValue as! AXUIElement
        AXUIElementSetMessagingTimeout(menuBar, messagingTimeout)

        let attributes = [kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute, kAXChildrenAttribute] as CFArray
        var queue: [(element: AXUIElement, depth: Int)] = [(menuBar, 0)]
        var index = 0
        while index < queue.count, index < maxElements {
            let (element, depth) = queue[index]
            index += 1
            var raw: CFArray?
            let result = AXUIElementCopyMultipleAttributeValues(element, attributes, [], &raw)
            // A timeout means the app is not answering; every further call would wait too.
            if result == .cannotComplete { return nil }
            guard result == .success, let values = raw as? [AnyObject], values.count == 3 else { continue }
            // Attributes an element lacks come back as AXValue errors, which fail these casts.
            if depth > 0, let character = values[0] as? String, character == commandCharacter,
               let modifiers = values[1] as? Int, modifiers == 0 { // kAXMenuItemModifierNone: ⌘ only
                return element
            }
            guard depth < maxDepth, let children = values[2] as? [AXUIElement] else { continue }
            for child in children {
                AXUIElementSetMessagingTimeout(child, messagingTimeout)
                queue.append((child, depth + 1))
            }
        }
        return nil
    }
}
