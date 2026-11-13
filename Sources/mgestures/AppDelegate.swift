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
    /// Lazy so the real config file is first read (and possibly created, or moved aside
    /// when broken) after the --snapshot and single-instance checks, never by those runs.
    private(set) lazy var store = ConfigStore()
    let state = AppState()
    private let overlay = TrailOverlay()
    private let hud = HUD.shared
    private let settingsModel = SettingsModel()
    private let hotKeys = HotKeyCenter()
    private var monitor: GestureMonitor!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let folder = Snapshot.requestedFolder {
            Snapshot.run(into: folder)
            NSApp.terminate(nil)
            return
        }
        guard SingleInstance.claim() else {
            NSApp.terminate(nil)
            return
        }
        installMainMenu()

        monitor = GestureMonitor(
            store: store, overlay: overlay,
            onGesture: { [weak self] id, distance, bundleID in
                self?.handleGesture(id, distance: distance, bundleID: bundleID)
            },
            onCancel: { [weak self] in
                guard let self, self.store.config.showGestureName else { return }
                self.hud.show(L("Cancelled"), symbol: "xmark")
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

    /// Opening the app again (Finder, Spotlight, Launchpad) while it runs shows Settings:
    /// a menu bar app has no other window to bring forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openSettings() }
        return true
    }

    /// `bundleID` is the app that was under the cursor when the press started (nil when no
    /// exclusions or per-app bindings exist), so its overrides apply.
    private func handleGesture(_ id: String, distance: Double, bundleID: String?) {
        let config = store.config
        let name = config.localizedName(for: id)
        state.lastGesture = name
        Feedback.gestureRecognized(config: config)
        let action = config.action(for: id, in: bundleID)
        if config.showGestureName { hud.show(name, detail: L(action.kind.title), symbol: action.kind.symbol) }
        ActionRunner.run(action)
    }

    private func registerToggleShortcut(_ combo: KeyCombo?) {
        hotKeys.register(combo) { [weak self] in
            guard let self else { return }
            self.store.config.enabled.toggle()
            let on = self.store.config.enabled
            self.hud.show(on ? L("Gestures on") : L("Gestures off"), symbol: on ? "hand.draw" : "hand.raised.slash")
        }
    }

    /// A main menu that is never shown (menu bar apps have no menu bar of their own) but
    /// still carries the key equivalents: without it ⌘C, ⌘V, ⌘A, ⌘Z and ⌘W do nothing in
    /// the Settings text fields. The Edit items have no target, so they go down the
    /// responder chain to whichever field is being edited.
    private func installMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: L("Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        appMenu.addItem(NSMenuItem(title: L("Quit mgestures"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let editMenu = NSMenu(title: L("Edit"))
        editMenu.addItem(NSMenuItem(title: L("Undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: L("Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
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

        let running = monitor?.isRunning ?? false
        menu.addItem(statusHeader(running: running))
        menu.addItem(.separator())

        if !running {
            menu.addItem(item(L("Grant Accessibility Access…"), #selector(grantAccess), symbol: "lock.open"))
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

        menu.addItem(item(L("Settings…"), #selector(openSettings), key: ",", symbol: "gearshape"))
        menu.addItem(item(L("Welcome Guide…"), #selector(openOnboarding), symbol: "sparkles"))
        menu.addItem(item(L("About mgestures"), #selector(showAbout), symbol: "info.circle"))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: L("Quit mgestures"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    /// "mgestures" with a colored status line, as the first (disabled) menu item.
    private func statusHeader(running: Bool) -> NSMenuItem {
        let (status, color): (String, NSColor) = !running
            ? (L("Waiting for Accessibility access"), .systemOrange)
            : store.config.enabled
                ? (LF("Active · %@", L(store.config.triggerButton.title)), .systemGreen)
                : (L("Gestures are off"), .secondaryLabelColor)
        let text = NSMutableAttributedString(string: "mgestures\n", attributes: [
            .font: NSFont.menuFont(ofSize: 0).withWeight(.semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        text.append(NSAttributedString(string: "● ", attributes: [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: color,
        ]))
        text.append(NSAttributedString(string: status, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        let header = NSMenuItem()
        header.attributedTitle = text
        header.isEnabled = false
        return header
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
            let window = SettingsWindow.make(store: store, state: state, model: settingsModel) { [weak self] title in
                self?.settingsWindow?.title = title
            }
            window.center()
            window.setFrameAutosaveName("mgestures.settings")
            settingsWindow = window
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
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = L("Welcome to mgestures")
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            // The SwiftUI content draws the (glass) panel; the window itself stays invisible.
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindow = window
        }
        show(onboardingWindow)
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

private extension NSFont {
    func withWeight(_ weight: NSFont.Weight) -> NSFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: weight]])
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
