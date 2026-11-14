import Foundation

/// A built-in shape the recognizer can match.
///
/// The first point is where the stroke starts and the last point is where it ends:
/// direction matters ("Right" and "Left" are different shapes). Coordinates are in
/// arbitrary units (x grows right, y grows down); only proportions matter because
/// strokes are resampled and normalized before comparison.
public struct GestureTemplate: Identifiable, Hashable, Sendable {
    /// Stable identifier, also used as the key in the configuration file.
    public let id: String
    public let group: GestureGroup
    public let points: [StrokePoint]

    public init(id: String, group: GestureGroup, points: [StrokePoint]) {
        self.id = id
        self.group = group
        self.points = points
    }

    /// The same shape drawn in the opposite direction.
    public func reversed(id: String) -> GestureTemplate {
        GestureTemplate(id: id, group: group, points: points.reversed())
    }
}

public enum GestureGroup: String, CaseIterable, Sendable {
    case directional = "Directional"
    case diagonal = "Diagonal"
    case corner = "Corners"
    case uShape = "U / Arch"
    case uRound = "U / Arch (round)"
    case cShape = "C"
    case chevron = "Chevron"
    case custom = "Custom"

    /// The basic view shows only these groups.
    public var isBasic: Bool { self == .directional || self == .diagonal || self == .custom }
}

extension GestureTemplate {
    /// All built-in templates, in display order.
    public static let builtIn: [GestureTemplate] = {
        var all: [GestureTemplate] = []

        func add(_ id: String, _ group: GestureGroup, _ pts: [StrokePoint], reverse reverseID: String? = nil) {
            let t = GestureTemplate(id: id, group: group, points: pts)
            all.append(t)
            if let reverseID { all.append(t.reversed(id: reverseID)) }
        }
        func p(_ x: Double, _ y: Double) -> StrokePoint { StrokePoint(x, y) }
        let arc = StrokeGeometry.arc

        // Straight lines
        add("Up", .directional, [p(0, 100), p(0, 0)])
        add("Down", .directional, [p(0, 0), p(0, 100)])
        add("Left", .directional, [p(100, 0), p(0, 0)])
        add("Right", .directional, [p(0, 0), p(100, 0)])

        // 45° diagonals
        add("Diagonal ↗", .diagonal, [p(0, 100), p(100, 0)])
        add("Diagonal ↖", .diagonal, [p(100, 100), p(0, 0)])
        add("Diagonal ↘", .diagonal, [p(0, 0), p(100, 100)])
        add("Diagonal ↙", .diagonal, [p(100, 0), p(0, 100)])

        // L corners
        add("L Shape", .corner, [p(0, 0), p(0, 100), p(60, 100)], reverse: "L Shape Rev")
        add("Gamma", .corner, [p(0, 0), p(100, 0), p(100, 60)], reverse: "Gamma Rev")
        add("Down-Left", .corner, [p(100, 0), p(100, 100), p(0, 100)], reverse: "Down-Left Rev")
        add("Up-Right", .corner, [p(0, 100), p(0, 0), p(100, 0)], reverse: "Up-Right Rev")

        // U / arch with sharp corners
        add("U Shape", .uShape, [p(0, 0), p(0, 100), p(80, 100), p(80, 0)], reverse: "U Shape Rev")
        add("U Shape Mirror", .uShape, [p(0, 100), p(0, 0), p(80, 0), p(80, 100)], reverse: "U Shape Mirror Rev")

        // U / arch, curved
        add("U Round", .uRound, arc(40, 0, 40, 180, 0, 16), reverse: "U Round Rev")            // bowl
        add("U Round Mirror", .uRound, arc(40, 40, 40, 180, 360, 16), reverse: "U Round Mirror Rev") // arch

        // C shapes. The arc is intentionally wide (~300°, almost a full circle) and the
        // chevron tip intentionally deep: when either was narrow/shallow, hand-drawn
        // C shapes and chevrons were confused with each other. Run the tests before
        // changing these.
        add("C Shape", .cShape, arc(27.5, 50, 55, -30, -330, 16), reverse: "C Shape Rev")  // opens to the right
        add("C Mirror", .cShape, arc(-27.5, 50, 55, 210, 510, 16), reverse: "C Mirror Rev") // opens to the left

        // Chevrons (> and <)
        add("Chevron Right", .chevron, [p(0, 0), p(95, 55), p(0, 110)], reverse: "Chevron Right Rev")
        add("Chevron Left", .chevron, [p(95, 0), p(0, 55), p(95, 110)], reverse: "Chevron Left Rev")

        return all
    }()

    public static func builtIn(id: String) -> GestureTemplate? {
        builtIn.first { $0.id == id }
    }
}
