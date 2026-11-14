import Foundation
import Testing
@testable import MouseLineCore

struct GestureTrackerTests {
    let settings = TrackerSettings(boundGestures: ["Left", "Right"])

    /// Draws a horizontal line of `length` points to the right, starting at (100, 100).
    func drawRight(_ t: inout GestureTracker, length: Double = 300, settings: TrackerSettings? = nil) -> GestureTracker.Output {
        _ = t.rightMouseDown(at: StrokePoint(100, 100), settings: settings ?? self.settings, active: true)
        var x = 100.0
        while x < 100 + length {
            x += 10
            _ = t.rightMouseDragged(to: StrokePoint(x, 100))
        }
        return t.rightMouseUp(at: StrokePoint(x, 100))
    }

    @Test func pressStartsTrackingAndKeyboardMonitoring() {
        var t = GestureTracker()
        let out = t.rightMouseDown(at: StrokePoint(5, 5), settings: settings, active: true)
        #expect(out.decision == .swallow)
        #expect(out.effects == [.beginTrail(StrokePoint(5, 5)), .setKeyboardMonitoring(true)])
        #expect(t.phase == .tracking)
    }

    @Test func boundGestureRunsAction() {
        var t = GestureTracker()
        let out = drawRight(&t)
        #expect(out.decision == .swallow)
        #expect(out.effects.contains(.setKeyboardMonitoring(false)))
        #expect(out.effects.contains { if case .runGesture(id: "Right", _) = $0 { return true }; return false })
        #expect(t.phase == .idle)
    }

    @Test func unboundGestureActsAsRightClick() {
        var t = GestureTracker()
        let out = drawRight(&t, settings: TrackerSettings(boundGestures: ["Up"]))
        #expect(out.decision == .replayDownThenPass)
        #expect(!out.effects.contains { if case .runGesture = $0 { return true }; return false })
    }

    @Test func shortStrokeActsAsRightClick() {
        var t = GestureTracker()
        let out = drawRight(&t, length: 20)
        #expect(out.decision == .replayDownThenPass)
        #expect(out.effects == [.endTrail(animated: false), .setKeyboardMonitoring(false)])
    }

    @Test func inactivePassesEverythingThrough() {
        var t = GestureTracker()
        #expect(t.rightMouseDown(at: StrokePoint(0, 0), settings: settings, active: false) == .init(.pass))
        #expect(t.rightMouseDragged(to: StrokePoint(300, 0)) == .init(.pass))
        #expect(t.rightMouseUp(at: StrokePoint(300, 0)) == .init(.pass))
    }

    @Test func escapeCancelsAndSwallowsTheRestOfThePress() {
        var t = GestureTracker()
        _ = t.rightMouseDown(at: StrokePoint(0, 0), settings: settings, active: true)
        _ = t.rightMouseDragged(to: StrokePoint(100, 0))
        let esc = t.escapePressed()
        #expect(esc.decision == .swallow)
        #expect(esc.effects == [.endTrail(animated: false), .setKeyboardMonitoring(false), .cancelled])
        #expect(t.rightMouseDragged(to: StrokePoint(200, 0)) == .init(.swallow))
        #expect(t.rightMouseUp(at: StrokePoint(300, 0)) == .init(.swallow))
        #expect(t.phase == .idle)
    }

    @Test func escapeWhileIdlePassesThrough() {
        var t = GestureTracker()
        #expect(t.escapePressed() == .init(.pass))
    }

    @Test func holdingStillHandsThePressToTheApp() {
        var t = GestureTracker()
        _ = t.rightMouseDown(at: StrokePoint(100, 100), settings: settings, active: true)
        _ = t.rightMouseDragged(to: StrokePoint(103, 101)) // tiny jitter is fine
        #expect(t.holdTimerFired(serial: t.serial) == [.endTrail(animated: false), .setKeyboardMonitoring(false), .replayDownNow])
        #expect(t.phase == .passthrough)
        // The rest of the press goes to the app untouched.
        #expect(t.rightMouseDragged(to: StrokePoint(150, 150)) == .init(.pass))
        #expect(t.rightMouseUp(at: StrokePoint(150, 150)) == .init(.pass))
        #expect(t.phase == .idle)
    }

