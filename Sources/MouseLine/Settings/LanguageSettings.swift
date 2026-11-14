import AppKit
import SwiftUI

/// The languages MouseLine is translated into (folder names of Support/*.lproj), each with
/// its own name in that language, as language pickers usually show them.
enum AppLanguage {
    static let all: [(code: String, name: String)] = [
        ("en", "English"),
        ("tr", "Türkçe"),
        ("es", "Español"),
        ("hi", "हिन्दी"),
        ("pt-BR", "Português (Brasil)"),
        ("de", "Deutsch"),
        ("ja", "日本語"),
        ("fr", "Français"),
        ("it", "Italiano"),
        ("ru", "Русский"),
        ("uk", "Українська"),
        ("pl", "Polski"),
        ("nl", "Nederlands"),
        ("id", "Bahasa Indonesia"),
        ("vi", "Tiếng Việt"),
        ("th", "ไทย"),
        ("ko", "한국어"),
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("ar", "العربية"),
    ]

    /// The language chosen in MouseLine ("" = follow macOS). Stored the standard way, as
    /// this app's AppleLanguages preference, which is also what System Settings → General →
    /// Language & Region → Applications writes; macOS applies it at the next launch.
    static var chosen: String {
        get {
            let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
            return (domain["AppleLanguages"] as? [String])?.first ?? ""
        }
        set {
            let defaults = UserDefaults.standard
            if newValue.isEmpty {
                defaults.removeObject(forKey: "AppleLanguages")
            } else {
                defaults.set([newValue], forKey: "AppleLanguages")
            }
            // A per-app language does not always switch AppKit to a right-to-left layout,
            // so ask for it explicitly for Arabic; with "Match System" macOS decides.
            if rightToLeft.contains(newValue) {
                defaults.set(true, forKey: "AppleTextDirection")
                defaults.set(true, forKey: "NSForceRightToLeftWritingDirection")
            } else {
                defaults.removeObject(forKey: "AppleTextDirection")
                defaults.removeObject(forKey: "NSForceRightToLeftWritingDirection")
            }
        }
    }

    /// Languages written right to left.
    static let rightToLeft: Set<String> = ["ar"]

    /// Starts a fresh copy of the app and quits this one, so a new language takes effect.
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [SingleInstance.relaunchArgument]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    Alerts.error(L("Could not restart MouseLine."), info: error.localizedDescription)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

@MainActor
final class LanguageModel: ObservableObject {
    /// The choice when the app started; a different choice needs a restart.
    private let atLaunch = AppLanguage.chosen
    @Published var selection = AppLanguage.chosen {
        didSet { AppLanguage.chosen = selection }
    }

    var needsRestart: Bool { selection != atLaunch }
}

/// Language picker for the General pane.
struct LanguageSection: View {
    @StateObject private var model = LanguageModel()

    var body: some View {
        Section {
            Picker("Language", selection: $model.selection) {
                Text("Match System").tag("")
                Divider()
                ForEach(AppLanguage.all, id: \.code) { language in
                    Text(verbatim: language.name).tag(language.code)
                }
            }
            if model.needsRestart {
                HStack {
                    Text("Restart MouseLine to use the new language.")
                        .captionStyle()
                    Spacer()
                    Button("Restart Now") { AppLanguage.relaunch() }
                        .glassButtonStyle(prominent: true)
                }
            }
        } header: {
            Text("Language")
        }
    }
}
