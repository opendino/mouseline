import AppKit
import MouseLineCore
import os

private let log = Logger(subsystem: "app.mouseline", category: "config")

/// Loads and saves `AppConfig` as JSON in ~/Library/Application Support/MouseLine/config.json.
@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: AppConfig {
        didSet { if config != oldValue { save() } }
    }

    /// Why the last save failed, or nil once a save works again. Every change retries the
    /// save (didSet), so this clears itself when the folder becomes writable.
    @Published private(set) var saveError: String?

    let fileURL: URL
    /// The save-failure alert is shown once per run; later failures are only logged.
    private var didAlertSaveFailure = false

    init(fileURL: URL = ConfigStore.defaultURL) {
        self.fileURL = fileURL
        if fileURL == ConfigStore.defaultURL { ConfigStore.migrateLegacySettings(to: fileURL) }
        self.config = ConfigStore.load(from: fileURL)
        if !FileManager.default.fileExists(atPath: fileURL.path) { save() }
    }

    nonisolated static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MouseLine", isDirectory: true).appendingPathComponent("config.json")
    }

    /// The app was called "mgestures" before it became MouseLine. Its settings lived in
    /// ~/Library/Application Support/mgestures; copy them over once, so gestures, app
    /// settings and calibration survive the rename. The old folder is left in place.
    private static func migrateLegacySettings(to url: URL) {
        let fm = FileManager.default
        let legacy = url.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("mgestures", isDirectory: true).appendingPathComponent("config.json")
        guard !fm.fileExists(atPath: url.path), fm.fileExists(atPath: legacy.path) else { return }
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: legacy, to: url)
            log.info("Copied settings from \(legacy.path, privacy: .public)")
        } catch {
            log.error("Could not copy the old settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> AppConfig {
        guard let data = try? Data(contentsOf: url) else { return AppConfig() }
        do {
            return try AppConfig.decode(data)
        } catch {
            // Keep the unreadable file for the user instead of silently overwriting it.
            let backup = url.deletingPathExtension().appendingPathExtension("broken.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            log.error("Config unreadable, moved to \(backup.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return AppConfig()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try config.encoded().write(to: fileURL, options: .atomic)
            // @Published fires on every assignment; skip the no-op one on each normal save.
            if saveError != nil { saveError = nil }
        } catch {
            log.error("Could not save config: \(error.localizedDescription, privacy: .public)")
            saveError = error.localizedDescription
            alertSaveFailure(error)
        }
    }

    /// The UI already shows the change as applied, so without this the user would only
    /// find out after a restart that it was lost. Deferred: save() runs inside didSet,
    /// often in the middle of a SwiftUI update, where a modal alert must not start.
    private func alertSaveFailure(_ error: Error) {
        guard !didAlertSaveFailure else { return }
        didAlertSaveFailure = true
        let folder = (fileURL.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Settings cannot be saved")
            alert.informativeText = LF("MouseLine cannot write to %@. Changes you make are lost when the app quits.", folder)
                + "\n\n" + error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    func binding(for gestureID: String) -> ActionConfig {
        config.action(for: gestureID)
    }

    func setBinding(_ action: ActionConfig, for gestureID: String) {
        if action == ActionConfig() {
            config.bindings.removeValue(forKey: gestureID)
        } else {
            config.bindings[gestureID] = action
        }
    }
}
