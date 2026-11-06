import AppKit
import MGesturesCore
import SwiftUI

// Note: view-local state uses small ObservableObject models with @StateObject instead of
// @State. In recent SDKs @State is a macro whose plugin ships only with Xcode, and this
// project must build with the Command Line Tools alone.

/// The panes of the settings window.
enum SettingsPane: Hashable {
    case general
    case gestures
    case appearance
    case recognition
    case excludedApps
    /// Gestures for one app (bundle id).
    case app(String)
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var selection: SettingsPane? = .gestures
}

/// The settings window: a System Settings–style sidebar and a detail pane.
struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var state: AppState
    @ObservedObject var model: SettingsModel
    var onTitleChange: (String) -> Void = { _ in }

    private var pane: SettingsPane {
        if case .app(let id) = model.selection, store.config.appBindings[id] == nil { return .gestures }
        return model.selection ?? .gestures
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 260)
        } detail: {
            detail
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 540)
        .onAppear { onTitleChange(title(for: pane)) }
        .onChange(of: model.selection) { _ in onTitleChange(title(for: pane)) }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $model.selection) {
            Section {
                row(.general, "General", symbol: "gearshape.fill", color: .gray)
                row(.gestures, "Gestures", symbol: "hand.draw.fill", color: .blue)
                row(.appearance, "Appearance", symbol: "paintbrush.pointed.fill", color: .pink)
                row(.recognition, "Recognition", symbol: "scribble.variable", color: .orange)
                row(.excludedApps, "Excluded Apps", symbol: "nosign", color: .red)
            }
            Section("App-Specific Gestures") {
                ForEach(AppScopePicker.apps(in: store.config), id: \.bundleID) { app in
                    Label {
                        Text(verbatim: app.name)
                    } icon: {
                        AppIconView(bundleID: app.bundleID, size: 20)
                    }
                    .tag(SettingsPane.app(app.bundleID))
                    .contextMenu {
                        Button("Remove App…") { removeApp(app.bundleID) }
                    }
                }
                addAppMenu
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ pane: SettingsPane, _ title: LocalizedStringKey, symbol: String, color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            IconTile(symbol: symbol, color: color, size: 20)
        }
        .tag(pane)
    }

    /// The plus sits outside the menu: borderless menus show only their title.
    private var addAppMenu: some View {
        HStack(spacing: 7) {
            Image(systemName: "plus.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 16))
                .frame(width: 20)
            Menu("Add App…") {
                ForEach(AppInfo.runningApps(excluding: Set(store.config.appBindings.keys)), id: \.bundleID) { app in
                    Button(app.name) { addApp(app) }
                }
                Divider()
                Button("Choose…") {
                    if let app = AppInfo.chooseApps(multiple: false).first { addApp(app) }
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .foregroundStyle(.secondary)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .general:
            GeneralSettingsView(store: store, state: state)
        case .gestures:
            GesturesView(store: store, scope: nil)
        case .appearance:
            AppearanceSettingsView(store: store)
        case .recognition:
            TryView(store: store)
        case .excludedApps:
            ExcludedAppsView(store: store)
        case .app(let id):
            GesturesView(store: store, scope: id, onRemove: { removeApp(id) })
                .id(id)
        }
    }

    private func title(for pane: SettingsPane) -> String {
        switch pane {
        case .general: return L("General")
        case .gestures: return L("Gestures")
        case .appearance: return L("Appearance")
        case .recognition: return L("Recognition")
        case .excludedApps: return L("Excluded Apps")
        case .app(let id): return store.config.appBindings[id].map { $0.name.isEmpty ? id : $0.name } ?? id
        }
    }

    // MARK: App scopes

    private func addApp(_ app: ExcludedApp) {
        if store.config.appBindings[app.bundleID] == nil {
            store.config.appBindings[app.bundleID] = AppBindings(name: app.name)
        }
        model.selection = .app(app.bundleID)
    }

    private func removeApp(_ bundleID: String) {
        let name = title(for: .app(bundleID))
        let confirmed = Alerts.confirm(
            LF("Remove the gestures for %@?", name),
            info: L("All shapes will use the All Apps settings in this app again."),
            confirmTitle: L("Remove")
        )
        guard confirmed else { return }
        if model.selection == .app(bundleID) { model.selection = .gestures }
        store.config.appBindings.removeValue(forKey: bundleID)
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
        LabeledContent {
            HStack(spacing: 10) {
                // No `step:` — on macOS it draws a tick mark per step. Snap in the binding instead.
                Slider(value: Binding(
                    get: { value },
                    set: { value = min(range.upperBound, max(range.lowerBound, ($0 / step).rounded() * step)) }
                ), in: range)
                .frame(minWidth: 160, maxWidth: 240)
                Text(String(format: format, value))
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(title)
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
