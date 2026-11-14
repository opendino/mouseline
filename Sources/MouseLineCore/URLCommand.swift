import Foundation

/// Commands other apps (Raycast, Alfred, Shortcuts, scripts) can send with a
/// `mouseline://` URL, e.g. `open mouseline://toggle`.
///
/// Only harmless commands exist: switching gestures on or off and opening windows. Nothing
/// that runs an action, so a web page that opens such a link cannot make MouseLine do more
/// than a menu click could.
public enum URLCommand: Equatable, Sendable {
    /// `mouseline://enable`, `mouseline://disable`, `mouseline://toggle`
    case setEnabled(Bool?)
    /// `mouseline://toggle-app` — gestures on/off in the frontmost app (its exclusion).
    case toggleFrontmostApp
    /// `mouseline://settings`, optionally with a pane: `mouseline://settings/calibration`
    case openSettings(pane: String?)
    /// `mouseline://welcome`
    case openWelcome

    public static let scheme = "mouseline"

    /// Settings panes that can be opened by name.
    public static let panes: Set<String> = ["general", "gestures", "appearance", "recognition", "calibration", "excluded-apps"]

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        // mouseline://toggle → host "toggle"; mouseline:toggle → no host, path "toggle".
        let parts = ([url.host ?? ""] + url.path.split(separator: "/").map(String.init))
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
        guard let command = parts.first else { return nil }
        switch command {
        case "enable", "on": self = .setEnabled(true)
        case "disable", "off": self = .setEnabled(false)
        case "toggle": self = .setEnabled(nil)
        case "toggle-app", "toggle-frontmost-app": self = .toggleFrontmostApp
        case "settings", "preferences":
            let pane = parts.dropFirst().first
            self = .openSettings(pane: pane.flatMap { Self.panes.contains($0) ? $0 : nil })
        case "welcome", "onboarding": self = .openWelcome
        default: return nil
        }
    }
}
