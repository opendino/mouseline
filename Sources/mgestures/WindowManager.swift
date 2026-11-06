import AppKit
import ApplicationServices
import os

private let log = Logger(subsystem: "dev.mgestures.app", category: "windows")

/// Moves, resizes and otherwise controls the focused window of the frontmost app through the
/// Accessibility API.
///
/// Every AX call is treated as fallible: many apps (games, Electron shells, Java apps) expose
/// only part of the window attributes, and a failing call must never crash the menu bar app.
@MainActor
enum WindowManager {
    enum Operation {
        case tileLeft, tileRight, tileTop, tileBottom
        case maximize, center, moveToNextDisplay
        case minimize, toggleFullScreen, close
    }

    static func perform(_ op: Operation) {
        guard let window = focusedWindow() else {
            log.debug("No focused window for \(String(describing: op), privacy: .public)")
            return
        }

        switch op {
        case .minimize:
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            return
        case .toggleFullScreen:
            toggleFullScreen(window)
            return
        case .close:
            press(buttonAttribute: kAXCloseButtonAttribute, of: window)
            return
        case .moveToNextDisplay:
            moveToNextDisplay(window)
            return
        case .tileLeft, .tileRight, .tileTop, .tileBottom, .maximize, .center:
            break
        }

        guard let current = frame(of: window) else { return }
        let area = visibleFrame(of: screen(for: current))
        guard !area.isEmpty else { return }
        let target: CGRect
        switch op {
        case .tileLeft: target = CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        case .tileRight: target = CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height)
        case .tileTop: target = CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height / 2)
        // Accessibility coordinates have a top-left origin, so the bottom half starts at midY.
        case .tileBottom: target = CGRect(x: area.minX, y: area.midY, width: area.width, height: area.height / 2)
        case .maximize: target = area
        case .center: target = centered(current.size, in: area)
        case .minimize, .toggleFullScreen, .close, .moveToNextDisplay: return
        }
        setFrame(target, of: window)
    }

    // MARK: - Operations

    /// Moves the window to the next screen in `NSScreen.screens` order (wrapping around),
    /// keeping its position and size proportional to the visible frames so a window tiled
    /// left on one display stays tiled left on the next one.
    private static func moveToNextDisplay(_ window: AXUIElement) {
        let screens = NSScreen.screens
        guard screens.count > 1, let current = frame(of: window) else { return }
        let source = screen(for: current)
        let index = screens.firstIndex { $0 == source } ?? 0
        let from = visibleFrame(of: screens[index])
        let to = visibleFrame(of: screens[(index + 1) % screens.count])
        guard !from.isEmpty, !to.isEmpty else { return }
        setFrame(proportionalFrame(current, from: from, to: to), of: window)
    }

    /// Uses the AXFullScreen attribute when the window supports setting it (standard Cocoa
    /// windows do); otherwise presses the green full-screen button, which is what a user
    /// would do and works for apps that only expose the button.
    private static func toggleFullScreen(_ window: AXUIElement) {
        let attribute = "AXFullScreen" as CFString
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(window, attribute, &settable) == .success, settable.boolValue {
            var value: CFTypeRef?
            var isFullScreen = false
            if AXUIElementCopyAttributeValue(window, attribute, &value) == .success,
               let value, CFGetTypeID(value) == CFBooleanGetTypeID() {
                isFullScreen = CFBooleanGetValue((value as! CFBoolean))
            }
            let newValue = isFullScreen ? kCFBooleanFalse : kCFBooleanTrue
            if let newValue, AXUIElementSetAttributeValue(window, attribute, newValue) == .success { return }
        }
        press(buttonAttribute: kAXFullScreenButtonAttribute, of: window)
    }

    /// Presses one of the window's title bar buttons (close, full screen, …).
    private static func press(buttonAttribute: String, of window: AXUIElement) {
        guard let button = element(buttonAttribute, of: window) else {
            log.debug("Window has no \(buttonAttribute, privacy: .public)")
            return
        }
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        if result != .success {
            log.error("Pressing \(buttonAttribute, privacy: .public) failed: \(result.rawValue)")
        }
    }

    // MARK: - Geometry (pure)

    /// A rectangle of `size` centered in `area`; a window larger than the area is shrunk to fit.
    static func centered(_ size: CGSize, in area: CGRect) -> CGRect {
        let width = min(size.width, area.width)
        let height = min(size.height, area.height)
        return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    }

    /// Maps `rect` from one area to another, keeping its relative position and size,
    /// then clamps the result so it lies entirely inside `to`.
    static func proportionalFrame(_ rect: CGRect, from: CGRect, to: CGRect) -> CGRect {
        let scaleX = to.width / from.width
        let scaleY = to.height / from.height
        let width = min(rect.width * scaleX, to.width)
        let height = min(rect.height * scaleY, to.height)
        var x = to.minX + (rect.minX - from.minX) * scaleX
        var y = to.minY + (rect.minY - from.minY) * scaleY
        x = min(max(x, to.minX), to.maxX - width)
        y = min(max(y, to.minY), to.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Accessibility helpers

    private static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return element(kAXFocusedWindowAttribute, of: AXUIElementCreateApplication(app.processIdentifier))
    }

    /// Reads an attribute whose value is itself an AX element (window, button, …).
    private static func element(_ attribute: String, of parent: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    /// Reads an AXValue-typed attribute (position, size); nil if missing or of another type.
    private static func axValue(_ attribute: String, of element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        return (value as! AXValue)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let posValue = axValue(kAXPositionAttribute, of: window),
              let sizeValue = axValue(kAXSizeAttribute, of: window)
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue, .cgPoint, &origin), AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func setFrame(_ rect: CGRect, of window: AXUIElement) {
        var origin = rect.origin
        var size = rect.size
        guard let pos = AXValueCreate(.cgPoint, &origin), let sz = AXValueCreate(.cgSize, &size) else { return }
        // Size → position → size: some apps clamp the size to the screen the window is
        // currently on, so the size is applied again after moving.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sz)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pos)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sz)
    }

    // MARK: - Screen geometry (Accessibility uses top-left-origin global coordinates)

    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private static func cgRect(fromCocoa r: NSRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// The screen showing the largest part of the window.
    private static func screen(for windowFrame: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            area(cgRect(fromCocoa: a.frame).intersection(windowFrame)) < area(cgRect(fromCocoa: b.frame).intersection(windowFrame))
        } ?? NSScreen.main
    }

    private static func visibleFrame(of screen: NSScreen?) -> CGRect {
        guard let screen = screen ?? NSScreen.main else { return .zero }
        return cgRect(fromCocoa: screen.visibleFrame)
    }

    private static func area(_ r: CGRect) -> CGFloat {
        r.isNull ? 0 : r.width * r.height
    }
}
