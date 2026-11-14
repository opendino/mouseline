import AppKit
import MouseLineCore
import SwiftUI

@MainActor
final class CalibrationPaneModel: ObservableObject {
    @Published var showAdvanced = false
}

/// The Calibration pane: fit recognition to the user's hand, with the manual values
/// tucked away under Advanced.
struct CalibrationSettingsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var state: AppState
    @StateObject private var model = CalibrationPaneModel()

    var body: some View {
        Form {
            Section {
                PaneHeader(
                    title: L("Calibration"),
                    subtitle: L("Draw a few shapes with your trigger button and MouseLine learns how you draw them: how precisely, and how long your strokes are.")
                ) {
                    IconTile(symbol: "dial.medium.fill", color: .indigo, size: 40)
                }
            }

            Section {
                CalibrationStatus(store: store, state: state)
                    .padding(.vertical, 4)
            }

            Section {
                DisclosureGroup(isExpanded: $model.showAdvanced) {
                    LabeledSlider(title: "Minimum gesture length", value: $store.config.clickMaxPath, range: 20...250, format: "%.0f pt")
                    LabeledSlider(title: "Recognition tolerance", value: $store.config.matchMaxDistance, range: 10...60, format: "%.0f")
                    LabeledContent("Personal examples") {
                        Text(store.config.isCalibrated ? LF("%d strokes", store.config.personalSamples.count) : L("None"))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Shorter strokes act as a normal click. A lower tolerance means fewer accidental matches, but shapes must be drawn more precisely.")
                            .captionStyle()
                        Spacer(minLength: 12)
                        Button("Reset Recognition", action: resetRecognition)
                            .glassButtonStyle()
                    }
                } label: {
                    Text("Advanced")
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Asks first: the personal examples cannot be brought back except by calibrating again.
    /// Nothing to ask when the values are already the defaults.
    private func resetRecognition() {
        var reset = store.config
        reset.resetRecognition()
        guard reset != store.config else { return }
        let confirmed = Alerts.confirm(
            L("Reset recognition?"),
            info: L("Your personal examples are removed and the minimum gesture length and recognition tolerance go back to their defaults. You can calibrate again at any time."),
            confirmTitle: L("Reset")
        )
        guard confirmed else { return }
        store.config.resetRecognition()
    }
}
