import Foundation

// The configuration model, persisted as JSON in
// ~/Library/Application Support/MouseLine/config.json.
//
// Every decoder below tolerates missing keys (falling back to defaults) so that a
// config file written by an older or newer version still loads.

public struct RGBAColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let orange = RGBAColor(red: 1, green: 0.55, blue: 0.1, alpha: 0.95)

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RGBAColor.orange
        red = try c.decodeIfPresent(Double.self, forKey: .red) ?? d.red
        green = try c.decodeIfPresent(Double.self, forKey: .green) ?? d.green
        blue = try c.decodeIfPresent(Double.self, forKey: .blue) ?? d.blue
        alpha = try c.decodeIfPresent(Double.self, forKey: .alpha) ?? 1
    }
}

// MARK: - Actions

/// Groups actions in the action picker.
public enum ActionCategory: String, CaseIterable, Sendable {
    case none = "None"
    case window = "Window"
    case app = "App"
    case navigation = "Navigation"
    case system = "System"
    case media = "Media"
    case custom = "Custom"
}

public enum ActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    // Window
    case tileLeft
    case tileRight
    case tileTop
    case tileBottom
    case maximize
    case center
    case moveToNextDisplay
    case toggleFullScreen
    case minimize
    case closeWindow
    // App
    case hideApp
    case quitApp
    case openApplication
    // Navigation
    case navigateBack
    case navigateForward
    case openURL
    // System
    case missionControl
    case showDesktop
    case lockScreen
    case sleepDisplay
    // Media
    case playPause
    case nextTrack
    case previousTrack
    case volumeUp
    case volumeDown
    case mute
    // Custom
    case keyboardShortcut
    case shellCommand
    case appleScript

    public var id: String { rawValue }

    /// English title; the app localizes it through its string table (the title is the key).
    public var title: String {
        switch self {
        case .none: return "No action"
        case .tileLeft: return "Tile window left"
        case .tileRight: return "Tile window right"
        case .tileTop: return "Tile window top"
        case .tileBottom: return "Tile window bottom"
        case .maximize: return "Maximize window"
        case .center: return "Center window"
        case .moveToNextDisplay: return "Move window to next display"
        case .toggleFullScreen: return "Toggle full screen"
        case .minimize: return "Minimize window"
        case .closeWindow: return "Close window"
        case .hideApp: return "Hide app"
        case .quitApp: return "Quit app"
        case .openApplication: return "Open application"
        case .navigateBack: return "Back"
        case .navigateForward: return "Forward"
        case .openURL: return "Open URL"
        case .missionControl: return "Mission Control"
        case .showDesktop: return "Show desktop"
        case .lockScreen: return "Lock screen"
        case .sleepDisplay: return "Sleep display"
        case .playPause: return "Play / pause"
        case .nextTrack: return "Next track"
        case .previousTrack: return "Previous track"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        case .keyboardShortcut: return "Keyboard shortcut"
        case .shellCommand: return "Run shell command"
        case .appleScript: return "Run AppleScript"
        }
    }

    public var category: ActionCategory {
        switch self {
        case .none: return .none
        case .tileLeft, .tileRight, .tileTop, .tileBottom, .maximize, .center,
             .moveToNextDisplay, .toggleFullScreen, .minimize, .closeWindow:
            return .window
        case .hideApp, .quitApp, .openApplication: return .app
        case .navigateBack, .navigateForward, .openURL: return .navigation
        case .missionControl, .showDesktop, .lockScreen, .sleepDisplay: return .system
        case .playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .mute: return .media
        case .keyboardShortcut, .shellCommand, .appleScript: return .custom
        }
    }

    /// True if the action needs extra input (shortcut, path, URL, command or script).
    public var hasParameters: Bool {
        switch self {
        case .keyboardShortcut, .openApplication, .openURL, .shellCommand, .appleScript: return true
        default: return false
        }
    }

    public static func kinds(in category: ActionCategory) -> [ActionKind] {
        allCases.filter { $0.category == category }
    }

    public init(from decoder: Decoder) throws {
        // Unknown kinds (e.g. from a newer version) degrade to "no action" instead of failing the whole file.
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ActionKind(rawValue: raw) ?? .none
    }
}

