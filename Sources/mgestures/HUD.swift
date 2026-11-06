import AppKit
import SwiftUI

/// A click-through, frosted-glass bubble near the bottom of the screen under the cursor
/// that briefly shows the recognized gesture and its action, like the system's own HUDs.
@MainActor
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private var host: NSHostingView<HUDView>?
    private var hideWork: DispatchWorkItem?

    func show(_ title: String, detail: String? = nil, symbol: String? = nil, duration: TimeInterval = 1.1) {
        let panel = self.panel ?? makePanel()
        guard let host else { return }
        // Setting rootView updates synchronously, so the size below is the new one.
        host.rootView = HUDView(title: title, detail: detail, symbol: symbol)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + max(80, visible.height * 0.12))
        let wasVisible = panel.isVisible && panel.alphaValue > 0.01
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        if !wasVisible {
            panel.alphaValue = 0
            panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y - 8))
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(origin)
        }

        // Cancel the previous hide, so a second message is not cut short by the first one's timer.
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                panel.animator().alphaValue = 0
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: HUDView(title: "", detail: nil, symbol: nil))
        panel.contentView = host
        self.host = host
        self.panel = panel
        return panel
    }
}

struct HUDView: View {
    let title: String
    let detail: String?
    let symbol: String?

    var body: some View {
        HStack(spacing: 12) {
            if let symbol = symbol {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 26)
                    .foregroundStyle(.primary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .font(.system(size: 14, weight: .semibold))
                if let detail = detail {
                    Text(verbatim: detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .fixedSize()
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
    }
}

/// NSVisualEffectView for SwiftUI backgrounds (vibrancy and blur behind the window).
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}
