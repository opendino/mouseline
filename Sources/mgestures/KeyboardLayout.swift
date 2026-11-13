import Carbon
import CoreGraphics
import Foundation

/// Finds which key types a character on the user's current keyboard layout.
///
/// Virtual key codes name physical keys (the kVK_ANSI_* constants are US positions), but
/// apps match menu shortcuts on the *character* the active layout produces for a key. On
/// Turkish F the US "[" key types "q", so posting ⌘ + kVK_ANSI_LeftBracket there sends ⌘Q
/// and quits the app. Synthetic shortcuts therefore look their key up per layout.
@MainActor
enum KeyboardLayout {
    /// The key code that types `character` without modifiers on the current layout, or nil
    /// when no key does (e.g. "[" needs ⌥ on German and Turkish layouts).
    static func keyCode(for character: Character) -> CGKeyCode? {
        guard let layoutData = currentLayoutData() else { return nil }
        return keyCode(for: String(character), in: layoutData)
    }

    /// The `uchr` data of the current layout. Input methods (e.g. Japanese) can report a
    /// source without it; the ASCII-capable layout they type through is used then.
    private static func currentLayoutData() -> Data? {
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let data = unicodeLayoutData(of: source) {
            return data
        }
        if let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
           let data = unicodeLayoutData(of: source) {
            return data
        }
        return nil
    }

    private static func unicodeLayoutData(of source: TISInputSource) -> Data? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        // The property is a CFData owned by the input source ("Get" rule), so it is not released.
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }

    private static func keyCode(for target: String, in layoutData: Data) -> CGKeyCode? {
        layoutData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> CGKeyCode? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            let keyboardType = UInt32(LMGetKbdType())
            for code: UInt16 in 0...127 {
                var deadKeyState: UInt32 = 0
                var length: Int = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDown), 0, keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                    characters.count, &length, &characters
                )
                guard status == noErr, length > 0 else { continue }
                if String(utf16CodeUnits: characters, count: Int(length)) == target { return CGKeyCode(code) }
            }
            return nil
        }
    }
}
