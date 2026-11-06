import Foundation
import Testing
@testable import MGesturesCore

/// Deterministic pseudo-random generator so "hand-drawn" strokes are reproducible.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension GestureTemplate: CustomTestStringConvertible {
    public var testDescription: String { id }
}

/// Turns a template into something resembling a real mouse stroke: scaled up to screen
/// size, moved, densely sampled, with jitter on every point.
func handDrawn(_ template: GestureTemplate, scale: Double = 3, jitter: Double, seed: UInt64) -> [StrokePoint] {
    var rng = SeededRandom(seed: seed)
    let dense = Recognizer.resample(template.points, count: 80)
    return dense.map { p in
        StrokePoint(
            500 + p.x * scale + Double.random(in: -jitter...jitter, using: &rng),
            300 + p.y * scale + Double.random(in: -jitter...jitter, using: &rng)
        )
    }
}

struct RecognizerTests {
    let recognizer = Recognizer()

    @Test func templateIDsAreUnique() {
        let ids = GestureTemplate.builtIn.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.count == 32)
    }

    @Test(arguments: GestureTemplate.builtIn)
    func exactTemplateMatchesItself(_ template: GestureTemplate) {
        let stroke = template.points.map { StrokePoint($0.x * 3 + 200, $0.y * 3 + 100) }
        guard case .gesture(let id, let distance) = recognizer.recognize(stroke) else {
            Issue.record("\(template.id): not recognized"); return
        }
        #expect(id == template.id)
        #expect(distance < 1e-6)
    }

    @Test(arguments: GestureTemplate.builtIn)
    func jitteredStrokeIsRecognized(_ template: GestureTemplate) {
        for seed in UInt64(1)...UInt64(10) {
            let result = recognizer.recognize(handDrawn(template, jitter: 6, seed: seed))
            guard case .gesture(let id, _) = result else {
                Issue.record("\(template.id) seed \(seed): not recognized (\(result))")
                continue
            }
            #expect(id == template.id, "seed \(seed)")
        }
    }

    @Test func shortStrokeIsAClick() {
        let stroke = [StrokePoint(100, 100), StrokePoint(110, 104), StrokePoint(120, 100)]
        #expect(recognizer.recognize(stroke) == .click)
        #expect(recognizer.recognize([StrokePoint(5, 5)]) == .click)
        #expect(recognizer.recognize([]) == .click)
    }

    @Test func clickThresholdIsConfigurable() {
        let stroke = [StrokePoint(0, 0), StrokePoint(50, 0)]
        #expect(recognizer.recognize(stroke, settings: .init(clickMaxPath: 70)) == .click)
        guard case .gesture(let id, _) = recognizer.recognize(stroke, settings: .init(clickMaxPath: 40)) else {
            Issue.record("expected a gesture"); return
        }
        #expect(id == "Right")
    }

    @Test func toleranceDecidesWhetherUnknownShapesAreRejected() {
        // "M" is intentionally not a template. With the default (loose) tolerance it is
        // still close enough to the arch; a stricter tolerance rejects it.
        let stroke = [StrokePoint(0, 300), StrokePoint(75, 0), StrokePoint(150, 180), StrokePoint(225, 0), StrokePoint(300, 300)]
        guard case .gesture(let id, let distance) = recognizer.recognize(stroke) else {
            Issue.record("expected a match with the default tolerance"); return
        }
        #expect(id == "U Round Mirror")
        guard case .unrecognized(let closest, _) = recognizer.recognize(stroke, settings: .init(matchMaxDistance: distance - 1)) else {
            Issue.record("expected rejection with a strict tolerance"); return
        }
        #expect(closest == "U Round Mirror")
    }

    @Test func wideZigZagCountsAsHorizontalLine() {
        // Documented behavior (same as the original Hammerspoon script): scaling keeps the
        // aspect ratio, so a wide, low zig-zag is close enough to a straight line.
        let stroke = (0..<12).map { i in StrokePoint(Double(i) * 30, i.isMultiple(of: 2) ? 0 : 200) }
        guard case .gesture(let id, _) = recognizer.recognize(stroke) else {
            Issue.record("not recognized"); return
        }
        #expect(id == "Right")
    }

    @Test func slightlyWobblyHorizontalLineIsRight() {
        let stroke = (0...40).map { i in StrokePoint(Double(i) * 8, sin(Double(i) / 3) * 6) }
        guard case .gesture(let id, _) = recognizer.recognize(stroke) else {
            Issue.record("not recognized"); return
        }
        #expect(id == "Right")
    }

    @Test func resampleProducesEvenlySpacedPoints() {
        let out = Recognizer.resample([StrokePoint(0, 0), StrokePoint(0, 0), StrokePoint(310, 0)], count: 32)
        #expect(out.count == 32)
        #expect(out.first == StrokePoint(0, 0))
        #expect(abs(out.last!.x - 310) < 1e-9)
        for i in 1..<out.count {
            #expect(abs(out[i].distance(to: out[i - 1]) - 10) < 1e-9)
        }
    }
}