public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    /// macOS virtual key code (kVK_*).
    public var keyCode: UInt16
    /// CGEventFlags raw value (only the modifier bits are used).
    public var modifiers: UInt64
    /// Human-readable form, e.g. "⌘⇧K".
    public var display: String

    public init(keyCode: UInt16, modifiers: UInt64, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    /// The key and modifiers are what the shortcut *is*, so they stay required; the label is
    /// only cosmetic.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try c.decode(UInt16.self, forKey: .keyCode)
        modifiers = try c.decode(UInt64.self, forKey: .modifiers)
        display = try c.decodeIfPresent(String.self, forKey: .display) ?? ""
    }

    // Modifier bits (identical in CGEventFlags and NSEvent.ModifierFlags).
    public static let shiftMask: UInt64 = 0x2_0000
    public static let controlMask: UInt64 = 0x4_0000
    public static let optionMask: UInt64 = 0x8_0000
    public static let commandMask: UInt64 = 0x10_0000
}

public struct ActionConfig: Codable, Equatable, Sendable {
    public var kind: ActionKind
    public var shortcut: KeyCombo?
    public var appPath: String
    /// Arguments passed to the application, shell-style (quotes allowed).
    public var appArguments: String
    /// Launch a separate instance even if the app is already running (`open -n`).
    public var newInstance: Bool
    public var url: String
    public var command: String
    /// AppleScript source for `.appleScript`.
    public var script: String

    public init(
        kind: ActionKind = .none, shortcut: KeyCombo? = nil, appPath: String = "",
        appArguments: String = "", newInstance: Bool = false, url: String = "", command: String = "",
        script: String = ""
    ) {
        self.kind = kind
        self.shortcut = shortcut
        self.appPath = appPath
        self.appArguments = appArguments
        self.newInstance = newInstance
        self.url = url
        self.command = command
        self.script = script
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ActionConfig()
        kind = try c.decodeIfPresent(ActionKind.self, forKey: .kind) ?? d.kind
        // A broken shortcut drops only the shortcut, not the binding (or the whole file).
        shortcut = try? c.decodeIfPresent(KeyCombo.self, forKey: .shortcut)
        appPath = try c.decodeIfPresent(String.self, forKey: .appPath) ?? d.appPath
        appArguments = try c.decodeIfPresent(String.self, forKey: .appArguments) ?? d.appArguments
        newInstance = try c.decodeIfPresent(Bool.self, forKey: .newInstance) ?? d.newInstance
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? d.url
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? d.command
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? d.script
    }
}

// MARK: - Triggering

/// Which mouse button draws gestures.
public enum TriggerButton: String, Codable, CaseIterable, Identifiable, Sendable {
    case right
    case middle

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .right: return "Right button"
        case .middle: return "Middle button"
        }
    }

    /// CGMouseButton number of this button.
    public var buttonNumber: Int64 {
        switch self {
        case .right: return 1
        case .middle: return 2
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TriggerButton(rawValue: raw) ?? .right
    }
}

/// A modifier key that must be held for gestures to start.
/// The look of MouseLine's own windows: follow macOS, or always light or dark.
public enum AppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public enum RequiredModifier: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case option
    case control
    case command
    case shift

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: return "None"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .command: return "⌘ Command"
        case .shift: return "⇧ Shift"
        }
    }

    /// The modifier bit (CGEventFlags raw value), or 0 for `.none`.
    public var mask: UInt64 {
        switch self {
        case .none: return 0
        case .option: return KeyCombo.optionMask
        case .control: return KeyCombo.controlMask
        case .command: return KeyCombo.commandMask
        case .shift: return KeyCombo.shiftMask
        }
    }

    /// Whether a press with these modifier flags (CGEventFlags raw value) may start a gesture.
    public func isSatisfied(by flags: UInt64) -> Bool {
        self == .none || flags & mask != 0
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RequiredModifier(rawValue: raw) ?? .none
    }
}

