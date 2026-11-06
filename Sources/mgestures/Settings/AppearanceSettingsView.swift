import AppKit
import MGesturesCore
import SwiftUI

/// The Appearance pane: trail, gesture name, sound and haptics.
struct AppearanceSettingsView: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section {
                PaneHeader(title: L("Appearance"), subtitle: L("How mgestures looks and sounds while you draw.")) {
                    IconTile(symbol: "paintbrush.pointed.fill", color: .pink, size: 40)
                }
            }

            Section {
                TrailPreview(color: Color(nsColor: store.config.trailColor.nsColor), width: store.config.trailWidth)
                    .frame(height: 110)
                    .opacity(store.config.showTrail ? 1 : 0.35)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                Toggle("Show trail while drawing", isOn: $store.config.showTrail)
                ColorPicker("Trail color", selection: trailColor, supportsOpacity: true)
                    .disabled(!store.config.showTrail)
                LabeledSlider(title: "Trail width", value: $store.config.trailWidth, range: 2...14, format: "%.0f pt")
                    .disabled(!store.config.showTrail)
            } header: {
                Text("Trail")
            }

            Section {
                Toggle("Show gesture name after drawing", isOn: $store.config.showGestureName)
                LabeledContent("Preview") {
                    Button("Show") {
                        HUD.shared.show(L("Left"), detail: L(ActionKind.tileLeft.title), symbol: ActionKind.tileLeft.symbol)
                    }
                    .glassButtonStyle()
                }
            } header: {
                Text("Gesture name")
            }

            Section {
                Picker("Sound", selection: sound) {
                    Text("None").tag("")
                    Divider()
                    ForEach(Feedback.availableSounds, id: \.self) { name in
                        Text(verbatim: name).tag(name)
                    }
                }
                Toggle(isOn: $store.config.hapticFeedback) {
                    Text("Haptic feedback")
                    Text("Force Touch trackpads only")
                }
            } header: {
                Text("Sound and haptics")
            }
        }
        .formStyle(.grouped)
    }

    private var trailColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: store.config.trailColor.nsColor) },
            set: { store.config.trailColor = RGBAColor(NSColor($0)) }
        )
    }

    private var sound: Binding<String> {
        Binding(
            get: { store.config.feedbackSound },
            set: { name in
                store.config.feedbackSound = name
                if !name.isEmpty { Feedback.preview(sound: name) }
            }
        )
    }
}

/// A sample stroke drawn with the chosen trail color and width, glow included.
struct TrailPreview: View {
    let color: Color
    let width: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(white: 0.16), Color(white: 0.09)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            DotGrid(spacing: 16)
                .opacity(0.35)
            Canvas { context, size in
                let w = size.width, h = size.height
                var path = Path()
                path.move(to: CGPoint(x: w * 0.12, y: h * 0.70))
                path.addCurve(
                    to: CGPoint(x: w * 0.50, y: h * 0.38),
                    control1: CGPoint(x: w * 0.22, y: h * 0.18),
                    control2: CGPoint(x: w * 0.36, y: h * 0.20)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.86, y: h * 0.32),
                    control1: CGPoint(x: w * 0.64, y: h * 0.56),
                    control2: CGPoint(x: w * 0.76, y: h * 0.86)
                )
                let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
                var glow = context
                glow.addFilter(.shadow(color: color.opacity(0.9), radius: 5))
                glow.stroke(path, with: .color(color), style: style)

                let r = max(3, width * 1.2)
                let tip = CGPoint(x: w * 0.86, y: h * 0.32)
                glow.fill(Path(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }
}
