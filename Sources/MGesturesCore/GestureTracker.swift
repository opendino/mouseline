import Foundation

/// Per-gesture settings, captured when the right button goes down.
public struct TrackerSettings: Equatable, Sendable {
    public var recognizer: RecognizerSettings
    /// Gesture ids that have an action. Strokes recognized as any other shape act as a normal right click.
    public var boundGestures: Set<String>
    /// Holding the button still for `holdDelay` seconds hands the press to the app (opens the context menu).
    public var holdToOpenMenu: Bool
    public var holdDelay: TimeInterval
    /// How far (in points) the pointer may drift from the starting point and still count as "holding still".
    public var holdMoveTolerance: Double
    /// Upper bound on stored points; longer strokes are thinned out (recognition resamples anyway).
    public var maxPoints: Int

    public init(
        recognizer: RecognizerSettings = .init(), boundGestures: Set<String> = [],
        holdToOpenMenu: Bool = true, holdDelay: TimeInterval = 0.5,
        holdMoveTolerance: Double = 6, maxPoints: Int = 4000
    ) {
        self.recognizer = recognizer
        self.boundGestures = boundGestures
        self.holdToOpenMenu = holdToOpenMenu
        self.holdDelay = holdDelay
        self.holdMoveTolerance = holdMoveTolerance
        self.maxPoints = maxPoints
    }
}

/// The decision logic of the gesture monitor, free of CGEvent so it can be unit-tested.
///
/// The monitor feeds it right-button and Esc events and applies the returned
/// `Output`: what to do with the event itself, plus side effects (trail, keyboard
/// monitoring, running an action).
public struct GestureTracker {
    public enum Phase: Equatable, Sendable {
        /// Not drawing; events pass through.
        case idle
        /// Right button is down and its events are being swallowed.
        case tracking
        /// Esc was pressed; swallow the rest of this press.
        case cancelled
        /// The press was handed to the app (hold-to-open-menu); let the rest of it through.
        case passthrough
    }

    public enum EventDecision: Equatable, Sendable {
        case pass
        case swallow
        /// Replay the swallowed button-down, then let this (button-up) event through.
        case replayDownThenPass
    }

    public enum Effect: Equatable, Sendable {
        case beginTrail(StrokePoint)
        case extendTrail(StrokePoint)
        case endTrail(animated: Bool)
        case setKeyboardMonitoring(Bool)
        case runGesture(id: String, distance: Double)
        case cancelled
        /// Post the swallowed button-down right now (no current event to piggyback on).
        case replayDownNow
    }

    public struct Output: Equatable, Sendable {
        public var decision: EventDecision
        public var effects: [Effect]

        public init(_ decision: EventDecision, _ effects: [Effect] = []) {
            self.decision = decision
            self.effects = effects
        }
    }

    public private(set) var phase = Phase.idle
    public private(set) var points: [StrokePoint] = []
    /// Increases with every tracked press; lets timers detect that they belong to an old press.
    public private(set) var serial = 0

    private var recognizer: Recognizer
    private var settings = TrackerSettings()
    private var start = StrokePoint(0, 0)
    private var maxDisplacement = 0.0

    public init(recognizer: Recognizer = Recognizer()) {
        self.recognizer = recognizer
    }

    /// Replaces the templates (e.g. after custom gestures changed). Takes effect from the next press.
    public mutating func setTemplates(_ templates: [GestureTemplate]) {
        recognizer = Recognizer(templates: templates)
    }

    // MARK: - Inputs

    /// `active` is false when gestures are disabled globally or for the app under the cursor.
    public mutating func rightMouseDown(at p: StrokePoint, settings: TrackerSettings, active: Bool) -> Output {
        // A previous press whose button-up we never saw (e.g. the tap was disabled): drop it.
        let cleanup = phase == .tracking ? reset() : []
        phase = .idle
        guard active else { return Output(.pass, cleanup) }

        self.settings = settings
        serial += 1
        phase = .tracking
        points = [p]
        start = p
        maxDisplacement = 0
        return Output(.swallow, cleanup + [.beginTrail(p), .setKeyboardMonitoring(true)])
    }

    public mutating func rightMouseDragged(to p: StrokePoint) -> Output {
        switch phase {
        case .idle, .passthrough:
            return Output(.pass)
        case .cancelled:
            return Output(.swallow)
        case .tracking:
            guard append(p) else { return Output(.swallow) }
            return Output(.swallow, [.extendTrail(p)])
        }
    }

    public mutating func rightMouseUp(at p: StrokePoint) -> Output {
        switch phase {
        case .idle:
            return Output(.pass)
        case .passthrough:
            phase = .idle
            return Output(.pass)
        case .cancelled:
            phase = .idle
            return Output(.swallow)
        case .tracking:
            append(p)
            let stroke = points
            phase = .idle
            points = []
            if case .gesture(let id, let distance) = recognizer.recognize(stroke, settings: settings.recognizer),
               settings.boundGestures.contains(id) {
                return Output(.swallow, [.endTrail(animated: true), .setKeyboardMonitoring(false), .runGesture(id: id, distance: distance)])
            }
            // A click, an unknown shape, or a shape without an action: behave like a normal right click.
            return Output(.replayDownThenPass, [.endTrail(animated: false), .setKeyboardMonitoring(false)])
        }
    }

    public mutating func escapePressed() -> Output {
        guard phase == .tracking else { return Output(.pass) }
        phase = .cancelled
        points = []
        return Output(.swallow, [.endTrail(animated: false), .setKeyboardMonitoring(false), .cancelled])
    }

    /// Called `settings.holdDelay` seconds after the press with the `serial` it was scheduled for.
    public mutating func holdTimerFired(serial: Int) -> [Effect] {
        guard phase == .tracking, serial == self.serial, settings.holdToOpenMenu,
              maxDisplacement <= settings.holdMoveTolerance
        else { return [] }
        phase = .passthrough
        points = []
        return [.endTrail(animated: false), .setKeyboardMonitoring(false), .replayDownNow]
    }

    /// Abandons the current press (e.g. after the system disabled the event tap).
    public mutating func reset() -> [Effect] {
        let wasTracking = phase == .tracking
        phase = .idle
        points = []
        return wasTracking ? [.endTrail(animated: false), .setKeyboardMonitoring(false)] : []
    }

    // MARK: - Points

    /// Adds a point; returns false if it was a duplicate of the last one.
    @discardableResult
    private mutating func append(_ p: StrokePoint) -> Bool {
        if let last = points.last, last == p { return false }
        points.append(p)
        maxDisplacement = max(maxDisplacement, start.distance(to: p))
        if points.count > settings.maxPoints {
            // Keep every other point (and always the newest one).
            let newest = points[points.count - 1]
            points = stride(from: 0, to: points.count - 1, by: 2).map { points[$0] } + [newest]
        }
        return true
    }
}