// MARK: - Apps and custom gestures

/// An app in which gestures are turned off (the right button behaves normally there).
public struct ExcludedApp: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var bundleID: String
    public var name: String
    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? bundleID
    }
}

/// Bindings that apply only in one app, overriding the global ones.
public struct AppBindings: Codable, Equatable, Sendable {
    public var name: String
    /// Gesture id → action. An entry with `.none` turns that gesture off in this app.
    public var bindings: [String: ActionConfig]

    public init(name: String, bindings: [String: ActionConfig] = [:]) {
        self.name = name
        self.bindings = bindings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        bindings = try c.decodeIfPresent([String: ActionConfig].self, forKey: .bindings) ?? [:]
    }
}

/// A shape recorded by the user.
public struct CustomGesture: Codable, Equatable, Identifiable, Sendable {
    public static let idPrefix = "custom."

    /// Stable id, always starting with `custom.`; used as the binding key.
    public var id: String
    public var name: String
    /// Normalized points (see `Recognizer.prepare`).
    public var points: [StrokePoint]

    public init(id: String = CustomGesture.idPrefix + UUID().uuidString, name: String, points: [StrokePoint]) {
        self.id = id
        self.name = name
        self.points = points
    }

    /// Creates a gesture from a raw drawn stroke (any coordinate space, y down).
    public init(name: String, stroke: [StrokePoint]) {
        self.init(name: name, points: Recognizer.prepare(stroke))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        points = try c.decode([StrokePoint].self, forKey: .points)
    }

    public var template: GestureTemplate {
        GestureTemplate(id: id, group: .custom, points: points)
    }

    public static func isCustomID(_ id: String) -> Bool { id.hasPrefix(idPrefix) }
}

// MARK: - App configuration

