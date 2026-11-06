import Foundation
import Testing
@testable import MGesturesCore

struct ConfigTests {
    @Test func roundTrip() throws {
        var config = AppConfig()
        config.bindings["Diagonal ↗"] = ActionConfig(
            kind: .openApplication, appPath: "/Applications/Notes.app",
            appArguments: "--flag \"two words\"", newInstance: true
        )
        config.bindings["C Shape"] = ActionConfig(
            kind: .keyboardShortcut, shortcut: KeyCombo(keyCode: 40, modifiers: 0x10_0000, display: "⌘K")
        )
        let decoded = try AppConfig.decode(config.encoded())
        #expect(decoded == config)
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let decoded = try AppConfig.decode(Data(#"{"enabled": false}"#.utf8))
        #expect(decoded.enabled == false)
        #expect(decoded.showTrail == true)
        #expect(decoded.clickMaxPath == 70)
        #expect(decoded.bindings == AppConfig.defaultBindings)
    }

    @Test func unknownActionKindBecomesNone() throws {
        let json = #"{"bindings": {"Up": {"kind": "teleport"}, "Down": {"kind": "minimize"}}}"#
        let decoded = try AppConfig.decode(Data(json.utf8))
        #expect(decoded.action(for: "Up").kind == .none)
        #expect(decoded.action(for: "Down").kind == .minimize)
        #expect(decoded.action(for: "Gamma").kind == .none)
    }

    @Test func boundGesturesSkipNoneActions() {
        var config = AppConfig(bindings: ["Up": ActionConfig(kind: .maximize), "Down": ActionConfig(kind: .none)])
        #expect(config.boundGestureIDs == ["Up"])
        config.excludedApps = [ExcludedApp(bundleID: "org.blenderfoundation.blender", name: "Blender")]
        #expect(config.isExcluded(bundleID: "org.blenderfoundation.blender"))
        #expect(!config.isExcluded(bundleID: "com.apple.finder"))
        #expect(!config.isExcluded(bundleID: nil))
    }

    @Test func olderConfigFilesGetNewDefaults() throws {
        // A file written by v0.1.0, before hold-to-menu and exclusions existed.
        let decoded = try AppConfig.decode(Data(#"{"version": 1, "enabled": true, "bindings": {}}"#.utf8))
        #expect(decoded.holdToOpenMenu == true)
        #expect(decoded.holdDelay == 0.5)
        #expect(decoded.excludedApps == [])
        #expect(decoded.onboardingCompleted == false)
    }

    @Test func defaultBindingsReferToRealTemplates() {
        for id in AppConfig.defaultBindings.keys {
            #expect(GestureTemplate.builtIn(id: id) != nil, "\(id)")
        }
    }

    @Test func argumentSplitting() {
        #expect(splitArguments("") == [])
        #expect(splitArguments("  a  b ") == ["a", "b"])
        #expect(splitArguments(#"--workspace="/Users/me/My Notes" -n"#) == ["--workspace=/Users/me/My Notes", "-n"])
        #expect(splitArguments(#"'single quoted' plain\ space"#) == ["single quoted", "plain space"])
        #expect(splitArguments(#"empty "" arg"#) == ["empty", "", "arg"])
    }
}
