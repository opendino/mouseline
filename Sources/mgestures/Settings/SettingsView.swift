import AppKit
import MGesturesCore
import SwiftUI

// Note: view-local state uses small ObservableObject models with @StateObject instead of
// @State. In recent SDKs @State is a macro whose plugin ships only with Xcode, and this
// project must build with the Command Line Tools alone.

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var state: AppState

    var body: some View {
        TabView {
            GesturesView(store: store)
                .tabItem { Label("Gestures", systemImage: "hand.draw") }
            TryView(store: store)
                .tabItem { Label("Try", systemImage: "scribble") }
            ExcludedAppsView(store: store)
                .tabItem { Label("Excluded Apps", systemImage: "nosign") }
            GeneralSettingsView(store: store, state: state)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding()
        .frame(width: 780, height: 680)
    }
}

/// A slider with a title on the left and the formatted value on the right.
struct LabeledSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let format: String

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range, step: step)
            Text(String(format: format, value))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}

/// Information about installed and running apps, for exclusions and per-app gestures.
@MainActor
enum AppInfo {
    static func excludedApp(at url: URL) -> ExcludedApp? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return ExcludedApp(bundleID: id, name: name)
    }

    static func excludedApp(for app: NSRunningApplication) -> ExcludedApp? {
        guard let id = app.bundleIdentifier else { return nil }
        return ExcludedApp(bundleID: id, name: app.localizedName ?? id)
    }

    /// Regular (Dock) apps that are running now, except mgestures and the given bundle ids.
    static func runningApps(excluding: Set<String>) -> [ExcludedApp] {
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != own }
            .compactMap(excludedApp(for:))
            .filter { !excluding.contains($0.bundleID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Lets the user pick one or more apps in /Applications.
    static func chooseApps(multiple: Bool) -> [ExcludedApp] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = multiple
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap(excludedApp(at:))
    }

    static func icon(bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}

/// Modal alerts used by the settings window.
@MainActor
enum Alerts {
    /// Asks for confirmation; returns true if the user confirmed.
    static func confirm(_ message: String, info: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.alertStyle = .warning
        let confirm = alert.addButton(withTitle: confirmTitle)
        confirm.hasDestructiveAction = true
        alert.addButton(withTitle: L("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func error(_ message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.alertStyle = .critical
        alert.runModal()
    }
}