    @Test func holdTimerIgnoredOnceDrawingStarted() {
        var t = GestureTracker()
        _ = t.rightMouseDown(at: StrokePoint(100, 100), settings: settings, active: true)
        _ = t.rightMouseDragged(to: StrokePoint(130, 100))
        _ = t.rightMouseDragged(to: StrokePoint(101, 100)) // came back, but already moved away once
        #expect(t.holdTimerFired(serial: t.serial) == [])
        #expect(t.phase == .tracking)
    }

    @Test func holdTimerIgnoredWhenDisabledOrStale() {
        var t = GestureTracker()
        var noHold = settings
        noHold.holdToOpenMenu = false
        _ = t.rightMouseDown(at: StrokePoint(0, 0), settings: noHold, active: true)
        #expect(t.holdTimerFired(serial: t.serial) == [])

        _ = t.rightMouseUp(at: StrokePoint(0, 0))
        let oldSerial = t.serial
        _ = t.rightMouseDown(at: StrokePoint(0, 0), settings: settings, active: true)
        #expect(t.holdTimerFired(serial: oldSerial) == [])
        #expect(t.phase == .tracking)
    }

    @Test func missedButtonUpIsCleanedUpOnNextPress() {
        var t = GestureTracker()
        _ = t.rightMouseDown(at: StrokePoint(0, 0), settings: settings, active: true)
        let out = t.rightMouseDown(at: StrokePoint(50, 50), settings: settings, active: true)
        #expect(out.effects.first == .endTrail(animated: false))
        #expect(out.effects.contains(.beginTrail(StrokePoint(50, 50))))
        #expect(t.points == [StrokePoint(50, 50)])
    }

    @Test func resetEndsTrailOnlyWhenTracking() {
        var t = GestureTracker()
        #expect(t.reset() == [])
        _ = t.rightMouseDown(at: StrokePoint(0, 0), settings: settings, active: true)
        #expect(t.reset() == [.endTrail(animated: false), .setKeyboardMonitoring(false)])
        #expect(t.phase == .idle)
    }

    @Test func duplicatePointsAreIgnored() {
        var t = GestureTracker()
        _ = t.rightMouseDown(at: StrokePoint(0, 0), settings: settings, active: true)
        #expect(t.rightMouseDragged(to: StrokePoint(0, 0)).effects == [])
        #expect(t.points.count == 1)
    }

    @Test func longStrokesAreThinnedOut() {
        var t = GestureTracker()
        var s = settings
        s.maxPoints = 100
        _ = t.rightMouseDown(at: StrokePoint(0, 0), settings: s, active: true)
        for i in 1...1000 { _ = t.rightMouseDragged(to: StrokePoint(Double(i), 0)) }
        #expect(t.points.count <= 100)
        #expect(t.points.first == StrokePoint(0, 0))
        #expect(t.points.last == StrokePoint(1000, 0))
        // Still recognized after thinning.
        let out = t.rightMouseUp(at: StrokePoint(1000, 0))
        #expect(out.effects.contains { if case .runGesture(id: "Right", _) = $0 { return true }; return false })
    }
}

struct CaptureModeTests {
    func run(_ points: [StrokePoint], capture: Bool) -> GestureTracker.Output {
        var tracker = GestureTracker(recognizer: Recognizer())
        let settings = TrackerSettings(boundGestures: ["Left"], captureStrokes: capture)
        _ = tracker.rightMouseDown(at: points[0], settings: settings, active: true)
        for p in points.dropFirst().dropLast() { _ = tracker.rightMouseDragged(to: p) }
        return tracker.rightMouseUp(at: points[points.count - 1])
    }

    @Test func capturesStrokesInsteadOfRunningThem() {
        let left = (0...20).map { StrokePoint(Double(-$0 * 10), 0) }
        let output = run(left, capture: true)
        #expect(output.decision == .swallow)
        #expect(output.effects.contains { if case .capturedStroke = $0 { return true } else { return false } })
        #expect(!output.effects.contains { if case .runGesture = $0 { return true } else { return false } })
        // Without capture the same stroke runs its action.
        #expect(run(left, capture: false).effects.contains { if case .runGesture(let id, _) = $0 { return id == "Left" } else { return false } })
    }

    @Test func shortPressesStayClicksWhileCapturing() {
        let tap = [StrokePoint(0, 0), StrokePoint(3, 1), StrokePoint(4, 1)]
        let output = run(tap, capture: true)
        #expect(output.decision == .replayDownThenPass)
        #expect(!output.effects.contains { if case .capturedStroke = $0 { return true } else { return false } })
    }
}
