import AppKit
import MGesturesCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LoginItemModel: ObservableObject {
    @Published private(set) var enabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var error: String?

    func set(_ enable: Bool) {
        do {
            if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = LF("Could not change the login item: %@", error.localizedDescription)
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}

@MainActor
final class GeneralModel: ObservableObject {
    @Published var shortcutError: String?
}

/// The General tab.
struct GeneralSettingsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var state: AppState
    @StateObject private var loginItem = LoginItemModel()
    @StateObject private var model = GeneralModel()

    var body: some View {
        Form {
            Section {
                PaneHeader(title: "mgestures", subtitle: statusText) {
                    OwnAppIcon(size: 44)
                } accessory: {
                    Toggle("Gestures enabled", isOn: $store.config.enabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!state.monitorRunning)
                }
                if !state.monitorRunning {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Accessibility access is required to capture mouse gestures.")
                            Button("Open Accessibility Settings…") {
                                Permissions.requestAccessibility()
                                Permissions.openAccessibilitySettings()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Toggle("Launch at login", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.set($0) }))
                if let error = loginItem.error {
                    Text(verbatim: error).font(.caption).foregroundStyle(.red)
                }
            }

            triggerSection
            contextMenuSection
            dataSection
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        if !state.monitorRunning { return L("Waiting for Accessibility access") }
        if !store.config.enabled { return L("Gestures are off") }
        return LF("Active · %@", L(store.config.triggerButton.title))
    }

    // MARK: Sections

    private var triggerSection: some View {
        Section {
            Picker("Trigger button", selection: $store.config.triggerButton) {
                ForEach(TriggerButton.allCases) { button in
                    Text(L(button.title)).tag(button)
                }
            }
            Picker("Required modifier key", selection: $store.config.requiredModifier) {
                ForEach(RequiredModifier.allCases) { modifier in
                    Text(L(modifier.title)).tag(modifier)
                }
            }
            HStack {
                Text("Turn gestures on/off")
                Spacer()
                ShortcutRecorder(combo: toggleShortcut)
            }
            if let error = model.shortcutError {
                Text(verbatim: error).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Trigger")
        } footer: {
            Text("With a required modifier key, gestures start only while it is held; otherwise the button works normally. The on/off shortcut works everywhere.")
                .footerStyle()
        }
    }

    private var contextMenuSection: some View {
        Section {
            Toggle("Hold still to open the context menu", isOn: $store.config.holdToOpenMenu)
            LabeledSlider(title: "Hold time", value: holdDelayMilliseconds, range: 200...1500, step: 50, format: "%.0f ms")
                .disabled(!store.config.holdToOpenMenu)
        } header: {
            Text("Context menu")
        } footer: {
            Text("A quick click always works normally. With this option, pressing and holding without moving does too, so you can press, drag to a menu item and release.")
                .footerStyle()
        }
    }

    private var dataSection: some View {
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

    // MARK: Bindings

    private var holdDelayMilliseconds: Binding<Double> {
        Binding(
            get: { store.config.holdDelay * 1000 },
            set: { store.config.holdDelay = $0 / 1000 }
        )
    }

    /// Accepts only shortcuts with ⌘, ⌃ or ⌥: plain keys would be taken away from every app.
    private var toggleShortcut: Binding<KeyCombo?> {
        Binding(
            get: { store.config.toggleShortcut },
            set: { combo in
                if let combo, !HotKeyCenter.isUsable(combo) {
                    model.shortcutError = L("Use at least one of ⌘, ⌃ or ⌥ in the shortcut.")
                    return
                }
                model.shortcutError = nil
                store.config.toggleShortcut = combo
            }
        )
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
