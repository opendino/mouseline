import AppKit
import MGesturesCore
import SwiftUI

// MARK: - Action picker and details

/// Picks an action, grouped by category.
struct ActionPicker: View {
    @Binding var kind: ActionKind

    var body: some View {
        Picker("Action", selection: $kind) {
            ActionMenuItems { $0 }
        }
        .labelsHidden()
        .fixedSize()
    }
}

/// Picks an app-specific action; nil means "use the All Apps setting".
struct ScopedActionPicker: View {
    @Binding var kind: ActionKind?
    let inherited: ActionKind

    var body: some View {
        Picker("Action", selection: $kind) {
            Text(LF("Default (%@)", L(inherited.title))).tag(ActionKind?.none)
            Divider()
            ActionMenuItems { Optional($0) }
        }
        .labelsHidden()
        .fixedSize()
    }
}

/// "No action" plus every action, in sections by category.
struct ActionMenuItems<Tag: Hashable>: View {
    let tag: (ActionKind) -> Tag

    var body: some View {
        Text(L(ActionKind.none.title)).tag(tag(.none))
        ForEach(ActionCategory.allCases.filter { $0 != .none }, id: \.self) { category in
            Section(L(category.rawValue)) {
                ForEach(ActionKind.kinds(in: category)) { kind in
                    Text(L(kind.title)).tag(tag(kind))
                }
            }
        }
    }
}

/// Extra inputs for actions that need them (shortcut, app, URL, command, script).
struct ActionDetailView: View {
    @Binding var action: ActionConfig

    var body: some View {
        switch action.kind {
        case .keyboardShortcut:
            ShortcutRecorder(combo: $action.shortcut)
        case .openApplication:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("Application path", text: $action.appPath)
                    Button("Choose…") {
                        if let url = AppInfo.chooseAppURL() { action.appPath = url.path }
                    }
                }
                TextField("Arguments (optional)", text: $action.appArguments)
                    .font(.body.monospaced())
                Toggle("Always open a new instance (arguments only apply to new instances)", isOn: $action.newInstance)
                    .font(.caption)
            }
        case .openURL:
            TextField("https://example.com", text: $action.url)
        case .shellCommand:
            TextField("Command (runs in zsh)", text: $action.command)
                .font(.body.monospaced())
        case .appleScript:
            VStack(alignment: .leading, spacing: 4) {
                TextEditor(text: $action.script)
                    .font(.body.monospaced())
                    .frame(height: 72)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.3)))
                Text("macOS asks once for each app the script controls (Privacy & Security → Automation).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }
}

/// ActionDetailView laid out for a settings row: placeholders instead of form labels.
struct ActionDetailRow: View {
    @Binding var action: ActionConfig

    var body: some View {
        ActionDetailView(action: $action)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .controlSize(.regular)
    }
}

// MARK: - Shape preview

/// Draws a shape, with a dot where the stroke starts and an arrowhead where it ends.
struct ShapePreview: View {
    let points: [StrokePoint]
    var tint: Color = .primary

    var body: some View {
        Canvas { context, size in
            let prepared = Recognizer.prepare(points) // centered, larger side = 100
            let scale = min(size.width, size.height) * 0.78 / Recognizer.referenceSize
            let mapped = prepared.map {
                CGPoint(x: size.width / 2 + $0.x * scale, y: size.height / 2 + $0.y * scale)
            }
            guard let first = mapped.first, let last = mapped.last else { return }

            var path = Path()
            path.addLines(mapped)
            let width = max(1.5, min(size.width, size.height) / 15)
            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))

            // Arrowhead along the direction of the last segment.
            let before = mapped[max(0, mapped.count - 3)]
            let angle = atan2(last.y - before.y, last.x - before.x)
            var arrow = Path()
            for side in [-1.0, 1.0] {
                let a = angle + .pi + side * .pi / 6
                arrow.move(to: last)
                arrow.addLine(to: CGPoint(x: last.x + width * 3 * cos(a), y: last.y + width * 3 * sin(a)))
            }
            context.stroke(arrow, with: .color(tint), style: StrokeStyle(lineWidth: width, lineCap: .round))

            let r = width * 1.6
            let dot = CGRect(x: first.x - r, y: first.y - r, width: 2 * r, height: 2 * r)
            context.fill(Path(ellipseIn: dot), with: .color(tint))
            context.stroke(Path(ellipseIn: dot.insetBy(dx: -width * 0.4, dy: -width * 0.4)), with: .color(tint.opacity(0.35)), lineWidth: width * 0.5)
        }
    }
}

// MARK: - Drawing pad

