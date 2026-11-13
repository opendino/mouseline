import AppKit
import MGesturesCore
import os
import SwiftUI

private let log = Logger(subsystem: "dev.mgestures.app", category: "onboarding")

/// Copies the running app into /Applications and relaunches it from there.
/// "Launch at login" and stable Accessibility permissions both expect the app to live there.
@MainActor
enum AppMover {
    static var isInApplicationsFolder: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let userApps = (NSHomeDirectory() as NSString).appendingPathComponent("Applications") + "/"
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApps)
    }

    /// True for a real .app bundle (not `swift run`).
    static var isAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Copies the app, launches the copy and quits. `onRelaunchError` reports a launch that
    /// failed after the copy succeeded (e.g. blocked by Gatekeeper); this copy keeps running.
    static func moveToApplicationsAndRelaunch(onRelaunchError: @escaping @MainActor @Sendable (Error) -> Void) throws {
        let source = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(source.lastPathComponent)
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.trashItem(at: destination, resultingItemURL: nil)
        }
        try fm.copyItem(at: source, to: destination)
        removeQuarantine(from: destination)
        log.info("Copied app to \(destination.path, privacy: .public)")
        let removeOriginal = canTrashOriginal(source)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [SingleInstance.relaunchArgument]
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    log.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
                    onRelaunchError(error)
                    return
                }
                // Otherwise Spotlight or Launchpad can later start the stale copy, whose own
                // "Move" would replace the installed app with it. A running app's bundle can
                // go to the Trash safely.
                if removeOriginal {
                    do {
                        try FileManager.default.trashItem(at: source, resultingItemURL: nil)
                    } catch {
                        log.error("Could not trash the original copy: \(error.localizedDescription, privacy: .public)")
                    }
                }
                NSApp.terminate(nil)
            }
        }
    }

    /// `copyItem` keeps extended attributes, so a downloaded copy would still be quarantined
    /// in /Applications and run translocated again (from a random read-only path), making
    /// the welcome guide offer the move over and over. Finder drops the attribute on a
    /// move; do the same. Errors (mostly "no such attribute") are irrelevant here.
    private static func removeQuarantine(from bundle: URL) {
        var paths = [bundle.path]
        if let items = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: nil) {
            for case let item as URL in items { paths.append(item.path) }
        }
        for path in paths {
            _ = removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }

    /// Only a copy the user put somewhere writable is removed: not a translocated copy
    /// (a read-only mirror of the download), not one on a disk image or other read-only
    /// volume, and never one already in an Applications folder.
    private static func canTrashOriginal(_ source: URL) -> Bool {
        let path = source.resolvingSymlinksInPath().path
        if path.contains("/AppTranslocation/") || isInApplicationsFolder { return false }
        if (try? source.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true { return false }
        return FileManager.default.isWritableFile(atPath: source.deletingLastPathComponent().path)
    }
}

/// Makes sure only one copy of mgestures captures the mouse at a time.
@MainActor
enum SingleInstance {
    static let relaunchArgument = "--relaunched"

    /// Returns false if another instance keeps running (this one should quit).
    static func claim() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return true }
        let me = ProcessInfo.processInfo.processIdentifier
        func others() -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.processIdentifier != me && !$0.isTerminated }
        }
        // Exactly one copy must survive when two start at the same moment (say, a login item
        // and a restored window): the one launched first wins, ties go to the lower pid.
        let myLaunch = NSRunningApplication.current.launchDate ?? .distantFuture
        func winner() -> NSRunningApplication? {
            others().first { other in
                let launch = other.launchDate ?? .distantFuture
                return launch < myLaunch || (launch == myLaunch && other.processIdentifier < me)
            }
        }
        // After "Move to Applications" the old copy quits right after launching us; give it a moment.
        let deadline = Date().addingTimeInterval(CommandLine.arguments.contains(relaunchArgument) ? 5 : 1)
        while winner() != nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard let other = winner() else { return true }
        // A menu bar app usually has no window, so activate() would show nothing. Opening its
        // bundle sends it a reopen event instead, and it answers by showing Settings.
        if let url = other.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else {
            other.activate()
        }
        return false
    }
}

// MARK: - Onboarding window