public struct AppConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var enabled: Bool
    public var onboardingCompleted: Bool

    // Triggering
    public var triggerButton: TriggerButton
    public var requiredModifier: RequiredModifier
    /// Global shortcut that toggles `enabled`.
    public var toggleShortcut: KeyCombo?
    /// Hold the button still to open the context menu immediately.
    public var holdToOpenMenu: Bool
    public var holdDelay: Double
    public var excludedApps: [ExcludedApp]

    // Feedback & appearance
    public var showTrail: Bool
    public var trailColor: RGBAColor
    public var trailWidth: Double
    /// Briefly show the recognized gesture's name on screen.
    public var showGestureName: Bool
    /// System sound name played on a recognized gesture ("" = no sound).
    public var feedbackSound: String
    /// Haptic feedback on Force Touch trackpads.
    public var hapticFeedback: Bool
    /// Light or dark windows, or the macOS setting.
    public var appearance: AppearanceMode

    // Recognition
    public var clickMaxPath: Double
    public var matchMaxDistance: Double
    public var customGestures: [CustomGesture]
    /// Strokes from calibration, used as extra templates (see `Calibration`).
    public var personalSamples: [PersonalSample]

    /// Template id → action. Gestures without an entry do nothing.
    public var bindings: [String: ActionConfig]
    /// Bundle id → bindings that override `bindings` in that app.
    public var appBindings: [String: AppBindings]

    public init(
        version: Int = 1, enabled: Bool = true, onboardingCompleted: Bool = false,
        triggerButton: TriggerButton = .right, requiredModifier: RequiredModifier = .none,
        toggleShortcut: KeyCombo? = nil,
        holdToOpenMenu: Bool = true, holdDelay: Double = 0.5, excludedApps: [ExcludedApp] = [],
        showTrail: Bool = true,
        trailColor: RGBAColor = .orange, trailWidth: Double = 5, showGestureName: Bool = true,
        feedbackSound: String = "", hapticFeedback: Bool = false,
        appearance: AppearanceMode = .system,
        clickMaxPath: Double = 70, matchMaxDistance: Double = 30,
        customGestures: [CustomGesture] = [],
        personalSamples: [PersonalSample] = [],
        bindings: [String: ActionConfig] = AppConfig.defaultBindings,
        appBindings: [String: AppBindings] = [:]
    ) {
        self.version = version
        self.enabled = enabled
        self.onboardingCompleted = onboardingCompleted
        self.triggerButton = triggerButton
        self.requiredModifier = requiredModifier
        self.toggleShortcut = toggleShortcut
        self.holdToOpenMenu = holdToOpenMenu
        self.holdDelay = holdDelay
        self.excludedApps = excludedApps
        self.showTrail = showTrail
        self.appearance = appearance
        self.trailColor = trailColor
        self.trailWidth = trailWidth
        self.showGestureName = showGestureName
        self.feedbackSound = feedbackSound
        self.hapticFeedback = hapticFeedback
        self.clickMaxPath = clickMaxPath
        self.matchMaxDistance = matchMaxDistance
        self.customGestures = customGestures
        self.personalSamples = personalSamples
        self.bindings = bindings
        self.appBindings = appBindings
    }

    // Valid ranges of the numeric settings, shared by the settings sliders and the decoder
    // (so a hand-edited or imported file cannot set, say, a zero click threshold that turns
    // every slightly moved right click into a gesture, or a negative hold delay).
    public static let clickMaxPathRange = 20.0...250.0
    public static let matchMaxDistanceRange = 10.0...60.0
    /// Seconds.
    public static let holdDelayRange = 0.2...1.5
    public static let trailWidthRange = 2.0...14.0

    public static let defaultBindings: [String: ActionConfig] = [
        "Left": ActionConfig(kind: .tileLeft),
        "Right": ActionConfig(kind: .tileRight),
        "Up": ActionConfig(kind: .maximize),
        "Down": ActionConfig(kind: .minimize),
    ]

    public var recognizerSettings: RecognizerSettings {
        RecognizerSettings(clickMaxPath: clickMaxPath, matchMaxDistance: matchMaxDistance)
    }

    // MARK: Templates

    /// Built-in shapes, the user's custom gestures, then personal calibration samples
    /// (extra templates for existing shapes; samples of deleted shapes are skipped).
    public var allTemplates: [GestureTemplate] {
        shapeTemplates + personalTemplates
    }

    /// Built-in shapes followed by the user's custom gestures, without personal samples.
    public var shapeTemplates: [GestureTemplate] {
        GestureTemplate.builtIn + customGestures.map(\.template)
    }

    private var personalTemplates: [GestureTemplate] {
        personalSamples.compactMap { sample in
            let group = GestureTemplate.builtIn.first { $0.id == sample.gestureID }?.group
                ?? (customGesture(id: sample.gestureID) != nil ? .custom : nil)
            return group.map { GestureTemplate(id: sample.gestureID, group: $0, points: sample.points) }
        }
    }

    public func customGesture(id: String) -> CustomGesture? {
        customGestures.first { $0.id == id }
    }

    /// Name shown to the user: the custom gesture's name, or the built-in template id.
    public func displayName(for gestureID: String) -> String {
        customGesture(id: gestureID)?.name ?? gestureID
    }

    private func gestureExists(_ id: String) -> Bool {
        CustomGesture.isCustomID(id) ? customGesture(id: id) != nil : GestureTemplate.builtIn(id: id) != nil
    }

    // MARK: Bindings

    /// The global action for a gesture.
    public func action(for gestureID: String) -> ActionConfig {
        bindings[gestureID] ?? ActionConfig()
    }

    /// The action in effect for a gesture in an app: the app's override if any, else the global one.
    public func action(for gestureID: String, in bundleID: String?) -> ActionConfig {
        if let bundleID, let override = appBindings[bundleID]?.bindings[gestureID] { return override }
        return action(for: gestureID)
    }

    public func hasOverride(for gestureID: String, in bundleID: String) -> Bool {
        appBindings[bundleID]?.bindings[gestureID] != nil
    }

    /// Gestures that do something globally.
    public var boundGestureIDs: Set<String> {
        boundGestureIDs(in: nil)
    }

    /// Gestures that do something in an app (taking its overrides into account).
    public func boundGestureIDs(in bundleID: String?) -> Set<String> {
        var ids = Set(bindings.filter { $0.value.kind != .none }.keys)
        if let bundleID, let overrides = appBindings[bundleID]?.bindings {
            for (id, action) in overrides {
                if action.kind == .none { ids.remove(id) } else { ids.insert(id) }
            }
        }
        return ids.filter(gestureExists)
    }

    public var trackerSettings: TrackerSettings {
        trackerSettings(in: nil)
    }

    public func trackerSettings(in bundleID: String?) -> TrackerSettings {
        TrackerSettings(
            recognizer: recognizerSettings, boundGestures: boundGestureIDs(in: bundleID),
            holdToOpenMenu: holdToOpenMenu, holdDelay: holdDelay
        )
    }

    /// Whether the app under the cursor matters (exclusions or per-app bindings exist).
    public var needsTargetApp: Bool {
        !excludedApps.isEmpty || !appBindings.isEmpty
    }

    public func isExcluded(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApps.contains { $0.bundleID == bundleID }
    }

    /// Removes a custom gesture together with every binding that refers to it.
    public mutating func removeCustomGesture(id: String) {
        customGestures.removeAll { $0.id == id }
        personalSamples.removeAll { $0.gestureID == id }
        bindings.removeValue(forKey: id)
        for key in appBindings.keys {
            appBindings[key]?.bindings.removeValue(forKey: id)
        }
    }

    // MARK: Coding

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? d.onboardingCompleted
        triggerButton = try c.decodeIfPresent(TriggerButton.self, forKey: .triggerButton) ?? d.triggerButton
        requiredModifier = try c.decodeIfPresent(RequiredModifier.self, forKey: .requiredModifier) ?? d.requiredModifier
        toggleShortcut = try? c.decodeIfPresent(KeyCombo.self, forKey: .toggleShortcut)
        holdToOpenMenu = try c.decodeIfPresent(Bool.self, forKey: .holdToOpenMenu) ?? d.holdToOpenMenu
        holdDelay = try c.decodeIfPresent(Double.self, forKey: .holdDelay) ?? d.holdDelay
        excludedApps = c.decodeLossyArray(ExcludedApp.self, forKey: .excludedApps) ?? d.excludedApps
        showTrail = try c.decodeIfPresent(Bool.self, forKey: .showTrail) ?? d.showTrail
        // An unknown value (e.g. from a newer version) falls back to following macOS.
        appearance = (try? c.decodeIfPresent(AppearanceMode.self, forKey: .appearance)) ?? d.appearance
        trailColor = (try? c.decodeIfPresent(RGBAColor.self, forKey: .trailColor)) ?? d.trailColor
        trailWidth = try c.decodeIfPresent(Double.self, forKey: .trailWidth) ?? d.trailWidth
        showGestureName = try c.decodeIfPresent(Bool.self, forKey: .showGestureName) ?? d.showGestureName
        feedbackSound = try c.decodeIfPresent(String.self, forKey: .feedbackSound) ?? d.feedbackSound
        hapticFeedback = try c.decodeIfPresent(Bool.self, forKey: .hapticFeedback) ?? d.hapticFeedback
        clickMaxPath = try c.decodeIfPresent(Double.self, forKey: .clickMaxPath) ?? d.clickMaxPath
        matchMaxDistance = try c.decodeIfPresent(Double.self, forKey: .matchMaxDistance) ?? d.matchMaxDistance
        customGestures = c.decodeLossyArray(CustomGesture.self, forKey: .customGestures) ?? d.customGestures
        personalSamples = c.decodeLossyArray(PersonalSample.self, forKey: .personalSamples) ?? d.personalSamples
        bindings = try c.decodeIfPresent([String: ActionConfig].self, forKey: .bindings) ?? d.bindings
        appBindings = try c.decodeIfPresent([String: AppBindings].self, forKey: .appBindings) ?? d.appBindings

        clickMaxPath = Self.clamp(clickMaxPath, to: Self.clickMaxPathRange)
        matchMaxDistance = Self.clamp(matchMaxDistance, to: Self.matchMaxDistanceRange)
        holdDelay = Self.clamp(holdDelay, to: Self.holdDelayRange)
        trailWidth = Self.clamp(trailWidth, to: Self.trailWidthRange)
        repairCustomGestureIDs()
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Gives every custom gesture a unique `custom.` id. The app always creates such ids, but a
    /// hand-edited or imported file may not: an id without the prefix is never counted as bound
    /// (see `gestureExists`), and a shared id makes two gestures share, and lose, one binding.
    /// A gesture without the prefix takes its bindings and samples along to the new id, unless
    /// the old key names a built-in shape, which keeps it. For a duplicate, the first gesture
    /// keeps the id and its bindings; the later one starts unbound.
    private mutating func repairCustomGestureIDs() {
        var seen = Set<String>()
        for index in customGestures.indices {
            let oldID = customGestures[index].id
            if CustomGesture.isCustomID(oldID), seen.insert(oldID).inserted { continue }

            let newID = CustomGesture.idPrefix + UUID().uuidString
            customGestures[index].id = newID
            seen.insert(newID)
            guard !CustomGesture.isCustomID(oldID), GestureTemplate.builtIn(id: oldID) == nil else { continue }

            if let action = bindings.removeValue(forKey: oldID) { bindings[newID] = action }
            for key in appBindings.keys {
                if let action = appBindings[key]?.bindings.removeValue(forKey: oldID) {
                    appBindings[key]?.bindings[newID] = action
                }
            }
            for i in personalSamples.indices where personalSamples[i].gestureID == oldID {
                personalSamples[i].gestureID = newID
            }
        }
    }

    public static func decode(_ data: Data) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// Decodes one array element, or nothing if that element is invalid.
