import Foundation

// Localization. Keys are the English text; translations live in
// Support/<language>.lproj/Localizable.strings, copied into the app bundle by
// scripts/build-app.sh. SwiftUI string literals (Text("…"), Button("…"), …) are looked
// up automatically; everything else goes through L() / LF().

/// The localized form of an English string.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// A localized format string filled with arguments, e.g. `LF("Disable in %@", appName)`.
func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: arguments)
}
