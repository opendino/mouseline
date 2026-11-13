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

    @Test func badNestedValuesDropOnlyThemselves() throws {
        let json = #"""
        {
          "toggleShortcut": {"keyCode": 40, "modifiers": 1048576},
          "trailColor": {"red": 0, "green": 0, "blue": 1},
          "excludedApps": [{"bundleID": "org.blenderfoundation.blender"}, {"name": "No bundle id"}],
          "customGestures": [
            {"id": "custom.a", "points": [{"x": 0, "y": 0}, {"x": 1, "y": 1}]},
            {"id": "custom.b", "name": "No points"}
          ],
          "personalSamples": [{"gestureID": "Up", "points": []}, {"gestureID": 5}],
          "bindings": {"Up": {"kind": "keyboardShortcut", "shortcut": {"keyCode": "K"}}, "Down": {"kind": "minimize"}}
        }
        """#
        let decoded = try AppConfig.decode(Data(json.utf8))
        #expect(decoded.toggleShortcut == KeyCombo(keyCode: 40, modifiers: 1_048_576, display: ""))
        #expect(decoded.trailColor == RGBAColor(red: 0, green: 0, blue: 1, alpha: 1))
        #expect(decoded.excludedApps == [ExcludedApp(bundleID: "org.blenderfoundation.blender", name: "org.blenderfoundation.blender")])
        #expect(decoded.customGestures.map(\.id) == ["custom.a"])
        #expect(decoded.customGestures.first?.name == "")
        #expect(decoded.personalSamples.map(\.gestureID) == ["Up"])
        #expect(decoded.action(for: "Up").kind == .keyboardShortcut)
        #expect(decoded.action(for: "Up").shortcut == nil)
        #expect(decoded.action(for: "Down").kind == .minimize)
    }

    @Test func wrongTypesFallBackToDefaults() throws {
        let json = #"{"toggleShortcut": "cmd-k", "trailColor": 3, "excludedApps": 7, "customGestures": {}, "enabled": false}"#
        let decoded = try AppConfig.decode(Data(json.utf8))
        #expect(decoded.toggleShortcut == nil)
        #expect(decoded.trailColor == .orange)
        #expect(decoded.excludedApps.isEmpty)
        #expect(decoded.customGestures.isEmpty)
        #expect(decoded.enabled == false)
    }

    @Test func numericSettingsAreClampedOnDecode() throws {
        let json = #"{"clickMaxPath": 0, "matchMaxDistance": 500, "holdDelay": -1, "trailWidth": 100}"#
        let decoded = try AppConfig.decode(Data(json.utf8))
        #expect(decoded.clickMaxPath == AppConfig.clickMaxPathRange.lowerBound)
        #expect(decoded.matchMaxDistance == AppConfig.matchMaxDistanceRange.upperBound)
        #expect(decoded.holdDelay == AppConfig.holdDelayRange.lowerBound)
        #expect(decoded.trailWidth == AppConfig.trailWidthRange.upperBound)

        // The defaults themselves are valid.
        let d = AppConfig()
        #expect(AppConfig.clickMaxPathRange.contains(d.clickMaxPath))
        #expect(AppConfig.matchMaxDistanceRange.contains(d.matchMaxDistance))
        #expect(AppConfig.holdDelayRange.contains(d.holdDelay))
        #expect(AppConfig.trailWidthRange.contains(d.trailWidth))
    }

    @Test func invalidCustomGestureIDsAreRepaired() throws {
        let points = #"[{"x": 0, "y": 0}, {"x": 100, "y": 0}, {"x": 0, "y": 100}]"#
        let json = """
        {
          "customGestures": [
            {"id": "zig", "name": "Zig", "points": \(points)},
            {"id": "custom.z", "name": "Z1", "points": \(points)},
            {"id": "custom.z", "name": "Z2", "points": \(points)},
            {"id": "Left", "name": "Fake left", "points": \(points)}
          ],
          "bindings": {"zig": {"kind": "playPause"}, "Left": {"kind": "tileLeft"}, "custom.z": {"kind": "maximize"}},
          "appBindings": {"com.apple.Safari": {"name": "Safari", "bindings": {"zig": {"kind": "missionControl"}}}},
          "personalSamples": [{"gestureID": "zig", "points": \(points)}, {"gestureID": "Left", "points": \(points)}]
        }
        """
        let decoded = try AppConfig.decode(Data(json.utf8))
        let ids = decoded.customGestures.map(\.id)
        #expect(ids.allSatisfy(CustomGesture.isCustomID))
        #expect(Set(ids).count == ids.count)
        #expect(decoded.customGestures.map(\.name) == ["Zig", "Z1", "Z2", "Fake left"])

        // The unprefixed gesture takes its binding, override and samples along.
        let zig = ids[0]
        #expect(decoded.bindings["zig"] == nil)
        #expect(decoded.action(for: zig).kind == .playPause)
        #expect(decoded.action(for: zig, in: "com.apple.Safari").kind == .missionControl)
        #expect(decoded.appBindings["com.apple.Safari"]?.bindings["zig"] == nil)
        #expect(decoded.personalSamples.map(\.gestureID) == [zig, "Left"])
        #expect(decoded.boundGestureIDs.contains(zig))

        // A duplicate leaves the id and binding to the first gesture.
        #expect(ids[1] == "custom.z")
        #expect(ids[2] != "custom.z")
        #expect(decoded.action(for: "custom.z").kind == .maximize)
        #expect(decoded.bindings[ids[2]] == nil)

        // A key that names a built-in shape stays with the built-in.
        #expect(decoded.action(for: "Left").kind == .tileLeft)
        #expect(decoded.bindings[ids[3]] == nil)

        // Repaired ids are stable once saved.
        #expect(try AppConfig.decode(decoded.encoded()) == decoded)
    }

    @Test func argumentSplitting() {
        #expect(splitArguments("") == [])
        #expect(splitArguments("  a  b ") == ["a", "b"])
        #expect(splitArguments(#"--workspace="/Users/me/My Notes" -n"#) == ["--workspace=/Users/me/My Notes", "-n"])
        #expect(splitArguments(#"'single quoted' plain\ space"#) == ["single quoted", "plain space"])
        #expect(splitArguments(#"empty "" arg"#) == ["empty", "", "arg"])
    }
}
