import AppKit
import MGesturesCore
import SwiftUI

enum GestureFilter: String, CaseIterable {
    case basic
    case all
}

@MainActor
final class GesturesModel: ObservableObject {
    /// Bundle id of the app whose gestures are shown; nil = all apps (global bindings).
    @Published var scope: String?
    @Published var filter = GestureFilter.all
    @Published var showUnassigned = true
    @Published var showRecorder = false
}

/// The Gestures tab: every shape with its action, globally or for one app.
struct GesturesView: View {
    @ObservedObject var store: ConfigStore
    @StateObject private var model = GesturesModel()

    /// The selected app scope, if it still exists (an import or removal may have dropped it).
    private var scope: String? {
        guard let scope = model.scope, store.config.appBindings[scope] != nil else { return nil }
        return scope
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            scopeBar
            Group {
                if let scope {
                    Text("Shapes not overridden here use the All Apps setting. Choose “No action” in an override to turn a shape off in \(appName(scope)).")
                } else if store.config.triggerButton == .middle {
                    Text("Hold the middle mouse button and draw a shape. The dot marks where the stroke starts.")
                } else {
                    Text("Hold the right mouse button and draw a shape. The dot marks where the stroke starts.")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            filterBar
            List {
                ForEach(GestureGroup.allCases.filter { model.filter == .all || $0.isBasic }, id: \.self) { group in
                    section(for: group)
                }
            }
        }
        .sheet(isPresented: $model.showRecorder) {
            RecordGestureView(store: store, isPresented: $model.showRecorder)
        }
    }

    // MARK: Bars

    private var scopeBar: some View {
        HStack {
            AppScopePicker(title: "Gestures for", store: store, scope: $model.scope)
                .frame(maxWidth: 340)
            Menu("Add App") {
                ForEach(AppInfo.runningApps(excluding: Set(store.config.appBindings.keys)), id: \.bundleID) { app in
                    Button(app.name) { addScope(app) }
                }
                Divider()
                Button("Choose…") {
                    if let app = AppInfo.chooseApps(multiple: false).first { addScope(app) }
                }
            }
            .fixedSize()
            if let scope {
                Button("Remove App") { removeScope(scope) }
            }
            Spacer()
        }
    }

    private var filterBar: some View {
        HStack {
            Picker("Shapes", selection: $model.filter) {
                Text("Basic").tag(GestureFilter.basic)
                Text("All Shapes").tag(GestureFilter.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Toggle("Show unassigned", isOn: $model.showUnassigned)
                .toggleStyle(.checkbox)
            Spacer()
            Button("Record New Gesture…") { model.showRecorder = true }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func section(for group: GestureGroup) -> some View {
        let templates = templates(in: group)
        if group == .custom {
            Section(L(group.rawValue)) {
                if store.config.customGestures.isEmpty {
                    Text("No custom gestures yet. Use “Record New Gesture…” to draw your own.")
                        .foregroundStyle(.secondary)
                } else if templates.isEmpty {
                    Text("All custom gestures are unassigned.")
                        .foregroundStyle(.secondary)
                }
                ForEach(templates) { template in
                    GestureRow(template: template, store: store, scope: scope)
                }
            }
        } else if !templates.isEmpty {
            Section(L(group.rawValue)) {
                ForEach(templates) { template in
                    GestureRow(template: template, store: store, scope: scope)
                }
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

    // MARK: Scopes

    private func appName(_ bundleID: String) -> String {
        let name = store.config.appBindings[bundleID]?.name ?? ""
        return name.isEmpty ? bundleID : name
    }

    private func addScope(_ app: ExcludedApp) {
        if store.config.appBindings[app.bundleID] == nil {
            store.config.appBindings[app.bundleID] = AppBindings(name: app.name)
        }
        model.scope = app.bundleID
    }

    private func removeScope(_ bundleID: String) {
        let confirmed = Alerts.confirm(
            LF("Remove the gestures for %@?", appName(bundleID)),
            info: L("All shapes will use the All Apps settings in this app again."),
            confirmTitle: L("Remove")
        )
        guard confirmed else { return }
        model.scope = nil
        store.config.appBindings.removeValue(forKey: bundleID)
    }
}

/// One shape with its action. In an app scope it shows the inherited action until overridden.
struct GestureRow: View {
    let template: GestureTemplate
    @ObservedObject var store: ConfigStore
    let scope: String?

    private var id: String { template.id }
    private var isCustom: Bool { template.group == .custom }
    private var isOverridden: Bool { scope.map { store.config.hasOverride(for: id, in: $0) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ShapePreview(points: template.points)
                    .frame(width: 34, height: 34)
                if isCustom {
                    TextField("Name", text: nameBinding)
                        .frame(width: 160)
                } else {
                    Text(L(id))
                        .frame(width: 160, alignment: .leading)
                }

                if let scope, !isOverridden {
                    Text(LF("Default: %@", L(store.config.action(for: id).kind.title)))
                        .foregroundStyle(.secondary)
                        .frame(width: 260, alignment: .leading)
                    Button("Override") {
                        store.config.appBindings[scope]?.bindings[id] = store.config.action(for: id)
                    }
                } else {
                    ActionPicker(kind: actionBinding.kind)
                        .frame(width: 260)
                    if let scope {
                        Button("Use Default") {
                            store.config.appBindings[scope]?.bindings.removeValue(forKey: id)
                        }
                    }
                }
                Spacer()
                if isCustom {
                    Button(role: .destructive, action: deleteGesture) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete gesture")
                }
            }
            if scope == nil || isOverridden {
                ActionDetailView(action: actionBinding)
                    .padding(.leading, 46)
            }
        }
        .padding(.vertical, 2)
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
            LF("Delete “%@”?", store.config.displayName(for: id)),
            info: L("Its actions are removed too, in all apps."),
            confirmTitle: L("Delete")
        )
        if confirmed { store.config.removeCustomGesture(id: id) }
    }
}
