import AppKit
import MGesturesCore
import SwiftUI

/// Developer tool: renders the app's windows offscreen to PNG files, without event taps,
/// permissions or touching the real settings file.
///
///     mgestures.app/Contents/MacOS/mgestures --snapshot <folder> [--light | --dark]
///
/// Used to check the UI and to make screenshots for the README (scripts/snapshot-ui.sh).
@MainActor
enum Snapshot {
    static let argument = "--snapshot"

    static var requestedFolder: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: argument), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func run(into folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if CommandLine.arguments.contains("--dark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else if CommandLine.arguments.contains("--light") {
            NSApp.appearance = NSAppearance(named: .aqua)
        }

        // A throwaway store in a temporary file, with a couple of sample customizations.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("mgestures-snapshot-\(UUID().uuidString).json")
        let store = ConfigStore(fileURL: file)
        store.config.onboardingCompleted = true
        let finder = "com.apple.finder"
        store.config.appBindings[finder] = AppBindings(name: "Finder")
        store.config.appBindings[finder]?.bindings["Left"] = ActionConfig(kind: .navigateBack)
        store.config.excludedApps = [ExcludedApp(bundleID: "com.apple.Terminal", name: "Terminal")]
        let state = AppState()
        state.monitorRunning = true

        let panes: [(String, SettingsPane)] = [
            ("settings-general", .general),
            ("settings-gestures", .gestures),
            ("settings-appearance", .appearance),
            ("settings-recognition", .recognition),
            ("settings-excluded", .excludedApps),
            ("settings-app", .app("com.apple.finder")),
        ]
        for (name, pane) in panes {
            let model = SettingsModel()
            model.selection = pane
            render(SettingsView(store: store, state: state, model: model), size: NSSize(width: 860, height: 640), name: name, in: folder)
        }

        let onboardingState = AppState()
        render(OnboardingView(store: store, state: onboardingState, openSettings: {}, close: {}), size: nil, name: "onboarding", in: folder)
        onboardingState.monitorRunning = true
        onboardingState.lastGesture = L("Left")
        render(OnboardingView(store: store, state: onboardingState, openSettings: {}, close: {}), size: nil, name: "onboarding-done", in: folder)

        render(RecordGestureView(store: store, isPresented: .constant(true)), size: nil, name: "record", in: folder)
        render(
            HUDView(title: L("Left"), detail: L(ActionKind.tileLeft.title), symbol: ActionKind.tileLeft.symbol)
                .padding(30)
                .background(Color(white: 0.5)),
            size: nil, name: "hud", in: folder
        )
        try? FileManager.default.removeItem(at: file)
    }

    private static func render<V: View>(_ view: V, size: NSSize?, name: String, in folder: URL) {
        let host = NSHostingView(rootView: view)
        let frame = NSRect(origin: .zero, size: size ?? host.fittingSize)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        // Let SwiftUI and AppKit lay out (lists fill in asynchronously).
        for _ in 0..<6 { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        host.layoutSubtreeIfNeeded()

        let bounds = host.bounds
        guard let rep = host.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        host.cacheDisplay(in: bounds, to: rep)
        let url = folder.appendingPathComponent("\(name).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path) \(Int(bounds.width))x\(Int(bounds.height))")
        window.orderOut(nil)
    }
}
