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

    static func moveToApplicationsAndRelaunch() throws {
        let source = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(source.lastPathComponent)
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.trashItem(at: destination, resultingItemURL: nil)
        }
        try fm.copyItem(at: source, to: destination)
        log.info("Copied app to \(destination.path, privacy: .public)")

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [SingleInstance.relaunchArgument]
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    log.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
                NSApp.terminate(nil)
            }
        }
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
        // After "Move to Applications" the old copy quits right after launching us; give it a moment.
        let deadline = Date().addingTimeInterval(CommandLine.arguments.contains(relaunchArgument) ? 5 : 1)
        while !others().isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if let other = others().first {
            other.activate()
            return false
        }
        return true
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to mgestures").font(.title2.bold())
                    Text("Hold a mouse button, draw a shape, release.")
                        .foregroundStyle(.secondary)
                }
            }

            if model.needsMove {
                StepView(number: 1, title: "Move to the Applications folder", done: false) {
                    Text("mgestures is running from \(model.currentFolder). Launch at login and permissions work reliably only from Applications.")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Move to Applications") { model.move() }
                            .buttonStyle(.borderedProminent)
                        Button("Not Now") { model.skipMove() }
                    }
                    if let error = model.moveError {
                        Text(verbatim: error).font(.caption).foregroundStyle(.red)
                    }
                }
            }

            StepView(number: model.stepOffset + 1, title: "Allow Accessibility access", done: state.monitorRunning) {
                Text("mgestures needs this to see the mouse buttons and to move windows. It does not record or send anything; the keyboard is only observed while you are drawing, to catch Esc.")
                    .fixedSize(horizontal: false, vertical: true)
                if !state.monitorRunning {
                    Button("Open Accessibility Settings…") {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                    Text("Turn on mgestures in the list. This window updates by itself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            StepView(number: model.stepOffset + 2, title: "Choose the button you draw with", done: false) {
                Picker("Trigger button", selection: $store.config.triggerButton) {
                    ForEach(TriggerButton.allCases) { button in
                        Text(L(button.title)).tag(button)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Text("A quick click with this button still works normally. You can also require a modifier key in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StepView(number: model.stepOffset + 3, title: "Try a gesture", done: state.lastGesture != nil) {
                if let gesture = state.lastGesture {
                    Text("Recognized “\(gesture)”. You're all set.")
                } else if usesMiddleButton {
                    Text("Hold the middle mouse button and draw a line to the left or right: the focused window snaps to that half of the screen. Up maximizes, down minimizes.")
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Hold the right mouse button and draw a line to the left or right: the focused window snaps to that half of the screen. Up maximizes, down minimizes.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(state.monitorRunning ? 1 : 0.45)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text("There's more").font(.headline)
                FeatureLine(symbol: "scribble.variable", text: "Record your own shapes")
                FeatureLine(symbol: "square.stack.3d.up", text: "Different gestures for each app")
                FeatureLine(symbol: "scribble", text: "Try tab: see how a stroke is recognized")
                FeatureLine(symbol: "nosign", text: "Turn gestures off in apps that need the button")
                FeatureLine(symbol: "keyboard", text: "On/off shortcut, sound and haptic feedback")
                FeatureLine(symbol: "macwindow.on.rectangle", text: "Window, app, media and system actions, shortcuts and scripts")
            }

            HStack {
                Button("Open Settings…", action: openSettings)
                Spacer()
                Button("Done") {
                    store.config.onboardingCompleted = true
                    close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
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
        do {
            try AppMover.moveToApplicationsAndRelaunch()
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
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(Color.accentColor)
            Text(text)
        }
    }
}

private struct StepView<Content: View>: View {
    let number: Int
    let title: LocalizedStringKey
    let done: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color.secondary.opacity(0.2))
                    .frame(width: 26, height: 26)
                if done {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                } else {
                    Text(verbatim: "\(number)").font(.callout.bold())
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                content
            }
        }
    }
}
