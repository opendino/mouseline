import AppKit
import QuartzCore

/// Draws the stroke being drawn as a glowing line with a dot at its head.
///
/// One transparent, click-through window per screen (a single window spanning several
/// screens is unreliable when "Displays have separate Spaces" is on). Points arrive in
/// global CoreGraphics coordinates (origin top-left of the main screen, y down).
@MainActor
final class TrailOverlay {
    /// Points closer than this to the previous one are not drawn (keeps paths small).
    private static let minSpacing: CGFloat = 1.5
    /// Beyond this many points the trail is thinned out by half.
    private static let maxPoints = 3000

    private var windows: [OverlayWindow] = []
    private var points: [CGPoint] = []
    private var active = false
    private var generation = 0

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildWindows() }
        }
    }

    func begin(at point: CGPoint, color: NSColor, width: Double) {
        generation += 1
        if windows.isEmpty { rebuildWindows() }
        points = [point]
        active = true
        for w in windows {
            w.alphaValue = 1
            w.configure(color: color, width: width)
            w.reset()
            if w.isNear(point) { w.update(points: points) }
            w.orderFrontRegardless()
        }
    }

    func add(_ point: CGPoint) {
        guard active, let last = points.last else { return }
        if hypot(point.x - last.x, point.y - last.y) < Self.minSpacing { return }
        points.append(point)
        if points.count > Self.maxPoints {
            points = stride(from: 0, to: points.count - 1, by: 2).map { points[$0] } + [point]
        }
        // Only redraw screens the stroke has reached; others stay empty.
        for w in windows where w.hasContent || w.isNear(point) {
            w.update(points: points)
        }
    }

    func end(animated: Bool) {
        guard active else { return }
        active = false
        points = []
        let current = generation
        guard animated else {
            windows.forEach { $0.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            windows.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A new stroke may have started during the fade; leave it alone.
                guard let self, self.generation == current else { return }
                self.windows.forEach { $0.orderOut(nil); $0.alphaValue = 1 }
            }
        })
    }

    private func rebuildWindows() {
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map { OverlayWindow(screen: $0) }
        active = false
    }
}

private final class OverlayWindow: NSWindow {
    private let line = CAShapeLayer()
    private let head = CAShapeLayer()
    private var headRadius: CGFloat = 6
    /// This screen's frame in global CG coordinates, grown by the glow margin.
    private var reach: CGRect = .null
    private(set) var hasContent = false

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        contentView = view

        for layer in [line, head] {
            layer.shadowOffset = .zero
            layer.shadowOpacity = 0.9
            layer.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull()]
            view.layer?.addSublayer(layer)
        }
        line.fillColor = nil
        line.lineCap = .round
        line.lineJoin = .round
        line.shadowRadius = 5
        head.shadowRadius = 4
        setFrame(screen.frame, display: false)

        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let f = screen.frame
        reach = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height).insetBy(dx: -40, dy: -40)
    }

    func isNear(_ p: CGPoint) -> Bool { reach.contains(p) }

    func reset() {
        hasContent = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        line.path = nil
        head.path = nil
        CATransaction.commit()
    }

    func configure(color: NSColor, width: Double) {
        line.strokeColor = color.cgColor
        line.shadowColor = color.cgColor
        line.lineWidth = CGFloat(width)
        head.fillColor = color.cgColor
        head.shadowColor = color.cgColor
        headRadius = max(3, CGFloat(width) * 1.2)
    }

    func update(points: [CGPoint]) {
        guard let first = points.first else { return }
        hasContent = true
        let local = points.map(toLocal)
        let path = CGMutablePath()
        path.move(to: local[0])
        if local.count == 1 { path.addLine(to: local[0]) } else { path.addLines(between: local) }

        let tip = toLocal(points.last ?? first)
        let r = headRadius
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        line.path = path
        head.path = CGPath(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r, width: 2 * r, height: 2 * r), transform: nil)
        CATransaction.commit()
    }

    /// Global CoreGraphics coordinates → this window's view coordinates (origin bottom-left).
    private func toLocal(_ p: CGPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.height
        return CGPoint(x: p.x - frame.minX, y: (primaryHeight - p.y) - frame.minY)
    }
}
