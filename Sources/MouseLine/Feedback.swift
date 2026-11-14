import AppKit
import MouseLineCore

/// Sound and haptic feedback when a gesture is recognized.
@MainActor
enum Feedback {
    private static let soundsDirectory = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)

    /// The system alert sounds (file names without extension), sorted. Read once: the folder
    /// is part of the sealed system volume and does not change while we run.
    static var availableSounds: [String] { cachedSounds }

    private static let cachedSounds: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(at: soundsDirectory, includingPropertiesForKeys: nil)) ?? []
        let names = files
            .filter { ["aiff", "aif", "caf", "wav", "m4a", "mp3"].contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent }
        return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }()

    /// Plays a sound by name, e.g. when it is picked in Settings.
    static func preview(sound: String) {
        play(sound)
    }

    /// Feedback for a gesture that is about to run its action.
    static func gestureRecognized(config: AppConfig) {
        if !config.feedbackSound.isEmpty { play(config.feedbackSound) }
        if config.hapticFeedback {
            // Only Force Touch trackpads respond; on a mouse this does nothing.
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }

    private static func play(_ name: String) {
        // NSSound(named:) returns a shared instance, which ignores play() while it is still
        // playing; restart it so quick successive gestures each get their sound.
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.stop()
        sound.play()
    }
}