private struct LossyElement<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

extension KeyedDecodingContainer {
    /// Decodes an array, dropping the elements that fail to decode, so one bad entry does not
    /// reset the whole list (or the whole file). Nil if the key is missing or not an array.
    fileprivate func decodeLossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T]? {
        guard let elements = try? decodeIfPresent([LossyElement<T>].self, forKey: key) else { return nil }
        return elements.compactMap(\.value)
    }
}

/// Splits a command-line style string into arguments.
/// Supports single quotes, double quotes and backslash escapes; no variable expansion.
public func splitArguments(_ string: String) -> [String] {
    var args: [String] = []
    var current = ""
    var inArgument = false
    var quote: Character?
    var escaping = false

    for ch in string {
        if escaping {
            current.append(ch); escaping = false; inArgument = true
            continue
        }
        if ch == "\\" && quote != "'" {
            escaping = true; inArgument = true
            continue
        }
        if let q = quote {
            if ch == q { quote = nil } else { current.append(ch) }
            continue
        }
        if ch == "\"" || ch == "'" {
            quote = ch; inArgument = true
        } else if ch.isWhitespace {
            if inArgument { args.append(current); current = ""; inArgument = false }
        } else {
            current.append(ch); inArgument = true
        }
    }
    if inArgument { args.append(current) }
    return args
}
