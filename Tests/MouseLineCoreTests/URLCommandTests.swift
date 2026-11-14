import Foundation
import Testing
@testable import MouseLineCore

struct URLCommandTests {
    func command(_ string: String) -> URLCommand? {
        URL(string: string).flatMap(URLCommand.init(url:))
    }

    @Test func parsesEveryCommand() {
        #expect(command("mouseline://enable") == .setEnabled(true))
        #expect(command("mouseline://off") == .setEnabled(false))
        #expect(command("mouseline://toggle") == .setEnabled(nil))
        #expect(command("MouseLine://Toggle") == .setEnabled(nil))
        #expect(command("mouseline:toggle") == .setEnabled(nil))
        #expect(command("mouseline://toggle-app") == .toggleFrontmostApp)
        #expect(command("mouseline://settings") == .openSettings(pane: nil))
        #expect(command("mouseline://settings/calibration") == .openSettings(pane: "calibration"))
        #expect(command("mouseline://welcome") == .openWelcome)
    }

    @Test func rejectsUnknownInput() {
        #expect(command("mouseline://run-script") == nil)
        #expect(command("mouseline://") == nil)
        #expect(command("https://toggle") == nil)
        // An unknown pane still opens Settings, on the default pane.
        #expect(command("mouseline://settings/../../etc") == .openSettings(pane: nil))
    }
}
