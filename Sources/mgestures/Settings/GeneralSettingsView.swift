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
                if state.monitorRunning {
                    Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Accessibility access is required to capture mouse gestures.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Open Accessibility Settings…") {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                    }
                }
                Toggle("Gestures enabled", isOn: $store.config.enabled)
                Toggle("Launch at login", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.set($0) }))
                if let error = loginItem.error {
                    Text(verbatim: error).font(.caption).foregroundStyle(.red)
                }
            }

            triggerSection
            contextMenuSection
            feedbackSection
            recognitionSection
            dataSection
        }
        .formStyle(.grouped)
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
                .font(.caption)
                .foregroundStyle(.secondary)
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
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var feedbackSection: some View {
        Section("Appearance and feedback") {
            Toggle("Show trail while drawing", isOn: $store.config.showTrail)
            ColorPicker("Trail color", selection: trailColor, supportsOpacity: true)
                .disabled(!store.config.showTrail)
            LabeledSlider(title: "Trail width", value: $store.config.trailWidth, range: 2...14, format: "%.0f pt")
                .disabled(!store.config.showTrail)
            Toggle("Show gesture name after drawing", isOn: $store.config.showGestureName)
            Picker("Sound", selection: sound) {
                Text("None").tag("")
                ForEach(Feedback.availableSounds, id: \.self) { name in
                    Text(verbatim: name).tag(name)
                }
            }
            Toggle(isOn: $store.config.hapticFeedback) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Haptic feedback")
                    Text("Force Touch trackpads only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recognitionSection: some View {
        Section {
            LabeledSlider(title: "Minimum gesture length", value: $store.config.clickMaxPath, range: 20...250, format: "%.0f pt")
            LabeledSlider(title: "Recognition tolerance", value: $store.config.matchMaxDistance, range: 10...60, format: "%.0f")
            Button("Reset to Defaults") {
                let d = AppConfig()
                store.config.clickMaxPath = d.clickMaxPath
                store.config.matchMaxDistance = d.matchMaxDistance
            }
        } header: {
            Text("Recognition")
        } footer: {
            Text("Shorter strokes act as a normal click. A lower tolerance means fewer accidental matches, but shapes must be drawn more precisely. Strokes that match no shape, or a shape without an action, also act as a normal click. Use the Try tab to test.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dataSection: some View {
        Section("Settings") {
            HStack {
                Button("Export…", action: exportSettings)
                Button("Import…", action: importSettings)
                Spacer()
                Button("Reset All Settings…", role: .destructive, action: resetSettings)
            }
            HStack {
                Text(verbatim: store.fileURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                }
            }
        }
    }

    // MARK: Bindings

    private var holdDelayMilliseconds: Binding<Double> {
        Binding(
            get: { store.config.holdDelay * 1000 },
            set: { store.config.holdDelay = $0 / 1000 }
        )
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