struct OnboardingView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var state: AppState
    @StateObject private var model = OnboardingModel()
    let openSettings: () -> Void
    let close: () -> Void

    private var usesMiddleButton: Bool { store.config.triggerButton == .middle }

    var body: some View {
        HStack(spacing: 0) {
            // Left: welcome and what else the app can do.
            VStack(alignment: .leading, spacing: 0) {
                OwnAppIcon(size: 64)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .padding(.bottom, 16)
                Text("Welcome to mgestures")
                    .font(.system(size: 24, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Hold a mouse button, draw a shape, release.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                Spacer(minLength: 24)
                features
            }
            .padding(.horizontal, 26)
            .padding(.top, 44)
            .padding(.bottom, 26)
            .frame(width: 290)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.primary.opacity(0.035))

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 0.5)

            // Right: the steps and the buttons.
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    if model.needsMove { moveStep }
                    accessStep
                    buttonStep
                    tryStep
                    calibrateStep
                }
                .padding(.horizontal, 22)
                .padding(.top, 44)
                .padding(.bottom, 18)
                Spacer(minLength: 0)
                footer
            }
            .frame(width: 520)
        }
        .fixedSize(horizontal: false, vertical: true)
        .modifier(FloatingGlassPanel(cornerRadius: 26))
    }

    // MARK: Sections

    private var moveStep: some View {
        StepCard(number: 1, title: "Move to the Applications folder", done: false) {
            Text("mgestures is running from \(model.currentFolder). Launch at login and permissions work reliably only from Applications.")
                .captionStyle()
            HStack {
                Button("Move to Applications") { model.move() }
                    .glassButtonStyle(prominent: true)
                Button("Not Now") { model.skipMove() }
                    .glassButtonStyle()
            }
            .padding(.top, 2)
            if let error = model.moveError {
                Text(verbatim: error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var accessStep: some View {
        StepCard(number: model.stepOffset + 1, title: "Allow Accessibility access", done: state.monitorRunning) {
            Text("mgestures needs this to see the mouse buttons and to move windows. It does not record or send anything; the keyboard is only observed while you are drawing, to catch Esc.")
                .captionStyle()
            if !state.monitorRunning {
                HStack(spacing: 10) {
                    Button("Open Accessibility Settings…") {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                    .glassButtonStyle(prominent: true)
                    Text("Turn on mgestures in the list. This window updates by itself.")
                        .captionStyle()
                }
                .padding(.top, 2)
            }
        }
    }

    private var buttonStep: some View {
        StepCard(number: model.stepOffset + 2, title: "Choose the button you draw with", done: false) {
            Picker("Trigger button", selection: $store.config.triggerButton) {
                ForEach(TriggerButton.allCases) { button in
                    Text(L(button.title)).tag(button)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Text("A quick click with this button still works normally. You can also require a modifier key in Settings.")
                .captionStyle()
        }
    }

    private var tryStep: some View {
        StepCard(number: model.stepOffset + 3, title: "Try a gesture", done: state.lastGesture != nil) {
            HStack(alignment: .center, spacing: 14) {
                Group {
                    if let gesture = state.lastGesture {
                        Text("Recognized “\(gesture)”. You're all set.")
                    } else if usesMiddleButton {
                        Text("Hold the middle mouse button and draw a line to the left or right: the focused window snaps to that half of the screen. Up maximizes, down minimizes.")
                    } else {
                        Text("Hold the right mouse button and draw a line to the left or right: the focused window snaps to that half of the screen. Up maximizes, down minimizes.")
                    }
                }
                .captionStyle()
                Spacer(minLength: 0)
                GestureDemo()
                    .frame(width: 120, height: 76)
            }
        }
        .opacity(state.monitorRunning ? 1 : 0.5)
    }

    private var calibrateStep: some View {
        StepCard(number: model.stepOffset + 4, title: "Fit it to your hand", done: store.config.isCalibrated) {
            HStack(spacing: 12) {
                Text("Optional, about 30 seconds: draw four shapes twice and mgestures tunes recognition to your strokes.")
                    .captionStyle()
                Spacer(minLength: 0)
                CalibrationStatus(store: store, state: state, compact: true)
            }
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("There's more")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            FeatureLine(symbol: "scribble.variable", color: .orange, text: "Record your own shapes")
            FeatureLine(symbol: "square.stack.3d.up.fill", color: .purple, text: "Different gestures for each app")
            FeatureLine(symbol: "cursorarrow.click.2", color: .blue, text: "Test strokes before you use them")
            FeatureLine(symbol: "nosign", color: .red, text: "Turn gestures off in apps that need the button")
            FeatureLine(symbol: "keyboard", color: .gray, text: "On/off shortcut, sound and haptics")
            FeatureLine(symbol: "macwindow.on.rectangle", color: .teal, text: "Window, media and system actions, scripts")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Open Settings…", action: openSettings)
                    .glassButtonStyle()
                Spacer()
                Button {
                    store.config.onboardingCompleted = true
                    close()
                } label: {
                    Text(state.monitorRunning ? L("Get Started") : L("Later"))
                        .frame(minWidth: 90)
                }
                .glassButtonStyle(prominent: true)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
    }
}

/// A small looping animation: a stroke is drawn to the left and the window snaps to the left half.
private struct GestureDemo: View {
    private static let period = 3.4

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period)
                draw(in: &context, size: size, t: t)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let screen = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        let screenPath = Path(roundedRect: screen, cornerRadius: 7, style: .continuous)
        context.fill(screenPath, with: .linearGradient(
            Gradient(colors: [Color(red: 0.36, green: 0.52, blue: 0.95), Color(red: 0.55, green: 0.38, blue: 0.86)]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: size.height)
        ))
        context.stroke(screenPath, with: .color(.black.opacity(0.15)), lineWidth: 0.5)

        // Phases: 0–0.3 rest, 0.3–1.3 draw, 1.3–1.8 snap, 1.8–2.8 hold, 2.8–3.4 return.
        func ease(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }
        let draw = ease((t - 0.3) / 1.0)
        let snap = t < 2.8 ? ease((t - 1.3) / 0.5) : 1 - ease((t - 2.8) / 0.6)
        let strokeAlpha = t < 1.3 ? 1 : max(0, 1 - (t - 1.3) / 0.35)

        let inset: CGFloat = 6
        let centered = CGRect(x: size.width * 0.24, y: size.height * 0.22, width: size.width * 0.52, height: size.height * 0.58)
        let left = CGRect(x: inset, y: inset, width: size.width / 2 - inset * 1.5, height: size.height - inset * 2)
        let s = CGFloat(snap)
        let window = CGRect(
            x: centered.minX + (left.minX - centered.minX) * s,
            y: centered.minY + (left.minY - centered.minY) * s,
            width: centered.width + (left.width - centered.width) * s,
            height: centered.height + (left.height - centered.height) * s
        )
        let windowPath = Path(roundedRect: window, cornerRadius: 4, style: .continuous)
        var shadowed = context
        shadowed.addFilter(.shadow(color: .black.opacity(0.25), radius: 3, y: 1))
        shadowed.fill(windowPath, with: .color(.white.opacity(0.95)))
        // Title bar dots.
        for (i, color) in [Color.red, .yellow, .green].enumerated() {
            let dot = CGRect(x: window.minX + 5 + CGFloat(i) * 6, y: window.minY + 4, width: 3.5, height: 3.5)
            context.fill(Path(ellipseIn: dot), with: .color(color.opacity(0.85)))
        }

        // The stroke: from the right of center towards the left.
        if draw > 0 && strokeAlpha > 0 {
            let start = CGPoint(x: size.width * 0.70, y: size.height * 0.55)
            let end = CGPoint(x: size.width * 0.28, y: size.height * 0.55)
            let tip = CGPoint(x: start.x + (end.x - start.x) * draw, y: start.y)
            var stroke = Path()
            stroke.move(to: start)
            stroke.addLine(to: tip)
            var glow = context
            glow.opacity = strokeAlpha
            let orange = Color(red: 1, green: 0.55, blue: 0.1)
            glow.addFilter(.shadow(color: orange, radius: 3))
            glow.stroke(stroke, with: .color(orange), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            glow.fill(Path(ellipseIn: CGRect(x: tip.x - 3.5, y: tip.y - 3.5, width: 7, height: 7)), with: .color(orange))
        }
    }
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var needsMove = AppMover.isAppBundle && !AppMover.isInApplicationsFolder
    @Published private(set) var moveError: String?

    var stepOffset: Int { needsMove ? 1 : 0 }

    var currentFolder: String {
        (Bundle.main.bundleURL.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    func move() {
        moveError = nil
        do {
            try AppMover.moveToApplicationsAndRelaunch { [weak self] error in
                self?.moveError = LF("Could not open the copy in Applications: %@", error.localizedDescription)
            }
        } catch {
            moveError = LF("Could not move the app: %@", error.localizedDescription)
        }
    }

    func skipMove() {
        needsMove = false
    }
}

private struct FeatureLine: View {
    let symbol: String
    let color: Color
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 9) {
            IconTile(symbol: symbol, color: color, size: 22)
            Text(text)
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One onboarding step on a card, with its number or a checkmark once it is done.
private struct StepCard<Content: View>: View {
    let number: Int
    let title: LocalizedStringKey
    let done: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(done ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(Color.accentColor.opacity(0.14)))
                    .frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text(verbatim: "\(number)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(done ? 0.035 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.25), value: done)
    }
}

/// The welcome window's body: one panel floating over the desktop. Liquid Glass on
/// macOS 26 and later, the under-window blur before. The window itself is transparent.
private struct FloatingGlassPanel: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            content
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(VisualEffectBackground(material: .underWindowBackground))
                .clipShape(shape)
        }
    }
}
