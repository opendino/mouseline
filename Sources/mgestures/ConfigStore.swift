import Foundation
import MGesturesCore
import os

private let log = Logger(subsystem: "dev.mgestures.app", category: "config")

/// Loads and saves `AppConfig` as JSON in ~/Library/Application Support/mgestures/config.json.
@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: AppConfig {
        didSet { if config != oldValue { save() } }
    }

    let fileURL: URL

    init(fileURL: URL = ConfigStore.defaultURL) {
        self.fileURL = fileURL
        self.config = ConfigStore.load(from: fileURL)
        if !FileManager.default.fileExists(atPath: fileURL.path) { save() }
    }

    nonisolated static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("mgestures", isDirectory: true).appendingPathComponent("config.json")
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
        } catch {
            log.error("Could not save config: \(error.localizedDescription, privacy: .public)")
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
