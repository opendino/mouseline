import AppKit
import MouseLineCore
import SwiftUI

/// The Excluded Apps pane: apps in which the trigger button behaves normally.
struct ExcludedAppsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject private var running = RunningApps.shared

    var body: some View {
        Form {
            Section {
                PaneHeader(
                    title: L("Excluded Apps"),
                    subtitle: L("In these apps the mouse button works normally and gestures are off — useful for 3D tools, games, remote desktops and virtual machines. The app under the cursor decides, not the active one.")
                ) {
                    IconTile(symbol: "nosign", color: .red, size: 40)
                }
            }

            Section {
                if store.config.excludedApps.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No excluded apps. Gestures work everywhere.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                ForEach(store.config.excludedApps) { app in
                    HStack(spacing: 12) {
                        AppIconView(bundleID: app.bundleID, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: app.name)
                            Text(verbatim: app.bundleID).captionStyle()
                        }
                        Spacer()
                        Button {
                            store.config.excludedApps.removeAll { $0.bundleID == app.bundleID }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Remove")
                    }
                    .padding(.vertical, 1)
                }
                HStack {
                    Spacer()
                    Menu("Add Running App") {
                        ForEach(running.list(excluding: Set(store.config.excludedApps.map(\.bundleID))), id: \.bundleID) { app in
                            Button(app.name) { add(app) }
                        }
                    }
                    .fixedSize()
                    Button("Add App…") {
                        AppInfo.chooseApps(multiple: true).forEach(add)
                    }
                    .glassButtonStyle()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func add(_ app: ExcludedApp) {
        guard !store.config.isExcluded(bundleID: app.bundleID) else { return }
        store.config.excludedApps.append(app)
        store.config.excludedApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
