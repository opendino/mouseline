import AppKit

/// A small, click-through label in the top-left corner that briefly shows the recognized gesture.
@MainActor
final class HUD {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var hideWork: DispatchWorkItem?

    func show(_ text: String, duration: TimeInterval = 1.2) {
        let panel = self.panel ?? makePanel()
        guard let label else { return }

        label.stringValue = text
        label.sizeToFit()
        let padding = NSSize(width: 14, height: 8)
        let size = NSSize(width: label.frame.width + padding.width * 2, height: label.frame.height + padding.height * 2)
        label.setFrameOrigin(NSPoint(x: padding.width, y: padding.height))

        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: visible.minX + 20, y: visible.maxY - 20 - size.height, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()

        // Cancel the previous hide, so a second message is not cut short by the first one's timer.
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let background = NSView()
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        background.layer?.cornerRadius = 8
        panel.contentView = background

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .white
        background.addSubview(label)

        self.panel = panel
        self.label = label
        return panel
    }
}
