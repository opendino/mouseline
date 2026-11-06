import AppKit
import Combine
import MGesturesCore
import SwiftUI

/// Shared state the settings and onboarding UI observe.
@MainActor
final class AppState: ObservableObject {
    @Published var monitorRunning = false
    @Published var lastGesture: String?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = ConfigStore()
    let state = AppState()
    private let overlay = TrailOverlay()
    private let hud = HUD()
    private let hotKeys = HotKeyCenter()
    private var monitor: GestureMonitor!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard SingleInstance.claim() else {
            NSApp.terminate(nil)
            return
        }

        monitor = GestureMonitor(
            store: store, overlay: overlay,
            onGesture: { [weak self] id, distance, bundleID in
                self?.handleGesture(id, distance: distance, bundleID: bundleID)
            },
            onCancel: { [weak self] in
                guard let self, self.store.config.showGestureName else { return }
                self.hud.show(L("Cancelled"))
            }
        )
        monitor.onStatusChange = { [weak self] in
            guard let self else { return }
            self.state.monitorRunning = self.monitor.isRunning
            self.updateStatusIcon()
        }

        setUpStatusItem()
        store.$config
            .map(\.enabled)
            .removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatusIcon() } }
            .store(in: &cancellables)
        // The global on/off shortcut; re-registered whenever it changes in Settings.
        store.$config
            .map(\.toggleShortcut)
            .removeDuplicates()
            .sink { [weak self] combo in
                MainActor.assumeIsolated { self?.registerToggleShortcut(combo) }
            }
            .store(in: &cancellables)

        let needsOnboarding = !store.config.onboardingCompleted || !Permissions.isAccessibilityTrusted
            || (AppMover.isAppBundle && !AppMover.isInApplicationsFolder && !store.config.onboardingCompleted)
        if needsOnboarding { openOnboarding() }
        monitor.start()
    }

    /// `bundleID` is the app that was under the cursor when the press started (nil when no
    /// exclusions or per-app bindings exist), so its overrides apply.
    private func handleGesture(_ id: String, distance: Double, bundleID: String?) {
        let config = store.config
        let name = config.localizedName(for: id)
        state.lastGesture = name
        Feedback.gestureRecognized(config: config)
        if config.showGestureName { hud.show(name) }
        ActionRunner.run(config.action(for: id, in: bundleID))
    }

    private func registerToggleShortcut(_ combo: KeyCombo?) {
        hotKeys.register(combo) { [weak self] in
            guard let self else { return }
            self.store.config.enabled.toggle()
            self.hud.show(self.store.config.enabled ? L("Gestures on") : L("Gestures off"))
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let active = store.config.enabled && (monitor?.isRunning ?? false)
        button.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "mgestures")
        button.appearsDisabled = !active
        button.toolTip = active ? "mgestures" : L("mgestures (inactive)")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !(monitor?.isRunning ?? false) {
            menu.addItem(item(L("Grant Accessibility Access…"), #selector(grantAccess)))
            menu.addItem(.separator())
        }

        let toggle = item(L("Gestures Enabled"), #selector(toggleEnabled))
        toggle.state = store.config.enabled ? .on : .off
        menu.addItem(toggle)

        // Status item menus don't activate us, so the frontmost app is still the user's app.
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier,
           let app = AppInfo.excludedApp(for: front) {
            let excluded = store.config.isExcluded(bundleID: app.bundleID)
            let perApp = item(LF("Disable in %@", app.name), #selector(toggleAppExclusion(_:)))
            perApp.state = excluded ? .on : .off
            perApp.representedObject = [app.bundleID, app.name]
            menu.addItem(perApp)
        }
        menu.addItem(.separator())

        menu.addItem(item(L("Settings…"), #selector(openSettings), key: ","))
        menu.addItem(item(L("Welcome Guide…"), #selector(openOnboarding)))
        menu.addItem(item(L("About mgestures"), #selector(showAbout)))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: L("Quit mgestures"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleEnabled() {
        store.config.enabled.toggle()
    }

    @objc private func toggleAppExclusion(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String], info.count == 2 else { return }
        if store.config.isExcluded(bundleID: info[0]) {
            store.config.excludedApps.removeAll { $0.bundleID == info[0] }
        } else {
            store.config.excludedApps.append(ExcludedApp(bundleID: info[0], name: info[1]))
        }
    }

    /// The standard About panel. As a menu bar app we are not active, so activate first or
    /// the panel opens behind the frontmost app.
    @objc private func showAbout() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? ""
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "mgestures",
            .applicationVersion: version,
            .version: build,
            .credits: aboutCredits(),
        ]
        // Running from `swift build` there is no bundle icon; fall back to the app's image.
        if let icon = NSApp.applicationIconImage { options[.applicationIcon] = icon }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    private func aboutCredits() -> NSAttributedString {
        let text = [
            L("Draw shapes with the mouse to control windows, apps and more."),
            L("Licensed under the Apache License 2.0."),
            L("The shape recognizer is an adaptation of the “$1 Unistroke Recognizer” by J. O. Wobbrock, A. D. Wilson and Y. Li (UIST 2007)."),
        ].joined(separator: "\n\n")
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ])
    }

    @objc private func grantAccess() {
        Permissions.requestAccessibility()
        Permissions.openAccessibilitySettings()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let root = SettingsView(store: store, state: state)
            settingsWindow = makeWindow(title: L("mgestures Settings"), root: root)
        }
        show(settingsWindow)
    }

    @objc func openOnboarding() {
        if onboardingWindow == nil {
            let root = OnboardingView(
                store: store, state: state,
                openSettings: { [weak self] in self?.openSettings() },
                close: { [weak self] in self?.onboardingWindow?.close() }
            )
            onboardingWindow = makeWindow(title: L("Welcome to mgestures"), root: root)
        }
        show(onboardingWindow)
    }

    private func makeWindow<V: View>(title: String, root: V) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func show(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum Permissions {
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds this app to the Accessibility list.
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
