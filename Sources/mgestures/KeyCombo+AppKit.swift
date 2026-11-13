import AppKit
import MGesturesCore

extension KeyCombo {
    /// The modifier bits we keep (same bit values in NSEvent.ModifierFlags and CGEventFlags).
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(Self.relevantModifiers)
        self.init(
            keyCode: event.keyCode,
            modifiers: UInt64(modifiers.rawValue),
            display: Self.symbols(for: modifiers) + Self.keyName(code: event.keyCode, characters: event.charactersIgnoringModifiers)
        )
    }

    static func symbols(for flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }

    static func keyName(code: UInt16, characters: String?) -> String {
        let named: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
            114: L("Help"), 71: "⌧", 76: "⌤", // Help/Insert, keypad Clear, keypad Enter
        ]
        if let name = named[code] { return name }
        // AppKit reports other special keys as private-use characters (U+F700–U+F8FF) or
        // control characters, which no font draws; the key code is readable at least.
        if let characters, !characters.isEmpty,
           !characters.unicodeScalars.contains(where: { (0xF700...0xF8FF).contains($0.value) || $0.properties.generalCategory == .control }) {
            return characters.uppercased()
        }
        return "Key \(code)"
    }
}
