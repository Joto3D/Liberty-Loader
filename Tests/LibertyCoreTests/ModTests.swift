import XCTest
@testable import LibertyCore

final class ModTests: TempDirTestCase {
    let hashA = "9ba626afa44a3aa3"
    let hashB = "2e24ba9dd702da5c"

    func testParsePatchFileNames() {
        XCTAssertEqual(PatchSet.parse(fileName: "9ba626afa44a3aa3.patch_0")?.index, 0)
        XCTAssertEqual(PatchSet.parse(fileName: "9BA626AFA44A3AA3.patch_12.gpu_resources")?.suffix, ".gpu_resources")
        XCTAssertEqual(PatchSet.parse(fileName: "9BA626AFA44A3AA3.patch_12.gpu_resources")?.hash, "9ba626afa44a3aa3")
        XCTAssertNil(PatchSet.parse(fileName: "9ba626afa44a3aa3"))
        XCTAssertNil(PatchSet.parse(fileName: "readme.txt"))
    }

    func testManifestV1WithOptions() throws {
        let json = """
        {"Version":1,"Guid":"abc","Name":"Cool Armor","Description":"desc","IconPath":"icon.png",
         "Options":[{"Name":"Red","Include":["red"],"SubOptions":[{"Name":"Matte","Include":["red/matte"]},{"Name":"Gloss","Include":["red/gloss"]}]},
                    {"Name":"Blue","Include":["blue"]}]}
        """
        let manifest = try ModManifest.parse(Data(json.utf8))
        XCTAssertEqual(manifest.name, "Cool Armor")
        XCTAssertEqual(manifest.options.map(\.name), ["Red", "Blue"])
        XCTAssertEqual(manifest.includedFolders(option: 0, subOption: 1), ["red", "red/gloss"])
        XCTAssertEqual(manifest.includedFolders(option: 1, subOption: 0), ["blue"])
        XCTAssertEqual(manifest.includedFolders(option: 9, subOption: nil), ["blue"])
    }

    func testCombinableOptionsStack() throws {
        // A weapon-skin pack: every option is its own folder, so there is no
        // reason to make the user pick one.
        let json = """
        {"Version":1,"Name":"Menacing Weapons","Options":[
            {"Name":"Rifle","Include":["Weapons/Rifle"]},
            {"Name":"Cannon","Include":["Weapons/Cannon"],"SubOptions":[{"Name":"Quiet","Include":["Weapons/Cannon/Quiet"]},{"Name":"Loud","Include":["Weapons/Cannon/Loud"]}]},
            {"Name":"Laser","Include":["Weapons/Laser"]}]}
        """
        let manifest = try ModManifest.parse(Data(json.utf8))
        XCTAssertTrue(manifest.optionsAreCombinable)
        XCTAssertEqual(manifest.includedFolders(options: [0, 2], subOptions: [:]),
                       ["Weapons/Rifle", "Weapons/Laser"])
        // Sub-options stay single: one style per chosen option, not both.
        XCTAssertEqual(manifest.includedFolders(options: [0, 1], subOptions: [1: 1]),
                       ["Weapons/Rifle", "Weapons/Cannon", "Weapons/Cannon/Loud"])
        XCTAssertEqual(manifest.includedFolders(options: [1], subOptions: [:]),
                       ["Weapons/Cannon", "Weapons/Cannon/Quiet"])
        // Indices that no longer exist are dropped, not clamped.
        XCTAssertEqual(manifest.includedFolders(options: [2, 9], subOptions: [:]), ["Weapons/Laser"])
        // Nothing chosen resolves like the old single-selection default.
        XCTAssertEqual(manifest.includedFolders(options: [], subOptions: [:]), ["Weapons/Rifle"])
    }

