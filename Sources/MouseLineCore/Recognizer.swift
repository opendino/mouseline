import Foundation

/// Thresholds that decide between "click", "gesture" and "not recognized".
public struct RecognizerSettings: Equatable, Sendable {
    /// Strokes shorter than this (total travelled distance, in points) are clicks, not gestures.
    public var clickMaxPath: Double
    /// If the best template is further away than this (in normalized units), the stroke is not recognized.
    public var matchMaxDistance: Double

    public init(clickMaxPath: Double = 70, matchMaxDistance: Double = 30) {
        self.clickMaxPath = clickMaxPath
        self.matchMaxDistance = matchMaxDistance
    }
}

public enum Recognition: Equatable, Sendable {
    /// The stroke is too short to be a gesture.
    case click
    /// The stroke is long enough but matches no template closely enough.
    case unrecognized(closest: String?, distance: Double)
    /// The stroke matched a template.
    case gesture(id: String, distance: Double)
}

/// A rotation-*sensitive* variant of the $1 Unistroke Recognizer.
///
/// Strokes are resampled to a fixed number of points, centered on their centroid and
/// scaled uniformly (aspect ratio preserved, so straight lines stay straight), then
/// compared point-by-point with each template. Unlike the original $1 algorithm there
/// is no rotation normalization: direction and mirroring are meaningful.
public struct Recognizer: Sendable {
    public static let resampleCount = 32
    public static let referenceSize = 100.0

    public struct PreparedTemplate: Sendable {
        public let id: String
        public let points: [StrokePoint]
    }

    public let templates: [PreparedTemplate]

    public init(templates: [GestureTemplate] = GestureTemplate.builtIn) {
        self.templates = templates.map { PreparedTemplate(id: $0.id, points: Self.prepare($0.points)) }
    }

    public func recognize(_ stroke: [StrokePoint], settings: RecognizerSettings = .init()) -> Recognition {
        guard stroke.count >= 2, StrokeGeometry.pathLength(stroke) >= settings.clickMaxPath else {
            return .click
        }
        guard let best = rankedMatches(for: stroke).first else {
            return .unrecognized(closest: nil, distance: .infinity)
        }
        if best.distance > settings.matchMaxDistance {
            return .unrecognized(closest: best.id, distance: best.distance)
        }
        return .gesture(id: best.id, distance: best.distance)
    }

    /// Every shape sorted by distance to the stroke (closest first). A shape with several
    /// templates (personal calibration samples) appears once, with its closest template.
    public func rankedMatches(for stroke: [StrokePoint]) -> [(id: String, distance: Double)] {
        let sample = Self.prepare(stroke)
        var seen = Set<String>()
        return templates
            .map { (id: $0.id, distance: Self.pathDistance(sample, $0.points)) }
            .enumerated()
            // Stable sort: on equal distance, keep template declaration order.
            .sorted { $0.element.distance != $1.element.distance ? $0.element.distance < $1.element.distance : $0.offset < $1.offset }
            .map(\.element)
            .filter { seen.insert($0.id).inserted }
    }

    // MARK: - Pipeline

    public static func prepare(_ points: [StrokePoint]) -> [StrokePoint] {
        normalize(resample(points, count: resampleCount), to: referenceSize)
    }

    /// Reduces the path to `n` points equally spaced along the travelled distance.
    public static func resample(_ points: [StrokePoint], count n: Int) -> [StrokePoint] {
        precondition(n >= 2, "resample count must be at least 2")
        guard let first = points.first else { return [] }
        guard points.count >= 2 else { return Array(repeating: first, count: n) }

        var cumulative = [0.0]
        cumulative.reserveCapacity(points.count)
        for i in 1..<points.count {
            cumulative.append(cumulative[i - 1] + points[i - 1].distance(to: points[i]))
        }
        let total = cumulative[cumulative.count - 1]
        guard total > 1e-9 else { return Array(repeating: first, count: n) }

        var out: [StrokePoint] = []
        out.reserveCapacity(n)
        var seg = 0
        for i in 0..<n {
            let target = total * Double(i) / Double(n - 1)
            while seg < points.count - 2 && cumulative[seg + 1] < target { seg += 1 }
            let segLength = cumulative[seg + 1] - cumulative[seg]
            let t = segLength > 1e-9 ? (target - cumulative[seg]) / segLength : 0
            let a = points[seg], b = points[seg + 1]
            out.append(StrokePoint(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y)))
        }
        return out
    }

    /// Centers on the centroid and scales uniformly so the larger bounding-box side equals `size`.
    public static func normalize(_ points: [StrokePoint], to size: Double) -> [StrokePoint] {
        guard !points.isEmpty else { return [] }
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        var cx = 0.0, cy = 0.0
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
            cx += p.x; cy += p.y
        }
        cx /= Double(points.count)
        cy /= Double(points.count)
        let scale = size / max(maxX - minX, maxY - minY, 1e-6)
        return points.map { StrokePoint(($0.x - cx) * scale, ($0.y - cy) * scale) }
    }

    /// Mean point-to-point distance between two equally sized paths.
    public static func pathDistance(_ a: [StrokePoint], _ b: [StrokePoint]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return .infinity }
        var sum = 0.0
        for i in 0..<n { sum += a[i].distance(to: b[i]) }
        return sum / Double(n)
    }
}