/// Collects one stroke drawn with the left mouse button.
@MainActor
final class DrawingModel: ObservableObject {
    @Published private(set) var points: [CGPoint] = []
    private var drawing = false

    func changed(_ p: CGPoint) {
        if !drawing {
            drawing = true
            points = [p]
            return
        }
        if let last = points.last, hypot(p.x - last.x, p.y - last.y) < 1 { return }
        points.append(p)
    }

    /// Ends the stroke and returns it (view coordinates, y down — like screen strokes).
    func ended() -> [StrokePoint] {
        drawing = false
        return points.map { StrokePoint($0.x, $0.y) }
    }

    func clear() {
        drawing = false
        points = []
    }
}

/// An area to draw a stroke in. It uses the LEFT button: right-button drags anywhere,
/// including in our own windows, are captured by mgestures' event tap.
struct DrawingPad: View {
    @ObservedObject var model: DrawingModel
    var height: CGFloat = 240
    var onStroke: ([StrokePoint]) -> Void

    private static let ink = Color(nsColor: NSColor(srgbRed: 1, green: 0.55, blue: 0.1, alpha: 1))

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
            DotGrid()
                .opacity(0.5)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
            if model.points.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "scribble.variable")
                        .font(.system(size: 28, weight: .light))
                    Text("Draw here with the left mouse button")
                }
                .foregroundStyle(.tertiary)
            }
            Canvas { context, _ in
                guard let first = model.points.first else { return }
                var path = Path()
                path.move(to: first)
                path.addLines(model.points)
                context.stroke(path, with: .color(Self.ink), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                context.fill(Path(ellipseIn: CGRect(x: first.x - 4, y: first.y - 4, width: 8, height: 8)), with: .color(.accentColor))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { model.changed($0.location) }
                .onEnded { _ in onStroke(model.ended()) }
        )
    }
}

/// A faint dot grid, like graph paper, behind the drawing area.
struct DotGrid: View {
    var spacing: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            var dots = Path()
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
                    x += spacing
                }
                y += spacing
            }
            context.fill(dots, with: .color(.secondary.opacity(0.35)))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Shortcut recorder

@MainActor
final class ShortcutRecorderModel: ObservableObject {
    @Published private(set) var recording = false
    private var monitor: Any?

    /// Captures the next key press in our windows; Esc without modifiers cancels.
    func start(onRecord: @escaping (KeyCombo) -> Void) {
        stop()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let mods = event.modifierFlags.intersection(KeyCombo.relevantModifiers)
            if !(event.keyCode == 53 && mods.isEmpty) {
                onRecord(KeyCombo(event: event))
            }
            self?.stop()
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

/// Click, then press a key combination to record it. Esc cancels.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @StateObject private var model = ShortcutRecorderModel()

    var body: some View {
        HStack {
            Button {
                if model.recording { model.stop() } else { model.start { combo = $0 } }
            } label: {
                if model.recording {
                    Text("Press a shortcut… (Esc to cancel)")
                } else if let combo {
                    Text(verbatim: combo.display).font(.body.monospaced())
                } else {
                    Text("Record Shortcut")
                }
            }
            if combo != nil && !model.recording {
                Button("Clear") { combo = nil }
            }
        }
        .onDisappear { model.stop() }
    }
}

// MARK: - App scope picker

/// "All Apps" plus every app that has its own gestures.
struct AppScopePicker: View {
    let title: LocalizedStringKey
    @ObservedObject var store: ConfigStore
    @Binding var scope: String?

    var body: some View {
        Picker(title, selection: validScope) {
            Text("All Apps").tag(String?.none)
            ForEach(AppScopePicker.apps(in: store.config), id: \.bundleID) { app in
                Text(verbatim: app.name).tag(Optional(app.bundleID))
            }
        }
    }

    /// Reads an app that no longer has its own gestures (removed while selected here) as
    /// All Apps, which is what the results then use, instead of an empty selection.
    private var validScope: Binding<String?> {
        Binding(
            get: { scope.flatMap { store.config.appBindings[$0] != nil ? $0 : nil } },
            set: { scope = $0 }
        )
    }

    static func apps(in config: AppConfig) -> [ExcludedApp] {
        config.appBindings
            .map { ExcludedApp(bundleID: $0.key, name: $0.value.name.isEmpty ? $0.key : $0.value.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension AppConfig {
    /// Name shown to the user for a gesture, localized for built-in shapes. A custom gesture
    /// whose name was cleared in the list gets a placeholder, so titles and prompts are not blank.
    func localizedName(for gestureID: String) -> String {
        guard CustomGesture.isCustomID(gestureID) else { return L(gestureID) }
        let name = displayName(for: gestureID).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? L("Custom Gesture") : name
    }
}
