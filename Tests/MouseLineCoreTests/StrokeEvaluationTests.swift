import Foundation
import Testing
@testable import MouseLineCore

struct StrokeEvaluationTests {
    let finder = "com.apple.finder"

    func line(to end: StrokePoint) -> [StrokePoint] {
        Recognizer.resample([StrokePoint(0, 0), end], count: 40)
    }

    /// Runs a stroke through the real state machine and reports whether an action would run.
    func trackerRuns(_ stroke: [StrokePoint], config: AppConfig, in bundleID: String?) -> String? {
        var tracker = GestureTracker(recognizer: Recognizer(templates: config.allTemplates))
        _ = tracker.rightMouseDown(at: stroke[0], settings: config.trackerSettings(in: bundleID), active: true)
        for p in stroke.dropFirst().dropLast() { _ = tracker.rightMouseDragged(to: p) }
        for effect in tracker.rightMouseUp(at: stroke[stroke.count - 1]).effects {
            if case .runGesture(let id, _) = effect { return id }
        }
        return nil
    }

    @Test func verdicts() {
        var config = AppConfig()
        config.appBindings[finder] = AppBindings(name: "Finder", bindings: ["Left": ActionConfig(kind: .navigateBack), "Right": ActionConfig(kind: .none)])

        #expect(config.evaluate(line(to: StrokePoint(30, 0))) == .tooShort)

        guard case .runs(let id, _, let action) = config.evaluate(line(to: StrokePoint(-300, 0)), in: finder) else {
            Issue.record("expected runs"); return
        }
        #expect(id == "Left")
        #expect(action.kind == .navigateBack)

        guard case .unbound(let unboundID, _) = config.evaluate(line(to: StrokePoint(300, 0)), in: finder) else {
            Issue.record("expected unbound (turned off in Finder)"); return
        }
        #expect(unboundID == "Right")

        guard case .unbound(let gammaID, _) = config.evaluate([StrokePoint(0, 0), StrokePoint(300, 0), StrokePoint(300, 180)]) else {
            Issue.record("expected unbound Gamma"); return
        }
        #expect(gammaID == "Gamma")

        var strict = config
        strict.matchMaxDistance = 1
        guard case .noMatch = strict.evaluate([StrokePoint(0, 300), StrokePoint(75, 0), StrokePoint(150, 180), StrokePoint(225, 0), StrokePoint(300, 300)]) else {
            Issue.record("expected noMatch"); return
        }
    }

    @Test func agreesWithTheRuntime() {
        var config = AppConfig()
        config.appBindings[finder] = AppBindings(name: "Finder", bindings: ["Right": ActionConfig(kind: .none), "Up": ActionConfig(kind: .missionControl)])
        let strokes: [[StrokePoint]] = [
            line(to: StrokePoint(300, 0)), line(to: StrokePoint(-300, 0)), line(to: StrokePoint(0, -300)),
            line(to: StrokePoint(0, 300)), line(to: StrokePoint(20, 0)),
            [StrokePoint(0, 0), StrokePoint(0, 300), StrokePoint(180, 300)],
        ]
        for stroke in strokes {
            for bundle in [nil, finder] {
                let verdict = config.evaluate(stroke, in: bundle)
                let runtime = trackerRuns(stroke, config: config, in: bundle)
                if case .runs(let id, _, _) = verdict {
                    #expect(runtime == id)
                } else {
                    #expect(runtime == nil, "\(verdict)")
                }
            }
        }
    }
}
