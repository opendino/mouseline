import AppKit
import MGesturesCore
import SwiftUI

@MainActor
final class CalibrationModel: ObservableObject {
    @Published private(set) var accepted: [(id: String, stroke: [StrokePoint])] = []
    @Published private(set) var message: String?
    @Published private(set) var lastStroke: [StrokePoint] = []
    @Published private(set) var lastAccepted = false
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

    /// Strokes come from the trigger button (see `CalibrationCapture`), in screen points.
    func submit(_ stroke: [StrokePoint], templates: [GestureTemplate], config: AppConfig) {
        guard let expected = currentID else { return }
        lastStroke = stroke
        switch Calibration.check(stroke, expected: expected, templates: templates) {
        case .accepted:
            message = nil
            lastAccepted = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                accepted.append((expected, stroke))
            }
            if accepted.count == steps.count {
                withAnimation(.easeInOut(duration: 0.3)) {
                    result = Calibration.compute(samples: accepted, templates: templates)
                }
            }
        case .tooShort:
            lastAccepted = false
            message = L("Draw a longer stroke.")
        case .looksLike(let other):
            lastAccepted = false
            message = LF("That looked like “%@”. Try again.", config.localizedName(for: other))
        }
    }

    func restart() {
        accepted = []
        result = nil
        message = nil
        lastStroke = []
    }
}

/// Sheet that fits recognition to the user's hand. The shapes are drawn with the real
/// trigger button anywhere on screen, so length and shape match everyday use; while it is
/// open, strokes are measured and nothing runs.
struct CalibrationView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var state: AppState
    @Binding var isPresented: Bool
    @StateObject private var model = CalibrationModel()

    private var buttonName: String { L(store.config.triggerButton.title).lowercased(with: Locale.current) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let result = model.result {
                summary(result)
            } else if !state.monitorRunning {
                Label("Accessibility access is required to capture mouse gestures.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                drawingStep
            }
            footer
        }
        .padding(24)
        .frame(width: 500)
        .onAppear {
            CalibrationCapture.shared.begin { [weak model, store] stroke in
                model?.submit(stroke, templates: store.config.shapeTemplates, config: store.config)
            }
        }
        .onDisappear { CalibrationCapture.shared.end() }
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
            HStack(spacing: 16) {
                ShapeTile(points: template.points, size: 72)
                    .id(model.stepIndex)
                    .transition(.scale.combined(with: .opacity))
                VStack(alignment: .leading, spacing: 4) {
                    Text(LF("Draw “%@”", L(id)))
                        .font(.system(size: 20, weight: .semibold))
                    Text(LF("%d of %d", model.repetition, Calibration.samplesPerGesture))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.lastStroke.isEmpty {
                    ShapeTile(points: model.lastStroke, size: 44, tint: model.lastAccepted ? .green : .orange)
                        .help("Your last stroke")
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.05)))
        }

        Group {
            if let message = model.message {
                Label(message, systemImage: "arrow.uturn.backward.circle")
                    .foregroundStyle(.orange)
            } else {
                Label(LF("Hold the %@ and draw the shape anywhere on the screen, as you normally would. Nothing runs while calibrating.", buttonName), systemImage: "cursorarrow.motionlines")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// One dash per stroke; filled when accepted.
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

/// Calibration status with a button that opens the sheet; used in the Calibration pane
/// and in the welcome guide.
struct CalibrationStatus: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var state: AppState
    var compact = false
    @StateObject private var sheet = SheetState()

    var body: some View {
        HStack(spacing: 12) {
            if !compact {
                Image(systemName: store.config.isCalibrated ? "checkmark.seal.fill" : "dial.medium")
                    .font(.system(size: 24))
                    .foregroundStyle(store.config.isCalibrated ? Color.green : Color.secondary)
                    .frame(width: 30)
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
                .disabled(!state.monitorRunning)
        }
        .sheet(isPresented: $sheet.isPresented) {
            CalibrationView(store: store, state: state, isPresented: $sheet.isPresented)
        }
    }
}

@MainActor
final class SheetState: ObservableObject {
    @Published var isPresented = false
}
