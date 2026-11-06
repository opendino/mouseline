import AppKit
import MGesturesCore
import SwiftUI

@MainActor
final class CalibrationModel: ObservableObject {
    let drawing = DrawingModel()
    @Published private(set) var accepted: [(id: String, stroke: [StrokePoint])] = []
    @Published private(set) var message: String?
    @Published private(set) var result: Calibration.Result?

    let steps = Calibration.steps
    var stepIndex: Int { accepted.count }
    var currentID: String? { stepIndex < steps.count ? steps[stepIndex] : nil }
    var isFinished: Bool { result != nil }

    /// Which repetition of the current shape this is (1-based).
    var repetition: Int {
        guard let id = currentID else { return 0 }
        return accepted.filter { $0.id == id }.count + 1
    }

    func submit(_ stroke: [StrokePoint], templates: [GestureTemplate], config: AppConfig) {
        guard let expected = currentID else { return }
        switch Calibration.check(stroke, expected: expected, templates: templates) {
        case .accepted:
            message = nil
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                accepted.append((expected, stroke))
            }
            if accepted.count == steps.count {
                withAnimation(.easeInOut(duration: 0.3)) {
                    result = Calibration.compute(samples: accepted, templates: templates)
                }
            }
        case .tooShort:
            message = L("Draw a longer stroke.")
        case .looksLike(let other):
            message = LF("That looked like “%@”. Try again.", config.localizedName(for: other))
        }
        // Clear the pad shortly after, so the next stroke starts on a clean surface.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.drawing.clear() }
    }

    func restart() {
        accepted = []
        result = nil
        message = nil
        drawing.clear()
    }
}

/// Sheet that fits the recognition to the user's hand: draw each basic shape twice.
struct CalibrationView: View {
    @ObservedObject var store: ConfigStore
    @Binding var isPresented: Bool
    @StateObject private var model = CalibrationModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let result = model.result {
                summary(result)
            } else {
                drawingStep
            }
            footer
        }
        .padding(24)
        .frame(width: 500)
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "dial.medium.fill", color: .indigo, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Calibrate Gestures")
                    .font(.system(size: 15, weight: .semibold))
                Text("Draw each shape twice, the way you normally would. mgestures adjusts itself to your hand.")
                    .captionStyle()
            }
        }
    }

    // MARK: Drawing

    @ViewBuilder
    private var drawingStep: some View {
        progress

        if let id = model.currentID, let template = GestureTemplate.builtIn.first(where: { $0.id == id }) {
            HStack(spacing: 14) {
                ShapeTile(points: template.points, size: 52)
                    .id(model.stepIndex)
                    .transition(.scale.combined(with: .opacity))
                VStack(alignment: .leading, spacing: 3) {
                    Text(LF("Draw “%@”", L(id)))
                        .font(.system(size: 17, weight: .semibold))
                    Text(LF("%d of %d", model.repetition, Calibration.samplesPerGesture))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }

        DrawingPad(model: model.drawing, height: 230) { stroke in
            model.submit(stroke, templates: store.config.shapeTemplates, config: store.config)
        }

        Group {
            if let message = model.message {
                Label(message, systemImage: "arrow.uturn.backward.circle")
                    .foregroundStyle(.orange)
            } else {
                Label("Draw with the left mouse button, from the dot in the direction of the arrow.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    /// One dot per stroke; filled when accepted.
    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.steps.enumerated()), id: \.offset) { index, _ in
                Capsule()
                    .fill(index < model.stepIndex ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.12)))
                    .frame(width: index == model.stepIndex ? 22 : 10, height: 6)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.stepIndex)
    }

    // MARK: Result

    private func summary(_ result: Calibration.Result) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All set")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Recognition is now fitted to your strokes. Your drawings are also kept as examples, so shapes are recognized the way you draw them.")
                        .captionStyle()
                }
            }
            HStack(spacing: 10) {
                ForEach(result.samples.indices, id: \.self) { i in
                    ShapeTile(points: result.samples[i].points, size: 40, tint: .green)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.green.opacity(0.08)))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if model.stepIndex > 0 {
                Button("Start Over") { model.restart() }
                    .glassButtonStyle()
            }
            Spacer()
            Button("Cancel") { isPresented = false }
                .keyboardShortcut(.cancelAction)
                .glassButtonStyle()
            Button("Save") {
                if let result = model.result { store.config.apply(result) }
                isPresented = false
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.isFinished)
            .glassButtonStyle(prominent: true)
        }
        .controlSize(.large)
    }
}

/// Calibration status with a button that opens the sheet; used in Recognition and onboarding.
struct CalibrationStatus: View {
    @ObservedObject var store: ConfigStore
    var compact = false
    @StateObject private var sheet = SheetState()

    var body: some View {
        HStack(spacing: 12) {
            if !compact {
                Image(systemName: store.config.isCalibrated ? "checkmark.seal.fill" : "dial.medium")
                    .font(.system(size: 22))
                    .foregroundStyle(store.config.isCalibrated ? Color.green : Color.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.config.isCalibrated ? L("Fitted to your strokes") : L("Using the standard settings"))
                    Text(store.config.isCalibrated
                         ? L("Calibrate again if gestures are missed or happen by accident.")
                         : L("Takes about 30 seconds: draw four shapes twice."))
                        .captionStyle()
                }
                Spacer()
            }
            Button(store.config.isCalibrated ? L("Calibrate Again…") : L("Calibrate…")) { sheet.isPresented = true }
                .glassButtonStyle(prominent: !store.config.isCalibrated)
        }
        .sheet(isPresented: $sheet.isPresented) {
            CalibrationView(store: store, isPresented: $sheet.isPresented)
        }
    }
}

@MainActor
final class SheetState: ObservableObject {
    @Published var isPresented = false
}
