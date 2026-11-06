import AppKit
import Combine
import CoreGraphics
import MGesturesCore
import os

private let log = Logger(subsystem: "dev.mgestures.app", category: "monitor")

/// Connects the system's input events to `GestureTracker` and applies its decisions.
///
/// Two event taps are installed:
/// - a **mouse tap** for the right and the other (middle, back, forward) buttons, always enabled.
///   Only the configured trigger button (`AppConfig.triggerButton`) is ever acted on; every
///   other button passes through untouched, including the buttons 3/4 that the back/forward
///   actions post;
/// - a **keyboard tap** for Esc, enabled *only while a gesture is being drawn*.
///   Outside of a gesture, mgestures does not see the keyboard at all.
@MainActor
final class GestureMonitor {
    /// Marks events we post ourselves (replayed button-downs) so our own tap lets them through.
    private static let replayTag: Int64 = 0x6D67_6573 // "mges"

    private let store: ConfigStore
    private let overlay: TrailOverlay
    /// Called with the gesture id, its match distance and the bundle id of the app that was
    /// under the cursor when the button went down (nil if it was not looked up).
    private let onGesture: (String, Double, String?) -> Void
    private let onCancel: () -> Void

    private var tracker = GestureTracker()
    private var downEvent: CGEvent?
    private var holdTimer: Timer?
    /// CGMouseButton number of the press the tracker is handling. Drag and up events of any
    /// other button pass through, and a press keeps its button even if the trigger setting
    /// changes while it is held.
    private var pressButton: Int64?
    /// App under the cursor at button-down, looked up only when the config needs it.
    private var pressBundleID: String?
    /// Templates waiting to be installed because they changed in the middle of a press.
    private var pendingTemplates: [GestureTemplate]?
    private var cancellables: Set<AnyCancellable> = []

    private var mouseTap: CFMachPort?
    private var keyTap: CFMachPort?
    private var sources: [CFRunLoopSource] = []
    private var retryTimer: Timer?
    private var permissionTimer: Timer?

    /// Called whenever `isRunning` changes (access granted or revoked).
    var onStatusChange: (() -> Void)?
    private(set) var isRunning = false {
        didSet { if oldValue != isRunning { onStatusChange?() } }
    }

    init(store: ConfigStore, overlay: TrailOverlay,
         onGesture: @escaping (_ id: String, _ distance: Double, _ bundleID: String?) -> Void,
         onCancel: @escaping () -> Void) {
        self.store = store
        self.overlay = overlay
        self.onGesture = onGesture
        self.onCancel = onCancel
        observeCustomGestures()
    }

