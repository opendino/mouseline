import AppKit
import MGesturesCore
import SwiftUI

/// The Excluded Apps tab: apps in which the trigger button behaves normally.
struct ExcludedAppsView: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("In these apps the mouse button works normally and gestures are off — useful for 3D tools, games, remote desktops and virtual machines. The app under the cursor decides, not the active one.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                if store.config.excludedApps.isEmpty {
                    Text("No excluded apps.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.config.excludedApps) { app in
                    HStack(spacing: 10) {
                        Image(nsImage: AppInfo.icon(bundleID: app.bundleID))
                            .resizable()
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: app.name)
                            Text(verbatim: app.bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            store.config.excludedApps.removeAll { $0.bundleID == app.bundleID }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove")
                    }
                }
            }

            HStack {
                Menu("Add Running App") {
                    ForEach(AppInfo.runningApps(excluding: Set(store.config.excludedApps.map(\.bundleID))), id: \.bundleID) { app in
                        Button(app.name) { add(app) }
                    }
                }
                .fixedSize()
                Button("Add App…") {
                    AppInfo.chooseApps(multiple: true).forEach(add)
                }
                Spacer()
            }
        }
    }

    private func add(_ app: ExcludedApp) {
        guard !store.config.isExcluded(bundleID: app.bundleID) else { return }
        store.config.excludedApps.append(app)
        store.config.excludedApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
