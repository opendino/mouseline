import AppKit
import SwiftUI

/// A click-through bubble near the bottom of the screen under the cursor that briefly
/// shows the recognized gesture and its action. Liquid Glass on macOS 26 and later
/// (it materializes in and morphs between messages), frosted glass before.
@MainActor
final class HUD {
    static let shared = HUD()

    /// The panel is larger than the bubble so the bubble can grow and animate inside it;
    /// it is transparent and ignores the mouse, so the extra room is invisible.
    private static let panelSize = NSSize(width: 560, height: 140)

    private let model = HUDModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private var orderOutWork: DispatchWorkItem?

    func show(_ title: String, detail: String? = nil, symbol: String? = nil, duration: TimeInterval = 1.1) {
        let panel = self.panel ?? makePanel()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = Self.panelSize
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + max(40, visible.height * 0.08))
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }

        orderOutWork?.cancel()
        panel.orderFrontRegardless()

        let content = HUDContent(title: title, detail: detail, symbol: symbol)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            model.content = content
            model.visible = true
        }

        // Cancel the previous hide, so a second message is not cut short by the first one's timer.
        hideWork?.cancel()
        let hide = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: hide)
    }

    private func hide() {
        withAnimation(.easeIn(duration: 0.25)) {
            model.visible = false
        }
        let orderOut = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        orderOutWork = orderOut
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: orderOut)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // the bubble draws its own; a window shadow would outline the panel
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: HUDStage(model: model))
        self.panel = panel
        return panel
    }
}

struct HUDContent: Equatable {
    var title: String
    var detail: String?
    var symbol: String?
}

@MainActor
final class HUDModel: ObservableObject {
    @Published var content = HUDContent(title: "")
    @Published var visible = false
}

/// The full panel: the bubble near the bottom, appearing and disappearing.
private struct HUDStage: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if model.visible {
                HUDView(title: model.content.title, detail: model.content.detail, symbol: model.content.symbol)
                    .glassAppearance()
                    .transition(.scale(scale: 0.82, anchor: .bottom).combined(with: .opacity))
                    .padding(.bottom, 24)
            }
        }
        .glassGroup()
    }
}

/// The bubble itself: symbol, gesture name and action.
struct HUDView: View {
    let title: String
    let detail: String?
    let symbol: String?

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 26)
                    .contentTransition(.opacity)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .font(.system(size: 14, weight: .semibold))
                if let detail {
                    Text(verbatim: detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .contentTransition(.opacity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .fixedSize()
        .modifier(HUDBackground())
    }
}

/// Liquid Glass capsule on macOS 26+, the HUD blur material before.
private struct HUDBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: Capsule(style: .continuous))
        } else {
            content
                .background(VisualEffectBackground(material: .hudWindow))
                .clipShape(Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        }
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