    /// Keeps the recognizer's templates in sync with the custom gestures.
    ///
    /// `@Published` emits before the property is stored, so the new value is taken from the
    /// publisher, not from `store.config`. While a press is being tracked the change is
    /// parked and applied at the next button-down: swapping templates mid-stroke could make
    /// the stroke match a shape that was not bound when the press started. (It would be
    /// harmless — the press's bound set was fixed at button-down — but this keeps every press
    /// consistent from start to end.)
    private func observeCustomGestures() {
        store.$config
            .removeDuplicates { $0.customGestures == $1.customGestures }
            .map(\.allTemplates)
            .sink { [weak self] templates in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.tracker.phase == .tracking {
                        self.pendingTemplates = templates
                    } else {
                        self.pendingTemplates = nil
                        self.tracker.setTemplates(templates)
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// Installs the event taps. Without Accessibility access this fails and is retried
    /// every two seconds, so gestures start working as soon as access is granted.
    func start() {
        guard mouseTap == nil else { return }

        let mouseMask = mask(
            .rightMouseDown, .rightMouseDragged, .rightMouseUp,
            .otherMouseDown, .otherMouseDragged, .otherMouseUp
        )
        guard AXIsProcessTrusted(),
              let mouseTap = makeTap(mask: mouseMask),
              let keyTap = makeTap(mask: mask(.keyDown))
        else {
            log.notice("Event taps unavailable (Accessibility access missing?); retrying")
            scheduleRetry()
            return
        }

        for tap in [mouseTap, keyTap] {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)!
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            sources.append(source)
        }
        CGEvent.tapEnable(tap: mouseTap, enable: true)
        CGEvent.tapEnable(tap: keyTap, enable: false) // only while drawing
        self.mouseTap = mouseTap
        self.keyTap = keyTap

        retryTimer?.invalidate()
        retryTimer = nil
        startPermissionWatch()
        isRunning = true
        log.info("Event taps installed")
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        permissionTimer?.invalidate()
        permissionTimer = nil
        apply(tracker.reset())
        downEvent = nil
        pressButton = nil
        holdTimer?.invalidate()
        for tap in [mouseTap, keyTap].compactMap({ $0 }) {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        for source in sources {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        sources = []
        mouseTap = nil
        keyTap = nil
        isRunning = false
    }

    private func makeTap(mask: CGEventMask) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: gestureTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func mask(_ types: CGEventType...) -> CGEventMask {
        types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                self.start()
            }
        }
    }

    /// If the user revokes Accessibility access while we run, the taps silently stop
    /// receiving events. Notice it, tear down, and wait for access again.
    private func startPermissionWatch() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !AXIsProcessTrusted() else { return }
                log.notice("Accessibility access was revoked")
                self.stop()
                self.start() // fails and schedules a retry
            }
        }
    }

    // MARK: - Event handling (main run loop; must stay fast)

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayTag { return pass }

        let output: GestureTracker.Output
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables taps that respond too slowly; turn the mouse tap back on.
            log.notice("Event tap was disabled by the system; re-enabling")
            if let mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: true) }
            holdTimer?.invalidate()
            apply(tracker.reset())
            downEvent = nil
            pressButton = nil
            return pass

        case .rightMouseDown, .otherMouseDown:
            let config = store.config
            let button = buttonNumber(type: type, event: event)
            guard button == config.triggerButton.buttonNumber else { return pass }
            output = buttonDown(event, button: button, config: config)

        case .rightMouseDragged, .otherMouseDragged:
            guard isPressButton(type: type, event: event) else { return pass }
            output = tracker.rightMouseDragged(to: point(event))

        case .rightMouseUp, .otherMouseUp:
            guard isPressButton(type: type, event: event) else { return pass }
            holdTimer?.invalidate()
            pressButton = nil
            output = tracker.rightMouseUp(at: point(event))

        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventKeycode) == 53 /* kVK_Escape */ else { return pass }
            holdTimer?.invalidate()
            output = tracker.escapePressed()

        default:
            return pass
        }

        apply(output.effects)
        switch output.decision {
        case .pass:
            return pass
        case .swallow:
            return nil
        case .replayDownThenPass:
            if let down = takeDownEvent() { down.tapPostEvent(proxy) }
            return pass
        }
    }

    /// Starts a press of the trigger button: decides whether gestures are active for it and
    /// with which settings.
    private func buttonDown(_ event: CGEvent, button: Int64, config: AppConfig) -> GestureTracker.Output {
        if let templates = pendingTemplates, tracker.phase != .tracking {
            pendingTemplates = nil
            tracker.setTemplates(templates)
        }

        let modifierHeld = config.requiredModifier.isSatisfied(by: event.flags.rawValue)
        // The window-list lookup costs about a millisecond, so do it only when the answer
        // can change something: gestures are on for this press and some app is special.
        var bundleID: String?
        if config.enabled && modifierHeld && config.needsTargetApp {
            bundleID = AppLocator.application(at: event.location)?.bundleIdentifier
        }
        var active = config.enabled && modifierHeld && !config.isExcluded(bundleID: bundleID)
        var settings = config.trackerSettings(in: bundleID)
        // While calibrating, every stroke of the trigger button is measured, wherever it is
        // drawn and even if gestures are off; nothing runs.
        if CalibrationCapture.shared.isActive {
            active = true
            settings.captureStrokes = true
        }

        pressButton = button
        pressBundleID = bundleID
        let output = tracker.rightMouseDown(at: point(event), settings: settings, active: active)
        if output.decision == .swallow {
            downEvent = event.copy()
            scheduleHoldTimer(delay: config.holdDelay, enabled: config.holdToOpenMenu)
        }
        return output
    }

    /// CGMouseButton number of a mouse event (1 = right, 2 = middle, 3/4 = back/forward).
    private func buttonNumber(type: CGEventType, event: CGEvent) -> Int64 {
        switch type {
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp: return 1
        default: return event.getIntegerValueField(.mouseEventButtonNumber)
        }
    }

    /// Whether a drag/up event belongs to the press the tracker is handling.
    private func isPressButton(type: CGEventType, event: CGEvent) -> Bool {
        guard let pressButton else { return false }
        return buttonNumber(type: type, event: event) == pressButton
    }

    private func apply(_ effects: [GestureTracker.Effect]) {
        for effect in effects {
            switch effect {
            case .beginTrail(let p):
                let config = store.config
                if config.showTrail {
                    overlay.begin(at: CGPoint(x: p.x, y: p.y), color: config.trailColor.nsColor, width: config.trailWidth)
                }
            case .extendTrail(let p):
                overlay.add(CGPoint(x: p.x, y: p.y))
            case .endTrail(let animated):
                overlay.end(animated: animated)
            case .setKeyboardMonitoring(let on):
                if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: on) }
            case .runGesture(let id, let distance):
                downEvent = nil
                // Run the action after returning, so the tap callback stays fast.
                let bundleID = pressBundleID
                DispatchQueue.main.async { [onGesture] in onGesture(id, distance, bundleID) }
            case .capturedStroke(let stroke):
                downEvent = nil
                DispatchQueue.main.async { CalibrationCapture.shared.deliver(stroke) }
            case .cancelled:
                downEvent = nil
                DispatchQueue.main.async { [onCancel] in onCancel() }
            case .replayDownNow:
                takeDownEvent()?.post(tap: .cghidEventTap)
            }
        }
    }

    private func scheduleHoldTimer(delay: TimeInterval, enabled: Bool) {
        holdTimer?.invalidate()
        guard enabled else { return }
        let serial = tracker.serial
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.apply(self.tracker.holdTimerFired(serial: serial))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    /// The swallowed button-down, tagged so our own tap ignores it when it comes back around.
    private func takeDownEvent() -> CGEvent? {
        guard let down = downEvent else { return nil }
        downEvent = nil
        down.setIntegerValueField(.eventSourceUserData, value: Self.replayTag)
        return down
    }

    private func point(_ event: CGEvent) -> StrokePoint {
        let p = event.location
        return StrokePoint(p.x, p.y)
    }
}

