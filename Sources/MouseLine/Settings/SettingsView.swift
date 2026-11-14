import AppKit
import MouseLineCore
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
    case calibration
    case excludedApps
    /// Gestures for one app (bundle id).
    case app(String)
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var selection: SettingsPane? = .gestures
}

/// Everything the sidebar and the detail pane share: the selected pane and app scopes.
@MainActor
struct SettingsActions {
    let store: ConfigStore
    let model: SettingsModel

    var pane: SettingsPane {
        if case .app(let id) = model.selection, store.config.appBindings[id] == nil { return .gestures }
        return model.selection ?? .gestures
    }

    func title(for pane: SettingsPane) -> String {
        switch pane {
        case .general: return L("General")
        case .gestures: return L("Gestures")
        case .appearance: return L("Appearance")
        case .recognition: return L("Recognition")
        case .calibration: return L("Calibration")
        case .excludedApps: return L("Excluded Apps")
        case .app(let id): return store.config.appBindings[id].map { $0.name.isEmpty ? id : $0.name } ?? id
        }
    }

    func addApp(_ app: ExcludedApp) {
        if store.config.appBindings[app.bundleID] == nil {
            store.config.appBindings[app.bundleID] = AppBindings(name: app.name)
        }
        model.selection = .app(app.bundleID)
    }

    func removeApp(_ bundleID: String) {
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

/// The settings window's sidebar: panes, app-specific gestures and the status card.
struct SettingsSidebar: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var state: AppState
    @ObservedObject var model: SettingsModel
    @ObservedObject private var running = RunningApps.shared

    private var actions: SettingsActions { SettingsActions(store: store, model: model) }

    var body: some View {
        List(selection: $model.selection) {
            Section {
                row(.general, "General", symbol: "gearshape.fill", color: .gray)
                row(.gestures, "Gestures", symbol: "hand.draw.fill", color: .blue)
                row(.appearance, "Appearance", symbol: "paintbrush.pointed.fill", color: .pink)
                row(.recognition, "Recognition", symbol: "scribble.variable", color: .orange)
                row(.calibration, "Calibration", symbol: "dial.medium.fill", color: .indigo)
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
                        Button("Remove App…") { actions.removeApp(app.bundleID) }
                    }
                }
                addAppMenu
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarStatus(store: store, state: state)
                .padding(10)
        }
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
                ForEach(running.list(excluding: Set(store.config.appBindings.keys)), id: \.bundleID) { app in
                    Button(app.name) { actions.addApp(app) }
                }
                Divider()
                Button("Choose…") {
                    if let app = AppInfo.chooseApps(multiple: false).first { actions.addApp(app) }
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .foregroundStyle(.secondary)
    }
}

/// The settings window's detail: the selected pane.
struct SettingsDetail: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var state: AppState
    @ObservedObject var model: SettingsModel
    var onTitleChange: (String) -> Void = { _ in }

    private var actions: SettingsActions { SettingsActions(store: store, model: model) }

    var body: some View {
        content
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { onTitleChange(actions.title(for: actions.pane)) }
            .onChange(of: model.selection) { _ in onTitleChange(actions.title(for: actions.pane)) }
    }

    @ViewBuilder
    private var content: some View {
        switch actions.pane {
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
        case .calibration:
            CalibrationSettingsView(store: store, state: state)
        case .app(let id):
            GesturesView(store: store, scope: id, onRemove: { actions.removeApp(id) })
                .id(id)
        }
    }
}

/// Builds the settings window from an AppKit split view, so the sidebar gets the system's
/// own treatment — a floating Liquid Glass sidebar on macOS 26, the translucent one before.
@MainActor
enum SettingsWindow {
    static func make(store: ConfigStore, state: AppState, model: SettingsModel, onTitleChange: @escaping (String) -> Void) -> NSWindow {
        let sidebar = NSHostingController(rootView: SettingsSidebar(store: store, state: state, model: model))
        let detail = NSHostingController(rootView: SettingsDetail(store: store, state: state, model: model, onTitleChange: onTitleChange))
        sidebar.sizingOptions = []
        detail.sizingOptions = []

        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 215
        sidebarItem.maximumThickness = 280
        sidebarItem.canCollapse = false
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 520
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(detailItem)

        let window = NSWindow(contentViewController: split)
        window.title = L("MouseLine Settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbar = NSToolbar(identifier: "settings")
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 880, height: 640))
        window.contentMinSize = NSSize(width: 760, height: 540)
        return window
    }
}

/// On/off switch and status at the bottom of the sidebar, on a glass card.
struct SidebarStatus: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var state: AppState

    private var color: Color {
        !state.monitorRunning ? .orange : store.config.enabled ? .green : .secondary
    }

    private var text: String {
        if !state.monitorRunning { return L("Waiting for Accessibility access") }
        if !store.config.enabled { return L("Gestures are off") }
        return LF("Active · %@", L(store.config.triggerButton.title))
    }

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(color.gradient)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.6), radius: 3)
            Text(verbatim: text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Toggle("Gestures enabled", isOn: $store.config.enabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(!state.monitorRunning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassSurface(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: store.config.enabled)
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

    /// Regular (Dock) apps that are running now, except MouseLine and the given bundle ids.
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
        let panel = appPanel(multiple: multiple)
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap(excludedApp(at:))
    }

    /// Lets the user pick one app and returns exactly the bundle picked. Looking the app up
    /// again by bundle id could return another copy (Xcode and Xcode-beta share one), and
    /// would fail for bundles that have no bundle id at all.
    static func chooseAppURL() -> URL? {
        let panel = appPanel(multiple: false)
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func appPanel(multiple: Bool) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = multiple
        return panel
    }

    static func icon(bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}

/// The regular apps running now, kept current as apps launch and quit. Menu content is
/// built together with the view, not when the menu opens, so asking NSWorkspace inside
/// the menu would list the apps of the last re-render: missing new ones, keeping quit ones.
@MainActor
final class RunningApps: ObservableObject {
    static let shared = RunningApps()

    @Published private(set) var apps: [ExcludedApp] = []

    private init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    /// The running apps, except the given bundle ids.
    func list(excluding: Set<String>) -> [ExcludedApp] {
        apps.filter { !excluding.contains($0.bundleID) }
    }

    private func refresh() {
        let current = AppInfo.runningApps(excluding: [])
        if current != apps { apps = current }
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
