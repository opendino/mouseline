import AppKit
import MGesturesCore
import SwiftUI

@MainActor
final class TryModel: ObservableObject {
    let drawing = DrawingModel()
    @Published var stroke: [StrokePoint] = []
    @Published var scope: String?
}

/// The Try tab: draw a stroke and see what mgestures would do with it, without running anything.
struct TryView: View {
    @ObservedObject var store: ConfigStore
    @StateObject private var model = TryModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Draw a shape to see how it is recognized. Here you draw with the left mouse button and nothing is run.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                AppScopePicker(title: "Evaluate for", store: store, scope: $model.scope)
                    .frame(maxWidth: 340)
                Spacer()
                Button("Clear") {
                    model.drawing.clear()
                    model.stroke = []
                }
            }

            DrawingPad(model: model.drawing, height: 300) { model.stroke = $0 }

            if !model.stroke.isEmpty {
                result
            }
            Spacer(minLength: 0)
        }
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

        VStack(alignment: .leading, spacing: 10) {
            verdictLabel(verdict, config: config)
                .font(.headline)

            Text(LF("Length %.0f pt (minimum %.0f) · tolerance %.0f", StrokeGeometry.pathLength(model.stroke), config.clickMaxPath, config.matchMaxDistance))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 18) {
                ForEach(ranked, id: \.id) { match in
                    HStack(spacing: 8) {
                        if let template = config.allTemplates.first(where: { $0.id == match.id }) {
                            ShapePreview(points: template.points)
                                .frame(width: 30, height: 30)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: config.localizedName(for: match.id))
                            Text(String(format: "%.1f", match.distance))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(match.distance <= config.matchMaxDistance ? Color.green : Color.secondary)
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
