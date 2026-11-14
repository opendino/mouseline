import Foundation

/// A point of a stroke in an arbitrary coordinate space (x grows right, y grows down).
public struct StrokePoint: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ x: Double, _ y: Double) {
        self.init(x: x, y: y)
    }

    public func distance(to other: StrokePoint) -> Double {
        hypot(other.x - x, other.y - y)
    }
}

public enum StrokeGeometry {
    /// Total distance travelled along the stroke.
    public static func pathLength(_ points: [StrokePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var length = 0.0
        for i in 1..<points.count {
            length += points[i - 1].distance(to: points[i])
        }
        return length
    }

    /// Points on a circular arc, from angle `from` to angle `to` (degrees), inclusive.
    public static func arc(
        centerX cx: Double, centerY cy: Double, radius r: Double,
        from a0: Double, to a1: Double, steps: Int
    ) -> [StrokePoint] {
        (0...steps).map { i in
            let t = (a0 + (a1 - a0) * Double(i) / Double(steps)) * .pi / 180
            return StrokePoint(cx + r * cos(t), cy + r * sin(t))
        }
    }
}
