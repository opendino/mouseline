import AppKit
import MGesturesCore
import SwiftUI

// Shared visual building blocks, modelled on System Settings: colored symbol tiles,
// pane headers and shape tiles.

/// A white SF Symbol on a rounded, gently graded color square — like System Settings icons.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
            )
            .frame(width: size, height: size)
    }
}

/// The large icon, title and description at the top of a settings pane.
struct PaneHeader<Icon: View, Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let icon: Icon
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(.system(size: 15, weight: .semibold))
                Text(verbatim: subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.vertical, 6)
    }
}

extension PaneHeader where Accessory == EmptyView {
    init(title: String, subtitle: String, @ViewBuilder icon: () -> Icon) {
        self.init(title: title, subtitle: subtitle, icon: icon, accessory: { EmptyView() })
    }
}

/// A gesture shape on a soft rounded tile.
struct ShapeTile: View {
    let points: [StrokePoint]
    var size: CGFloat = 34
    var tint: Color = .accentColor

    var body: some View {
        ShapePreview(points: points, tint: tint)
            .padding(size * 0.12)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(tint.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(tint.opacity(0.18), lineWidth: 0.5)
            )
    }
}

/// An app's icon at a given size.
struct AppIconView: View {
    let bundleID: String
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: AppInfo.icon(bundleID: bundleID))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// The running app's own icon.
struct OwnAppIcon: View {
    var size: CGFloat = 48

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

extension ActionKind {
    /// SF Symbol shown next to the action in the HUD and in lists.
    var symbol: String {
        switch self {
        case .none: return "circle.slash"
        case .tileLeft: return "rectangle.lefthalf.filled"
        case .tileRight: return "rectangle.righthalf.filled"
        case .tileTop: return "rectangle.tophalf.filled"
        case .tileBottom: return "rectangle.bottomhalf.filled"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .center: return "rectangle.center.inset.filled"
        case .moveToNextDisplay: return "display.2"
        case .toggleFullScreen: return "arrow.up.backward.and.arrow.down.forward.rectangle"
        case .minimize: return "arrow.down.right.and.arrow.up.left"
        case .closeWindow: return "xmark.rectangle"
        case .hideApp: return "eye.slash"
        case .quitApp: return "power"
        case .openApplication: return "app.badge"
        case .navigateBack: return "chevron.backward"
        case .navigateForward: return "chevron.forward"
        case .openURL: return "safari"
        case .missionControl: return "rectangle.3.group"
        case .showDesktop: return "menubar.dock.rectangle"
        case .lockScreen: return "lock"
        case .sleepDisplay: return "moon"
        case .playPause: return "playpause.fill"
        case .nextTrack: return "forward.fill"
        case .previousTrack: return "backward.fill"
        case .volumeUp: return "speaker.wave.3.fill"
        case .volumeDown: return "speaker.wave.1.fill"
        case .mute: return "speaker.slash.fill"
        case .keyboardShortcut: return "command"
        case .shellCommand: return "terminal"
        case .appleScript: return "applescript"
        }
    }
}

extension View {
    /// Secondary caption text style used under controls.
    func captionStyle() -> some View {
        font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    /// Section footer text: wraps and stays leading-aligned, like System Settings.
    func footerStyle() -> some View {
        captionStyle()
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
