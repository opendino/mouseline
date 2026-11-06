import AppKit
import MGesturesCore
import SwiftUI

@MainActor
final class RecordModel: ObservableObject {
    @Published var name = ""
    @Published var stroke: [StrokePoint] = []
    @Published var kind = ActionKind.none
    let drawing = DrawingModel()
}

/// Sheet for recording a custom gesture.
struct RecordGestureView: View {
    /// Strokes shorter than this are too small to be recognized reliably.
    static let minimumLength = 60.0
    /// A best-match distance below this means the new shape would be confused with an existing one.
    static let similarityWarningDistance = 12.0

    @ObservedObject var store: ConfigStore
    @Binding var isPresented: Bool
    @StateObject private var model = RecordModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconTile(symbol: "scribble.variable", color: .orange, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Record a Gesture")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Draw the shape once, in the direction you will draw it with the trigger button.")
                        .captionStyle()
                }
            }

            DrawingPad(model: model.drawing, height: 260) { model.stroke = $0 }

            HStack(alignment: .center) {
                Button("Clear") {
                    model.drawing.clear()
                    model.stroke = []
                }
                Spacer()
                if !model.stroke.isEmpty {
                    ShapeTile(points: model.stroke, size: 40)
                }
            }

            if isTooShort {
                Label("Draw a longer stroke.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            } else if let similar = similarGestureName {
                Label(LF("Very similar to “%@” — they may be confused.", similar), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Form {
                TextField("Name", text: $model.name)
                LabeledContent("Action") {
                    ActionPicker(kind: $model.kind)
                }
            }
            .formStyle(.columns)
            Text("Shortcuts, apps, URLs, commands and scripts can be set up in the list after saving.")
                .captionStyle()

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .controlSize(.large)
        }
        .padding(22)
        .frame(width: 460)
    }

    private var pathLength: Double { StrokeGeometry.pathLength(model.stroke) }
    private var isTooShort: Bool { !model.stroke.isEmpty && pathLength < Self.minimumLength }
    private var trimmedName: String { model.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { pathLength >= Self.minimumLength && !trimmedName.isEmpty }

    private var similarGestureName: String? {
        guard pathLength >= Self.minimumLength,
              let best = Recognizer(templates: store.config.allTemplates).rankedMatches(for: model.stroke).first,
              best.distance < Self.similarityWarningDistance
        else { return nil }
        return store.config.localizedName(for: best.id)
    }

    private func save() {
        guard canSave else { return }
        let gesture = CustomGesture(name: trimmedName, stroke: model.stroke)
        store.config.customGestures.append(gesture)
        if model.kind != .none {
            store.config.bindings[gesture.id] = ActionConfig(kind: model.kind)
        }
        isPresented = false
    }
}
