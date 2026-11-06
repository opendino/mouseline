import AppKit
import MGesturesCore
import SwiftUI

@MainActor
final class TryModel: ObservableObject {
    let drawing = DrawingModel()
    @Published var stroke: [StrokePoint] = []
    @Published var scope: String?
}

/// The Recognition pane: a test area that shows what a stroke would do (nothing is run),
/// and the recognition settings next to it so they can be tuned on the spot.
struct TryView: View {
    @ObservedObject var store: ConfigStore
    @StateObject private var model = TryModel()

    var body: some View {
        Form {
            Section {
                PaneHeader(
                    title: L("Recognition"),
                    subtitle: L("Draw a shape to see how it is recognized. Here you draw with the left mouse button and nothing is run.")
                ) {
                    IconTile(symbol: "scribble.variable", color: .orange, size: 40)
                }
            }

            Section {
                AppScopePicker(title: "Evaluate for", store: store, scope: $model.scope)
                DrawingPad(model: model.drawing, height: 260) { model.stroke = $0 }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                if model.stroke.isEmpty {
                    Text("The result appears here.")
                        .foregroundStyle(.secondary)
                } else {
                    result
                }
            } header: {
                HStack {
                    Text("Test area")
                    Spacer()
                    Button("Clear") {
                        model.drawing.clear()
                        model.stroke = []
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(model.stroke.isEmpty)
                }
            }

            Section {
                LabeledSlider(title: "Minimum gesture length", value: $store.config.clickMaxPath, range: 20...250, format: "%.0f pt")
                LabeledSlider(title: "Recognition tolerance", value: $store.config.matchMaxDistance, range: 10...60, format: "%.0f")
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        let d = AppConfig()
                        store.config.clickMaxPath = d.clickMaxPath
                        store.config.matchMaxDistance = d.matchMaxDistance
                    }
                }
            } header: {
                Text("Sensitivity")
            } footer: {
                Text("Shorter strokes act as a normal click. A lower tolerance means fewer accidental matches, but shapes must be drawn more precisely. Strokes that match no shape, or a shape without an action, also act as a normal click.")
                    .footerStyle()
            }
        }
        .formStyle(.grouped)
    }

    private var scope: String? {
        guard let scope = model.scope, store.config.appBindings[scope] != nil else { return nil }
        return scope
    }

    @ViewBuilder
    private var result: some View {
        let config = store.config
        let recognizer = Recognizer(templates: config.allTemplates)
        let verdict = config.evaluate(model.stroke, in: scope, recognizer: recognizer)
        let ranked = Array(recognizer.rankedMatches(for: model.stroke).prefix(3))

        VStack(alignment: .leading, spacing: 4) {
            verdictLabel(verdict, config: config)
                .font(.headline)
            Text(LF("Length %.0f pt (minimum %.0f) · tolerance %.0f", StrokeGeometry.pathLength(model.stroke), config.clickMaxPath, config.matchMaxDistance))
                .captionStyle()
        }
        .padding(.vertical, 2)

        LabeledContent("Closest shapes") {
            HStack(spacing: 16) {
                ForEach(ranked, id: \.id) { match in
                    let within = match.distance <= config.matchMaxDistance
                    HStack(spacing: 8) {
                        if let template = config.allTemplates.first(where: { $0.id == match.id }) {
                            ShapeTile(points: template.points, size: 30, tint: within ? .green : .secondary)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: config.localizedName(for: match.id))
                            Text(String(format: "%.1f", match.distance))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(within ? Color.green : Color.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func verdictLabel(_ verdict: StrokeVerdict, config: AppConfig) -> some View {
        switch verdict {
        case .tooShort:
            Label(L("Too short — acts as a normal right click"), systemImage: "cursorarrow.click")
                .foregroundStyle(.secondary)
        case .noMatch:
            Label(L("No shape within tolerance — normal right click"), systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        case .unbound(let id, _):
            Label(LF("“%@” has no action — normal right click", config.localizedName(for: id)), systemImage: "circle.slash")
                .foregroundStyle(.orange)
        case .runs(let id, _, let action):
            Label(LF("“%@” → %@", config.localizedName(for: id), L(action.kind.title)), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}
