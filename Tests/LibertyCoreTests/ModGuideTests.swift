import XCTest
@testable import LibertyCore

final class ModGuideTests: TempDirTestCase {
    func testBBCodeToPlainText() {
        let bbcode = """
        [center][size=5][b]Immersive First Person View[/b][/size][/center]<br />[img]https://x/banner.png[/img]<br />\
        A [i]fully[/i] redone camera. See [url=https://example.com/faq]the FAQ[/url] &amp; enjoy.<br /><br /><br /><br />\
        [list][*]Works with all armors[*]No HUD changes[/list]
        """
        let text = NexusText.plainText(fromBBCode: bbcode)
        XCTAssertTrue(text.hasPrefix("Immersive First Person View"))
        XCTAssertFalse(text.contains("[") || text.contains("banner.png") || text.contains("<br"))
        XCTAssertTrue(text.contains("A fully redone camera. See the FAQ (https://example.com/faq) & enjoy."))
        XCTAssertTrue(text.contains("• Works with all armors\n• No HUD changes"))
        XCTAssertFalse(text.contains("\n\n\n"))
    }

    func testInstructionHighlights() {
        let description = """
        Immersive First Person View - Fully Redux
        Play the whole game from your Helldiver's eyes.

        How to use:
        Aim down sights and switch to first person once.
        The camera then stays in first person for the mission.

        Changelog
        v12 fixed the jetpack. You can press V to toggle the helmet visor overlay.
        """
        let highlights = ModGuide.instructionHighlights(in: description)
        XCTAssertEqual(highlights.first, "Aim down sights and switch to first person once.")
        XCTAssertTrue(highlights.contains("The camera then stays in first person for the mission."))
        XCTAssertTrue(highlights.contains("You can press V to toggle the helmet visor overlay."))
        XCTAssertFalse(highlights.contains { $0.contains("Changelog") })
    }

    func testNoFalseHighlights() {
        XCTAssertEqual(ModGuide.instructionHighlights(in: "Replaces the extraction music with Doom Eternal's The Only Thing They Fear Is You."), [])
        XCTAssertEqual(ModGuide.instructionHighlights(in: ""), [])
    }

    func testReadmeDiscoveryAndOldIndex() throws {
        let store = try ModStore(rootURL: tmp.appendingPathComponent("store"))
        try write("src/FPV/9ba626afa44a3aa3.patch_0")
        try write("src/FPV/docs/README.txt", "Press F to look around.")
        let mod = try store.install(from: tmp.appendingPathComponent("src/FPV"))
        XCTAssertEqual(store.readmeText(for: mod), "Press F to look around.")
        XCTAssertNil(mod.nexusDescription)

        try write("src/Plain/9ba626afa44a3aa3.patch_0")
        let plain = try store.install(from: tmp.appendingPathComponent("src/Plain"))
        XCTAssertNil(store.readmeText(for: plain))
    }
}