    func testOverlappingOptionsStaySingleSelection() throws {
        // Both options write the same folder, so stacking them would only mean
        // one of them winning. Such a mod keeps a radio group.
        let json = """
        {"Version":1,"Name":"Armor","Options":[
            {"Name":"Red","Include":["armor","red"]},
            {"Name":"Blue","Include":["armor","blue"]}]}
        """
        let manifest = try ModManifest.parse(Data(json.utf8))
        XCTAssertFalse(manifest.optionsAreCombinable)
        // Still resolvable if asked, and a shared folder is deployed once.
        XCTAssertEqual(manifest.includedFolders(options: [0, 1], subOptions: [:]), ["armor", "red", "blue"])
    }

    func testSingleOptionIsNotCombinable() throws {
        let manifest = try ModManifest.parse(Data(#"{"Version":1,"Name":"One","Options":[{"Name":"Only","Include":["only"]}]}"#.utf8))
        XCTAssertFalse(manifest.optionsAreCombinable)
    }

    func testChosenSelectionFallsBackToLegacyFields() throws {
        // A mod installed before options could be combined has only the old
        // fields in mods.json; it must still resolve to what the user picked.
        var mod = InstalledMod(id: UUID(), name: "Old", enabled: true,
                               selectedOption: 1, selectedSubOption: 2,
                               installedAt: Date(), folderName: "old")
        XCTAssertEqual(mod.chosenOptions, [1])
        XCTAssertEqual(mod.chosenSubOptions, [1: 2])

        mod.choose(options: [0, 3], subOptions: [3: 1])
        XCTAssertEqual(mod.chosenOptions, [0, 3])
        XCTAssertEqual(mod.chosenSubOptions, [3: 1])
        // The legacy fields keep a sensible single answer for older builds.
        XCTAssertEqual(mod.selectedOption, 0)
        XCTAssertNil(mod.selectedSubOption)
    }

    func testDeploysEveryChosenOption() throws {
        let store = try ModStore(rootURL: tmp.appendingPathComponent("store"))
        let source = tmp.appendingPathComponent("download")
        try write("manifest.json", #"{"Version":1,"Name":"Pack","Options":[{"Name":"A","Include":["a"]},{"Name":"B","Include":["b"]},{"Name":"C","Include":["c"]}]}"#, in: source)
        try write("a/\(hashA).patch_0", "a", in: source)
        try write("b/\(hashB).patch_0", "b", in: source)
        try write("c/\(hashA).patch_1", "c", in: source)

        var mod = try store.install(from: source)
        XCTAssertEqual(store.resolve(mod).patchSets.count, 1)   // defaults to the first option

        mod.choose(options: [0, 1, 2], subOptions: [:])
        try store.update(mod)
        XCTAssertEqual(store.resolve(mod).patchSets.count, 3)
    }

    func testLegacyManifest() throws {
        let manifest = try ModManifest.parse(Data(#"{"Guid":"x","Name":"Old","Options":["A","B"]}"#.utf8))
        XCTAssertNil(manifest.version)
        XCTAssertEqual(manifest.includedFolders(option: 1, subOption: nil), ["B"])
    }

    func testInstallFolderUnwrapsAndUsesManifest() throws {
        let source = tmp.appendingPathComponent("download/Wrapper")
        try write("Inner/manifest.json", #"{"Version":1,"Name":"Fancy","Options":[{"Name":"One","Include":["one"]},{"Name":"Two","Include":["two"]}]}"#, in: source)
        try write("Inner/one/\(hashA).patch_0", "one", in: source)
        try write("Inner/two/\(hashA).patch_0", "two", in: source)

        let store = try ModStore(rootURL: tmp.appendingPathComponent("store"))
        let mod = try store.install(from: source)
        XCTAssertEqual(mod.name, "Fancy")
        XCTAssertEqual(mod.selectedOption, 0)

        var resolved = store.resolve(mod)
        XCTAssertEqual(resolved.patchSets.count, 1)
        XCTAssertEqual(try read(resolved.patchSets[0].files[""]!), "one")

        var changed = mod
        changed.selectedOption = 1
        try store.update(changed)
        resolved = store.resolve(changed)
        XCTAssertEqual(try read(resolved.patchSets[0].files[""]!), "two")

        // Persisted across instances.
        let reopened = try ModStore(rootURL: tmp.appendingPathComponent("store"))
        XCTAssertEqual(reopened.mods.first?.selectedOption, 1)
    }

    func testInstallRejectsFolderWithoutPatches() throws {
        try write("nothing/readme.txt")
        let store = try ModStore(rootURL: tmp.appendingPathComponent("store"))
        XCTAssertThrowsError(try store.install(from: tmp.appendingPathComponent("nothing"))) {
            XCTAssertEqual($0 as? LibertyError, .noPatchFiles)
        }
        XCTAssertTrue(store.mods.isEmpty)
    }

    func testMoveMatchesOnMoveSemantics() throws {
        let store = try ModStore(rootURL: tmp.appendingPathComponent("store"))
        for name in ["A", "B", "C"] {
            try write("\(name)/\(hashA).patch_0")
            try store.install(from: tmp.appendingPathComponent(name))
        }
        try store.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(store.mods.map(\.name), ["B", "C", "A"])
        try store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(store.mods.map(\.name), ["A", "B", "C"])
    }

    func testDeployRenumbersAndKeepsSiblingsTogether() throws {
        let data = tmp.appendingPathComponent("data")
        try write("\(hashA).patch_0", "foreign", in: data)   // installed by something else
        try write("\(hashA)", "game archive", in: data)

        try write("m1/\(hashA).patch_0", "m1-main")
        try write("m1/\(hashA).patch_0.gpu_resources", "m1-gpu")
        try write("m1/\(hashA).patch_0.stream", "m1-stream")
        try write("m2/\(hashA).patch_0", "m2-main")
        try write("m2/\(hashB).patch_3", "m2-b")

        let mods = [
            ResolvedMod(id: UUID(), name: "M1", patchSets: PatchSet.collect(in: [tmp.appendingPathComponent("m1")])),
            ResolvedMod(id: UUID(), name: "M2", patchSets: PatchSet.collect(in: [tmp.appendingPathComponent("m2")])),
        ]
        let deployer = PatchDeployer(dataDir: data, stateDirectory: tmp.appendingPathComponent("state"))
        let plan = try deployer.sync(mods)

        XCTAssertEqual(try read(data.appendingPathComponent("\(hashA).patch_0")), "foreign")
        XCTAssertEqual(try read(data.appendingPathComponent("\(hashA).patch_1")), "m1-main")
        XCTAssertEqual(try read(data.appendingPathComponent("\(hashA).patch_1.gpu_resources")), "m1-gpu")
        XCTAssertEqual(try read(data.appendingPathComponent("\(hashA).patch_1.stream")), "m1-stream")
        XCTAssertEqual(try read(data.appendingPathComponent("\(hashA).patch_2")), "m2-main")
        XCTAssertEqual(try read(data.appendingPathComponent("\(hashB).patch_0")), "m2-b")
        XCTAssertEqual(plan.conflicts[hashA], ["M1", "M2"])
        XCTAssertNil(plan.conflicts[hashB])

        // Re-sync with only M2: M1's files go away, M2 is renumbered, foreign files stay.
        try deployer.sync([mods[1]])
        XCTAssertEqual(files(in: data), [hashA, "\(hashA).patch_0", "\(hashA).patch_1", "\(hashB).patch_0"].sorted())
        XCTAssertEqual(try read(data.appendingPathComponent("\(hashA).patch_1")), "m2-main")

        try deployer.purge()
        XCTAssertEqual(files(in: data), [hashA, "\(hashA).patch_0"])
    }

    func testPathGuard() {
        let guardrail = PathGuard(allowedRoots: [URL(fileURLWithPath: "/bottle/data")])
        XCTAssertTrue(guardrail.isAllowed(URL(fileURLWithPath: "/bottle/data/x.patch_0")))
        XCTAssertFalse(guardrail.isAllowed(URL(fileURLWithPath: "/bottle/data/../../etc/passwd")))
        XCTAssertFalse(guardrail.isAllowed(URL(fileURLWithPath: "/bottle/database")))
    }
}
