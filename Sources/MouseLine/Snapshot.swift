import AppKit
import MouseLineCore
import SwiftUI

/// Developer tool: renders the app's windows offscreen to PNG files, without event taps,
/// permissions or touching the real settings file.
///
///     MouseLine.app/Contents/MacOS/MouseLine --snapshot <folder> [--light | --dark] [--onscreen]
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
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("MouseLine-snapshot-\(UUID().uuidString).json")
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
            ("settings-calibration", .calibration),
            ("settings-app", .app("com.apple.finder")),
        ]
        for (name, pane) in panes {
            let model = SettingsModel()
            model.selection = pane
            guard shouldRender(name) else { continue }
            // The real pane title, as the settings window shows it.
            var built: NSWindow?
            let window = SettingsWindow.make(store: store, state: state, model: model) { built?.title = $0 }
            built = window
            show(window, name: name, in: folder)
        }

        let onboardingState = AppState()
        render(OnboardingView(store: store, state: onboardingState, openSettings: {}, close: {}), size: nil, name: "onboarding", in: folder, transparent: true)
        onboardingState.monitorRunning = true
        onboardingState.lastGesture = L("Left")
        render(OnboardingView(store: store, state: onboardingState, openSettings: {}, close: {}), size: nil, name: "onboarding-done", in: folder, transparent: true)

        render(RecordGestureView(store: store, isPresented: .constant(true)), size: nil, name: "record", in: folder)
        render(CalibrationView(store: store, state: state, isPresented: .constant(true)), size: nil, name: "calibration", in: folder)
        render(
            HUDView(title: L("Left"), detail: L(ActionKind.tileLeft.title), symbol: ActionKind.tileLeft.symbol)
                .padding(30)
                .background(onscreen ? Color.clear : Color(white: 0.5)),
            size: nil, name: "hud", in: folder, transparent: onscreen
        )
        try? FileManager.default.removeItem(at: file)
    }

    /// With --onscreen each window is shown in the middle of the screen for about a second
    /// and captured by the window server, so Liquid Glass and blur are in the picture
    /// (over the desktop picture; other apps' windows are not captured).
    private static var onscreen: Bool { CommandLine.arguments.contains("--onscreen") }

    /// `--only a,b` limits the snapshot to those names.
    private static func shouldRender(_ name: String) -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--only"), i + 1 < args.count else { return true }
        return args[i + 1].split(separator: ",").contains { $0 == name }
    }

    /// Shows a ready-made window (offscreen, or on screen with --onscreen) and saves it.
    private static func show(_ window: NSWindow, name: String, in folder: URL) {
        if onscreen, let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.frame.midX - window.frame.width / 2, y: screen.frame.midY - window.frame.height / 2))
        } else {
            window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        }
        window.orderFrontRegardless()
        for _ in 0..<(onscreen ? 12 : 6) { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        if onscreen {
            capture(window, name: name, in: folder)
        } else if let view = window.contentView {
            view.layoutSubtreeIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                let url = folder.appendingPathComponent("\(name).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print("wrote \(url.path)")
            }
        }
        window.orderOut(nil)
    }

    private static func render<V: View>(_ view: V, size: NSSize?, name: String, in folder: URL, transparent: Bool = false) {
        guard shouldRender(name) else { return }
        let host = NSHostingView(rootView: view)
        let frame = NSRect(origin: .zero, size: size ?? host.fittingSize)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        if transparent {
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        window.contentView = host
        if onscreen, let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.frame.midX - frame.width / 2, y: screen.frame.midY - frame.height / 2))
        } else {
            window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        }
        window.orderFrontRegardless()
        // Let SwiftUI and AppKit lay out (lists fill in asynchronously).
        for _ in 0..<(onscreen ? 12 : 6) { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        host.layoutSubtreeIfNeeded()

        if onscreen {
            capture(window, name: name, in: folder)
            window.orderOut(nil)
            return
        }

        let bounds = host.bounds
        guard let rep = host.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        host.cacheDisplay(in: bounds, to: rep)
        let url = folder.appendingPathComponent("\(name).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path) \(Int(bounds.width))x\(Int(bounds.height))")
        window.orderOut(nil)
    }

    /// Captures the screen area under `window` (the window composited over the desktop).
    /// CGWindowListCreateImage is unavailable to Swift on new SDKs but still works for an
    /// app's own windows, so it is looked up at runtime.
    private static func capture(_ window: NSWindow, name: String, in folder: URL) {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let f = window.frame.insetBy(dx: -24, dy: -24)
        let rect = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
        guard let image = create(rect, 1 /* on screen only */, 0, 0)?.takeRetainedValue() else { return }
        let url = folder.appendingPathComponent("\(name).png")
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path) (on screen)")
    }
}
