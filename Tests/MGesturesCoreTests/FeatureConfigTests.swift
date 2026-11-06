import Foundation
import Testing
@testable import MGesturesCore

struct FeatureConfigTests {
    let finder = "com.apple.finder"
    let safari = "com.apple.Safari"

    @Test func perAppOverridesWin() {
        var config = AppConfig()
        config.appBindings[finder] = AppBindings(name: "Finder", bindings: [
            "Left": ActionConfig(kind: .navigateBack),
            "Down": ActionConfig(kind: .none),
            "Gamma": ActionConfig(kind: .closeWindow),
        ])
        #expect(config.action(for: "Left", in: finder).kind == .navigateBack)
        #expect(config.action(for: "Left", in: safari).kind == .tileLeft)
        #expect(config.action(for: "Left", in: nil).kind == .tileLeft)
        #expect(config.action(for: "Up", in: finder).kind == .maximize) // not overridden → global
        #expect(config.hasOverride(for: "Down", in: finder))
        #expect(!config.hasOverride(for: "Up", in: finder))

        #expect(config.boundGestureIDs(in: finder) == ["Left", "Right", "Up", "Gamma"])
        #expect(config.boundGestureIDs(in: safari) == ["Left", "Right", "Up", "Down"])
        #expect(config.needsTargetApp)
        #expect(!AppConfig().needsTargetApp)
    }

    @Test func customGesturesBecomeTemplates() {
        var config = AppConfig()
        let zigzag = (0..<5).map { StrokePoint(Double($0) * 40, $0.isMultiple(of: 2) ? 0 : 80) }
        let gesture = CustomGesture(name: "Zig", stroke: zigzag)
        config.customGestures = [gesture]
        config.bindings[gesture.id] = ActionConfig(kind: .playPause)

        #expect(CustomGesture.isCustomID(gesture.id))
        #expect(gesture.points.count == Recognizer.resampleCount)
        #expect(config.allTemplates.count == GestureTemplate.builtIn.count + 1)
        #expect(config.displayName(for: gesture.id) == "Zig")
        #expect(config.displayName(for: "Left") == "Left")
        #expect(config.boundGestureIDs.contains(gesture.id))

        // The recognizer finds the custom shape when drawn again at another size and place.
        let recognizer = Recognizer(templates: config.allTemplates)
        let redrawn = zigzag.map { StrokePoint($0.x * 2 + 300, $0.y * 2 + 50) }
        guard case .gesture(let id, _) = recognizer.recognize(redrawn) else {
            Issue.record("custom gesture not recognized"); return
        }
        #expect(id == gesture.id)
    }

    @Test func removingCustomGestureRemovesItsBindings() {
        var config = AppConfig()
        let g = CustomGesture(name: "Z", points: Recognizer.prepare([StrokePoint(0, 0), StrokePoint(100, 0), StrokePoint(0, 100), StrokePoint(100, 100)]))
        config.customGestures = [g]
        config.bindings[g.id] = ActionConfig(kind: .mute)
        config.appBindings[finder] = AppBindings(name: "Finder", bindings: [g.id: ActionConfig(kind: .quitApp)])
        config.removeCustomGesture(id: g.id)
        #expect(config.customGestures.isEmpty)
        #expect(config.bindings[g.id] == nil)
        #expect(config.appBindings[finder]?.bindings[g.id] == nil)
    }

    @Test func bindingsToMissingGesturesAreIgnored() {
        var config = AppConfig()
        config.bindings["custom.deleted"] = ActionConfig(kind: .mute)
        config.bindings["No Such Shape"] = ActionConfig(kind: .mute)
        #expect(!config.boundGestureIDs.contains("custom.deleted"))
        #expect(!config.boundGestureIDs.contains("No Such Shape"))
    }

    @Test func requiredModifier() {
        #expect(RequiredModifier.none.isSatisfied(by: 0))
        #expect(!RequiredModifier.option.isSatisfied(by: 0))
        #expect(RequiredModifier.option.isSatisfied(by: KeyCombo.optionMask | KeyCombo.shiftMask))
        #expect(!RequiredModifier.command.isSatisfied(by: KeyCombo.optionMask))
        #expect(TriggerButton.right.buttonNumber == 1)
        #expect(TriggerButton.middle.buttonNumber == 2)
    }

    @Test func everyActionHasACategoryAndTitle() {
        for kind in ActionKind.allCases {
            #expect(!kind.title.isEmpty)
            #expect(ActionKind.kinds(in: kind.category).contains(kind))
        }
        let total = ActionCategory.allCases.map { ActionKind.kinds(in: $0).count }.reduce(0, +)
        #expect(total == ActionKind.allCases.count)
    }

    @Test func newFieldsRoundTripAndDefault() throws {
        var config = AppConfig()
        config.triggerButton = .middle
        config.requiredModifier = .option
        config.toggleShortcut = KeyCombo(keyCode: 5, modifiers: KeyCombo.commandMask | KeyCombo.optionMask, display: "⌥⌘G")
        config.feedbackSound = "Pop"
        config.hapticFeedback = true
        config.customGestures = [CustomGesture(name: "Hook", points: Recognizer.prepare([StrokePoint(0, 0), StrokePoint(0, 100), StrokePoint(50, 80)]))]
        config.appBindings[safari] = AppBindings(name: "Safari", bindings: ["Up": ActionConfig(kind: .appleScript, script: "beep")])
        #expect(try AppConfig.decode(config.encoded()) == config)

        let old = try AppConfig.decode(Data(#"{"version": 1, "triggerButton": "laser", "requiredModifier": "hyper"}"#.utf8))
        #expect(old.triggerButton == .right)
        #expect(old.requiredModifier == .none)
        #expect(old.customGestures.isEmpty)
        #expect(old.appBindings.isEmpty)
        #expect(old.feedbackSound == "")
        #expect(old.toggleShortcut == nil)
    }

    @Test func trackerUsesNewTemplates() {
        var tracker = GestureTracker()
        let hook = [StrokePoint(0, 0), StrokePoint(0, 200), StrokePoint(60, 140)]
        let g = CustomGesture(name: "Hook", stroke: hook)
        tracker.setTemplates(GestureTemplate.builtIn + [g.template])
        let settings = TrackerSettings(boundGestures: [g.id])
        _ = tracker.rightMouseDown(at: hook[0], settings: settings, active: true)
        for p in Recognizer.resample(hook, count: 30).dropFirst() { _ = tracker.rightMouseDragged(to: p) }
        let out = tracker.rightMouseUp(at: hook[2])
        #expect(out.effects.contains { if case .runGesture(id: g.id, _) = $0 { return true }; return false })
    }
}
