import Foundation

/// A stroke the user drew during calibration. It is kept as an extra template for its
/// gesture, so the recognizer also knows how *this* person draws the shape.
public struct PersonalSample: Codable, Equatable, Sendable {
    public var gestureID: String
    /// Normalized points (see `Recognizer.prepare`).
    public var points: [StrokePoint]

    public init(gestureID: String, points: [StrokePoint]) {
        self.gestureID = gestureID
        self.points = points
    }

    /// Creates a sample from a raw drawn stroke (any coordinate space, y down).
    public init(gestureID: String, stroke: [StrokePoint]) {
        self.init(gestureID: gestureID, points: Recognizer.prepare(stroke))
    }
}

/// Fits the recognition settings to the user's own strokes, so nobody has to tune
/// tolerances by hand: the user draws a few basic shapes, and the minimum gesture length,
/// the tolerance and a set of personal templates are derived from them.
public enum Calibration {
    /// The shapes drawn during calibration, in order.
    public static let gestureIDs = ["Left", "Right", "Up", "Down"]
    /// How many times each shape is drawn.
    public static let samplesPerGesture = 2
    /// Strokes shorter than this are rejected while calibrating (they would be clicks).
    public static let minimumStrokeLength = 40.0

    /// Bounds for the fitted values, so one odd stroke cannot make mgestures unusable.
    /// The tolerance never drops below the default: calibration only samples straight lines,
    /// so tightening it would reject curved and custom shapes whose variation was never measured.
    public static let toleranceRange = AppConfig().matchMaxDistance...45.0
    public static let clickMaxPathRange = 35.0...110.0

    /// The drawing order: every shape `samplesPerGesture` times.
    public static var steps: [String] {
        gestureIDs.flatMap { Array(repeating: $0, count: samplesPerGesture) }
    }

    public enum SampleCheck: Equatable, Sendable {
        /// Accepted; `distance` is how far it is from the shape's template.
        case accepted(distance: Double)
        case tooShort
        /// The stroke is closer to another shape than to the expected one.
        case looksLike(String)
    }

    public struct Result: Equatable, Sendable {
        public var clickMaxPath: Double
        public var matchMaxDistance: Double
        public var samples: [PersonalSample]
    }

    /// Checks one stroke drawn for `expected` before it is accepted. `templates` should be
    /// the shapes without personal samples (built-in and custom).
    public static func check(_ stroke: [StrokePoint], expected: String, templates: [GestureTemplate]) -> SampleCheck {
        guard stroke.count >= 2, StrokeGeometry.pathLength(stroke) >= minimumStrokeLength else { return .tooShort }
        guard let best = Recognizer(templates: templates).rankedMatches(for: stroke).first else { return .tooShort }
        guard best.id == expected else { return .looksLike(best.id) }
        return .accepted(distance: best.distance)
    }

    /// Derives the settings from accepted strokes.
    ///
    /// - Tolerance: well above the largest distance between a stroke and its own shape
    ///   (the user's natural variation), but below the distance to the nearest other shape
    ///   where possible, then clamped to `toleranceRange` (which starts at the default, so
    ///   the line samples can only loosen the tolerance, never tighten it).
    /// - Minimum gesture length: a fraction of the user's shortest stroke, so short, quick
    ///   strokes count as gestures while small slips during a click do not.
    public static func compute(samples: [(id: String, stroke: [StrokePoint])], templates: [GestureTemplate]) -> Result {
        let recognizer = Recognizer(templates: templates)
        var ownMax = 0.0
        var otherMin = Double.infinity
        for sample in samples {
            let ranked = recognizer.rankedMatches(for: sample.stroke)
            if let own = ranked.first(where: { $0.id == sample.id }) { ownMax = max(ownMax, own.distance) }
            if let other = ranked.first(where: { $0.id != sample.id }) { otherMin = min(otherMin, other.distance) }
        }

        var tolerance = max(ownMax * 1.5, ownMax + 8)
        if otherMin.isFinite {
            tolerance = min(tolerance, max(ownMax + 4, otherMin * 0.9))
        }
        tolerance = clamp(tolerance, to: toleranceRange).rounded()

        let shortest = samples.map { StrokeGeometry.pathLength($0.stroke) }.min() ?? 175
        let clickMaxPath = clamp(shortest * 0.4, to: clickMaxPathRange).rounded()

        return Result(
            clickMaxPath: clickMaxPath,
            matchMaxDistance: tolerance,
            samples: samples.map { PersonalSample(gestureID: $0.id, stroke: $0.stroke) }
        )
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

extension AppConfig {
    /// True once the user has calibrated (personal samples exist).
    public var isCalibrated: Bool { !personalSamples.isEmpty }

    /// Applies a calibration result.
    public mutating func apply(_ calibration: Calibration.Result) {
        clickMaxPath = calibration.clickMaxPath
        matchMaxDistance = calibration.matchMaxDistance
        personalSamples = calibration.samples
    }

    /// Back to the default recognition settings, without personal samples.
    public mutating func resetRecognition() {
        let defaults = AppConfig()
        clickMaxPath = defaults.clickMaxPath
        matchMaxDistance = defaults.matchMaxDistance
        personalSamples = []
    }
}
