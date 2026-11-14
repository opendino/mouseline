import Foundation
import Testing
@testable import MouseLineCore

struct CalibrationTests {
    /// A slightly wobbly line, like a real hand-drawn stroke (y down).
    func stroke(dx: Double, dy: Double, wobble: Double = 6) -> [StrokePoint] {
        (0...30).map { i in
            let t = Double(i) / 30
            let w = sin(t * .pi * 3) * wobble
            // Wobble perpendicular to the direction of travel.
            return StrokePoint(dx * t + (dy == 0 ? 0 : w), dy * t + (dx == 0 ? 0 : w))
        }
    }

    func vector(for id: String, length: Double = 180) -> (Double, Double) {
        switch id {
        case "Left": return (-length, 0)
        case "Right": return (length, 0)
        case "Up": return (0, -length)
        default: return (0, length)
        }
    }

    @Test func checkAcceptsTheRightShapeAndRejectsOthers() {
        let templates = AppConfig().shapeTemplates
        guard case .accepted = Calibration.check(stroke(dx: -180, dy: 0), expected: "Left", templates: templates) else {
            Issue.record("a left stroke should be accepted for Left"); return
        }
        #expect(Calibration.check(stroke(dx: 180, dy: 0), expected: "Left", templates: templates) == .looksLike("Right"))
        #expect(Calibration.check(stroke(dx: -20, dy: 0, wobble: 0), expected: "Left", templates: templates) == .tooShort)
    }

    @Test func computeStaysWithinBoundsAndKeepsEverySample() {
        let templates = AppConfig().shapeTemplates
        let samples = Calibration.steps.map { id -> (id: String, stroke: [StrokePoint]) in
            let (dx, dy) = vector(for: id)
            return (id, stroke(dx: dx, dy: dy))
        }
        let result = Calibration.compute(samples: samples, templates: templates)
        #expect(Calibration.toleranceRange.contains(result.matchMaxDistance))
        #expect(Calibration.clickMaxPathRange.contains(result.clickMaxPath))
        #expect(result.samples.count == Calibration.steps.count)
    }

    @Test func neatLinesNeverTightenTheTolerance() {
        // Only lines are sampled, so the tolerance must not drop below the default, or curved
        // and custom shapes that matched before would stop being recognized.
        let templates = AppConfig().shapeTemplates
        let samples = Calibration.steps.map { id -> (id: String, stroke: [StrokePoint]) in
            let (dx, dy) = vector(for: id)
            return (id, stroke(dx: dx, dy: dy, wobble: 1))
        }
        let result = Calibration.compute(samples: samples, templates: templates)
        #expect(result.matchMaxDistance >= AppConfig().matchMaxDistance)
        #expect(Calibration.toleranceRange.lowerBound == AppConfig().matchMaxDistance)
    }

    @Test func shortStrokesLowerTheMinimumLength() {
        let templates = AppConfig().shapeTemplates
        func samples(length: Double) -> [(id: String, stroke: [StrokePoint])] {
            Calibration.steps.map { id in
                let (dx, dy) = vector(for: id, length: length)
                return (id, stroke(dx: dx, dy: dy, wobble: 3))
            }
        }
        let short = Calibration.compute(samples: samples(length: 110), templates: templates)
        let long = Calibration.compute(samples: samples(length: 260), templates: templates)
        #expect(short.clickMaxPath < long.clickMaxPath)
        #expect(short.clickMaxPath < 110) // the user's own short strokes still count as gestures
    }

    @Test func personalSamplesBecomeTemplatesAndAreRankedOnce() {
        var config = AppConfig()
        let crooked = stroke(dx: -180, dy: 50, wobble: 0) // a left stroke drifting down
        config.apply(Calibration.Result(
            clickMaxPath: 50, matchMaxDistance: 30,
            samples: [PersonalSample(gestureID: "Left", stroke: crooked)]
        ))
        #expect(config.isCalibrated)
        #expect(config.allTemplates.count == config.shapeTemplates.count + 1)

        let ranked = Recognizer(templates: config.allTemplates).rankedMatches(for: crooked)
        #expect(ranked.first?.id == "Left")
        #expect(ranked.first?.distance ?? 1 < 0.001) // matches its own sample exactly
        #expect(ranked.filter { $0.id == "Left" }.count == 1)

        config.resetRecognition()
        #expect(!config.isCalibrated)
        #expect(config.matchMaxDistance == AppConfig().matchMaxDistance)
    }

    @Test func samplesOfDeletedCustomGesturesAreDropped() {
        var config = AppConfig()
        let custom = CustomGesture(name: "Z", stroke: [StrokePoint(0, 0), StrokePoint(100, 0), StrokePoint(0, 100), StrokePoint(100, 100)])
        config.customGestures = [custom]
        config.personalSamples = [PersonalSample(gestureID: custom.id, points: custom.points)]
        #expect(config.allTemplates.contains { $0.id == custom.id && $0.group == .custom })
        config.removeCustomGesture(id: custom.id)
        #expect(config.personalSamples.isEmpty)
    }

    @Test func oldConfigFilesDecodeWithoutSamples() throws {
        let data = Data(#"{"version":1,"clickMaxPath":70}"#.utf8)
        let config = try AppConfig.decode(data)
        #expect(config.personalSamples.isEmpty)
        let roundTrip = try AppConfig.decode(try {
            var c = config
            c.personalSamples = [PersonalSample(gestureID: "Up", stroke: stroke(dx: 0, dy: -150))]
            return try c.encoded()
        }())
        #expect(roundTrip.personalSamples.count == 1)
    }
}