/// C-compatible trampoline into `GestureMonitor.handle`. The taps' run loop sources are
/// on the main run loop, so this always runs on the main thread.
private func gestureTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<GestureMonitor>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated {
        monitor.handle(proxy: proxy, type: type, event: event)
    }
}

/// Finds which app a click would go to.
@MainActor
enum AppLocator {
    /// The owner of the frontmost normal window under `point` (global CG coordinates),
    /// falling back to the frontmost app.
    static func application(at point: CGPoint) -> NSRunningApplication? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            // The list is ordered front to back.
            for window in windows {
                guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                      let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                      let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: boundsDict),
                      bounds.contains(point)
                else { continue }
                if let alpha = window[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
                return NSRunningApplication(processIdentifier: pid)
            }
        }
        return NSWorkspace.shared.frontmostApplication
    }
}

extension RGBAColor {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .orange
        self.init(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent)
    }
}

/// Routes trigger-button strokes to the calibration screen while it is open.
@MainActor
final class CalibrationCapture {
    static let shared = CalibrationCapture()

    private var handler: (([StrokePoint]) -> Void)?

    var isActive: Bool { handler != nil }

    /// Starts sending strokes to `handler` instead of recognizing them.
    func begin(_ handler: @escaping ([StrokePoint]) -> Void) { self.handler = handler }

    func end() { handler = nil }

    func deliver(_ stroke: [StrokePoint]) { handler?(stroke) }
}
