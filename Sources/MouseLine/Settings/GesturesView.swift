import AppKit
import MouseLineCore
import SwiftUI

enum GestureFilter: String, CaseIterable {
    case basic
    case all
}

@MainActor
final class GesturesModel: ObservableObject {
    @Published var filter = GestureFilter.all
    @Published var showUnassigned = true
    @Published var showRecorder = false
}

/// Every shape with its action — for all apps (scope nil) or as overrides for one app.
struct GesturesView: View {
    @ObservedObject var store: ConfigStore
    /// Bundle id of the app whose overrides are edited; nil = All Apps.
    let scope: String?
    var onRemove: () -> Void = {}
    @StateObject private var model = GesturesModel()

    var body: some View {
        Form {
            Section {
                header
            }

            Section {
                HStack {
                    Picker("Shapes", selection: $model.filter) {
                        Text("Basic").tag(GestureFilter.basic)
                        Text("All Shapes").tag(GestureFilter.all)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Toggle("Show unassigned", isOn: $model.showUnassigned)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            ForEach(GestureGroup.allCases.filter { model.filter == .all || $0.isBasic }, id: \.self) { group in
                section(for: group)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $model.showRecorder) {
            RecordGestureView(store: store, isPresented: $model.showRecorder)
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        if let scope {
            PaneHeader(
                title: appName(scope),
                subtitle: LF("Shapes set to Default use the All Apps setting. Choose “No action” to turn a shape off in %@.", appName(scope))
            ) {
                AppIconView(bundleID: scope, size: 40)
            } accessory: {
                Button("Remove App…", role: .destructive, action: onRemove)
                    .glassButtonStyle()
            }
        } else {
            PaneHeader(
                title: L("Gestures"),
                subtitle: store.config.triggerButton == .middle
                    ? L("Hold the middle mouse button and draw a shape. The dot marks where the stroke starts.")
                    : L("Hold the right mouse button and draw a shape. The dot marks where the stroke starts.")
            ) {
                IconTile(symbol: "hand.draw.fill", color: .blue, size: 40)
            } accessory: {
                Button {
                    model.showRecorder = true
                } label: {
                    Label("Record Gesture…", systemImage: "plus")
                }
                .glassButtonStyle(prominent: true)
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func section(for group: GestureGroup) -> some View {
        let templates = templates(in: group)
        if group == .custom {
            Section {
                if store.config.customGestures.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "scribble.variable")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No custom gestures yet")
                            Text("Draw your own shape and give it an action.")
                                .captionStyle()
                        }
                        Spacer()
                        Button("Record Gesture…") { model.showRecorder = true }
                    }
                    .padding(.vertical, 4)
                } else if templates.isEmpty {
                    Text("All custom gestures are unassigned.")
                        .foregroundStyle(.secondary)
                }
                ForEach(templates) { template in
                    GestureRow(template: template, store: store, scope: scope)
                }
            } header: {
                Text(L(group.rawValue))
            }
        } else if !templates.isEmpty {
            Section {
                ForEach(templates) { template in
                    GestureRow(template: template, store: store, scope: scope)
                }
            } header: {
                Text(L(group.rawValue))
            }
        }
    }

    private func templates(in group: GestureGroup) -> [GestureTemplate] {
        let all = group == .custom
            ? store.config.customGestures.map(\.template)
            : GestureTemplate.builtIn.filter { $0.group == group }
        guard !model.showUnassigned else { return all }
        return all.filter { store.config.action(for: $0.id, in: scope).kind != .none }
    }

    private func appName(_ bundleID: String) -> String {
        let name = store.config.appBindings[bundleID]?.name ?? ""
        return name.isEmpty ? bundleID : name
    }
}

/// One shape with its action. In an app scope the picker's first item follows All Apps.
struct GestureRow: View {
    let template: GestureTemplate
    @ObservedObject var store: ConfigStore
    let scope: String?

    private var id: String { template.id }
    private var isCustom: Bool { template.group == .custom }
    private var isOverridden: Bool { scope.map { store.config.hasOverride(for: id, in: $0) } ?? false }
    private var effectiveKind: ActionKind { store.config.action(for: id, in: scope).kind }

    /// Accent for shapes that do something here; in an app scope, only for overrides.
    private var tileTint: Color {
        if effectiveKind == .none { return .secondary }
        if scope != nil && !isOverridden { return .secondary }
        return .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent {
                HStack(spacing: 8) {
                    if scope != nil {
                        ScopedActionPicker(kind: scopedKind, inherited: store.config.action(for: id).kind)
                    } else {
                        ActionPicker(kind: actionBinding.kind)
                    }
                    if isCustom {
                        Button(action: deleteGesture) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Delete gesture")
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    ShapeTile(points: template.points, size: 34, tint: tileTint)
                    if isCustom {
                        TextField("Name", text: nameBinding)
                            .textFieldStyle(.plain)
                            .labelsHidden()
                    } else {
                        Text(L(id))
                    }
                    if isOverridden {
                        Text("Custom")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            if (scope == nil || isOverridden) && actionBinding.wrappedValue.kind.hasParameters {
                ActionDetailRow(action: actionBinding)
                    .padding(.leading, 46)
                    .padding(.bottom, 2)
            }
        }
        .padding(.vertical, 1)
    }

    /// Edits the global binding, or this app's override.
    private var actionBinding: Binding<ActionConfig> {
        Binding(
            get: { store.config.action(for: id, in: scope) },
            set: { newValue in
                if let scope {
                    store.config.appBindings[scope]?.bindings[id] = newValue
                } else {
                    store.setBinding(newValue, for: id)
                }
            }
        )
    }

    /// nil = no override (follow All Apps).
    private var scopedKind: Binding<ActionKind?> {
        Binding(
            get: { isOverridden ? store.config.action(for: id, in: scope).kind : nil },
            set: { kind in
                guard let scope else { return }
                if let kind {
                    var action = isOverridden ? store.config.action(for: id, in: scope) : store.config.action(for: id)
                    action.kind = kind
                    store.config.appBindings[scope]?.bindings[id] = action
                } else {
                    store.config.appBindings[scope]?.bindings.removeValue(forKey: id)
                }
            }
        )
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { store.config.customGesture(id: id)?.name ?? "" },
            set: { newName in
                if let index = store.config.customGestures.firstIndex(where: { $0.id == id }) {
                    store.config.customGestures[index].name = newName
                }
            }
        )
    }

    private func deleteGesture() {
        let confirmed = Alerts.confirm(
            LF("Delete “%@”?", store.config.localizedName(for: id)),
            info: L("Its actions are removed too, in all apps."),
            confirmTitle: L("Delete")
        )
        if confirmed { store.config.removeCustomGesture(id: id) }
    }
}
