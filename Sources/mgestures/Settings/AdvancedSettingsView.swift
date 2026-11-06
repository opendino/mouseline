import AppKit
import MGesturesCore
import SwiftUI
import UniformTypeIdentifiers

/// The Advanced pane: manual recognition settings and the settings file. Calibration
/// (in Recognition) normally sets the recognition values; these are for troubleshooting.
struct AdvancedSettingsView: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section {
                PaneHeader(
                    title: L("Advanced"),
                    subtitle: L("Manual settings for troubleshooting. Calibration in Recognition sets these for you.")
                ) {
                    IconTile(symbol: "slider.horizontal.3", color: .gray, size: 40)
                }
            }

            Section {
                LabeledSlider(title: "Minimum gesture length", value: $store.config.clickMaxPath, range: 20...250, format: "%.0f pt")
                LabeledSlider(title: "Recognition tolerance", value: $store.config.matchMaxDistance, range: 10...60, format: "%.0f")
                LabeledContent("Personal examples") {
                    Text(store.config.isCalibrated ? LF("%d strokes", store.config.personalSamples.count) : L("None"))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Reset Recognition") { store.config.resetRecognition() }
                        .glassButtonStyle()
                }
            } header: {
                Text("Recognition")
            } footer: {
                Text("Shorter strokes act as a normal click. A lower tolerance means fewer accidental matches, but shapes must be drawn more precisely. Strokes that match no shape, or a shape without an action, also act as a normal click.")
                    .footerStyle()
            }

            Section {
                LabeledContent("Settings file") {
                    HStack(spacing: 6) {
                        Text(verbatim: (store.fileURL.path as NSString).abbreviatingWithTildeInPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                        } label: {
                            Image(systemName: "arrow.right.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Show in Finder")
                    }
                }
                HStack {
                    Button("Export…", action: exportSettings)
                        .glassButtonStyle()
                    Button("Import…", action: importSettings)
                        .glassButtonStyle()
                    Spacer()
                    Button("Reset All Settings…", role: .destructive, action: resetSettings)
                        .glassButtonStyle()
                }
            } header: {
                Text("Settings")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Export / import / reset

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "mgestures-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.config.encoded().write(to: url, options: .atomic)
        } catch {
            Alerts.error(L("Could not export the settings."), info: error.localizedDescription)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var imported = try AppConfig.decode(Data(contentsOf: url))
            imported.onboardingCompleted = true
            store.config = imported
        } catch {
            Alerts.error(L("Could not import the settings."), info: error.localizedDescription)
        }
    }

    private func resetSettings() {
        let confirmed = Alerts.confirm(
            L("Reset all settings?"),
            info: L("All gestures, custom shapes, app settings and exclusions are replaced with the defaults. Export first if you want to keep them."),
            confirmTitle: L("Reset")
        )
        guard confirmed else { return }
        var fresh = AppConfig()
        fresh.onboardingCompleted = true
        store.config = fresh
    }
}
