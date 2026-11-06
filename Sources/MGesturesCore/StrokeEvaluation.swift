import Foundation

/// What a stroke would do if it were drawn with the trigger button. Used by the Settings
/// "Try" tab; follows exactly the same rules as `GestureTracker.rightMouseUp`.
public enum StrokeVerdict: Equatable, Sendable {
    /// Shorter than the minimum gesture length: a normal right click.
    case tooShort
    /// No shape within the tolerance: a normal right click.
    case noMatch(closest: String?, distance: Double)
    /// Matches a shape that has no action (in this app): a normal right click.
    case unbound(id: String, distance: Double)
    /// Matches a shape and runs its action.
    case runs(id: String, distance: Double, action: ActionConfig)
}

extension AppConfig {
    /// Evaluates a stroke with this configuration, as if drawn over an app with `bundleID`.
    public func evaluate(_ stroke: [StrokePoint], in bundleID: String? = nil, recognizer: Recognizer? = nil) -> StrokeVerdict {
        let recognizer = recognizer ?? Recognizer(templates: allTemplates)
        switch recognizer.recognize(stroke, settings: recognizerSettings) {
        case .click:
            return .tooShort
        case .unrecognized(let closest, let distance):
            return .noMatch(closest: closest, distance: distance)
        case .gesture(let id, let distance):
            guard boundGestureIDs(in: bundleID).contains(id) else { return .unbound(id: id, distance: distance) }
            return .runs(id: id, distance: distance, action: action(for: id, in: bundleID))
        }
    }
}
