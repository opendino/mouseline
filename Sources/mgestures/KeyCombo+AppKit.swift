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
        ]
        if let name = named[code] { return name }
        if let characters, !characters.isEmpty { return characters.uppercased() }
        return "Key \(code)"
    }
}
