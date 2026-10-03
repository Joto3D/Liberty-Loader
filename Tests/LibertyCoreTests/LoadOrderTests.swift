import XCTest
@testable import LibertyCore

final class LoadOrderTests: TempDirTestCase {
    let bingus = "ARSENAL: place this loader LAST (bottom of the list) with default priority, or FIRST if first-mod priority is enabled. Required by Armory Preview Cache."

    func testDetectHints() {
        XCTAssertEqual(LoadOrderHint.detect(in: bingus), .bottom)
        XCTAssertEqual(LoadOrderHint.detect(in: "Make sure this mod must be loaded last."), .bottom)
        XCTAssertEqual(LoadOrderHint.detect(in: "Keep it at the bottom of your mod list"), .bottom)
        XCTAssertEqual(LoadOrderHint.detect(in: "Place this mod first so others can override it."), .top)
        XCTAssertNil(LoadOrderHint.detect(in: "Replaces the extraction music with Doom Eternal's track."))
        XCTAssertNil(LoadOrderHint.detect(in: "Download the loader first, then install this."))
        XCTAssertNil(LoadOrderHint.detect(in: ""))
    }

    private func install(_ name: String, description: String? = nil, into store: ModStore) throws -> InstalledMod {
        try write("src/\(name)/9ba626afa44a3aa3.patch_0")
        if let description {
            let json = try JSONSerialization.data(withJSONObject: ["Version": 1, "Name": name, "Description": description])
            try String(decoding: json, as: UTF8.self).write(to: tmp.appendingPathComponent("src/\(name)/manifest.json"), atomically: true, encoding: .utf8)
        }
        return try store.install(from: tmp.appendingPathComponent("src/\(name)"))
    }

    func testLoaderIsPinnedAndKeptAtBottom() throws {
        let store = try ModStore(rootURL: tmp.appendingPathComponent("store"))
        _ = try install("Immersive", into: store)
        let loader = try install("Bingus", description: bingus, into: store)
        _ = try install("Options", description: "Requires Bingus Shared Loader v18+.", into: store)
        _ = try install("Bindings", into: store)

        XCTAssertEqual(store.mods.first { $0.id == loader.id }?.loadOrderPin, .bottom)
        XCTAssertEqual(store.mods.map(\.name), ["Immersive", "Options", "Bindings", "Bingus"])
        XCTAssertEqual(store.takeRecentlyAutoPinned(), ["Bingus"])
        XCTAssertEqual(store.takeRecentlyAutoPinned(), [])

        // Dragging a normal mod below the loader snaps back above it.
        try store.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        XCTAssertEqual(store.mods.map(\.name), ["Options", "Bindings", "Immersive", "Bingus"])

        // Unpinning by hand lets it move freely and is never re-detected.
        try store.setPin(nil, for: loader.id)
        try store.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(store.mods.first?.name, "Bingus")
        try store.refreshPins()
        XCTAssertNil(store.mods.first?.loadOrderPin)

        // Manual top pin.
        let bindings = try XCTUnwrap(store.mods.first { $0.name == "Bindings" })
        try store.setPin(.top, for: bindings.id)
        XCTAssertEqual(store.mods.first?.name, "Bindings")
    }

    func testExistingModsGetPinnedOnLoadAndOldIndexDecodes() throws {
        let root = tmp.appendingPathComponent("store")
        let store = try ModStore(rootURL: root)
        let loader = try install("Bingus", into: store)
        _ = try install("Other", into: store)

        // Simulate a pre-pin mods.json: description arrives later (e.g. from Nexus), no pin fields.
        var withDescription = try XCTUnwrap(store.mods.first { $0.id == loader.id })
        withDescription.description = bingus
        withDescription.loadOrderPin = nil
        try store.update(withDescription)
        var json = try String(contentsOf: root.appendingPathComponent("mods.json"), encoding: .utf8)
        json = json.replacingOccurrences(of: #""loadOrderPin" : "bottom","#, with: "")
        try json.write(to: root.appendingPathComponent("mods.json"), atomically: true, encoding: .utf8)

        let reopened = try ModStore(rootURL: root)
        XCTAssertEqual(reopened.mods.map(\.name), ["Other", "Bingus"])
        XCTAssertEqual(reopened.mods.last?.loadOrderPin, .bottom)
    }
}
