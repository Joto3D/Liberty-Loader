import XCTest
@testable import LibertyCore

final class DiagnosticsTests: TempDirTestCase {
    let hashA = "9ba626afa44a3aa3"
    let hashB = "2e24ba9dd702da5c"
    let hashGone = "aaaaaaaaaaaaaaaa"

    var data: URL { tmp.appendingPathComponent("data") }

    func makeStore() throws -> (ModStore, PatchDeployer) {
        try write(hashA, "archive", in: data)
        try write(hashB, "archive", in: data)
        let store = try ModStore(rootURL: tmp.appendingPathComponent("store"))
        let deployer = PatchDeployer(dataDir: data, stateDirectory: tmp.appendingPathComponent("state"))
        return (store, deployer)
    }

    @discardableResult
    func install(_ name: String, files: [String], into store: ModStore) throws -> InstalledMod {
        for file in files { try write("src/\(name)/\(file)") }
        return try store.install(from: tmp.appendingPathComponent("src/\(name)"))
    }

    func testNotDeployedThenOK() throws {
        let (store, deployer) = try makeStore()
        let mod = try install("Armor", files: ["\(hashA).patch_0"], into: store)

        var report = ModDiagnostics.run(store: store, deployer: deployer, buildChanged: false, gameRunning: false)
        XCTAssertEqual(report.global, [.nothingDeployed])
        XCTAssertEqual(report.mods.first { $0.modID == mod.id }?.problems, [.notDeployed(missing: ["\(hashA).patch_0"])])
        XCTAssertTrue(report.hasBlockingProblems)

        try deployer.sync(store.resolvedEnabledMods())
        report = ModDiagnostics.run(store: store, deployer: deployer, buildChanged: false, gameRunning: false)
        XCTAssertEqual(report.global, [])
        XCTAssertTrue(report.mods.allSatisfy(\.isOK))
        XCTAssertFalse(report.hasBlockingProblems)

        // Steam "verify files" removed our patch.
        try FileManager.default.removeItem(at: data.appendingPathComponent("\(hashA).patch_0"))
        report = ModDiagnostics.run(store: store, deployer: deployer, buildChanged: true, gameRunning: true)
        XCTAssertEqual(report.global, [.gameRunning, .gameUpdatedSinceDeploy])
        XCTAssertEqual(report.mods.first?.problems, [.notDeployed(missing: ["\(hashA).patch_0"])])
    }

    func testOutdatedModTargetsMissingArchive() throws {
        let (store, deployer) = try makeStore()
        try install("Old", files: ["\(hashGone).patch_0"], into: store)
        try deployer.sync(store.resolvedEnabledMods())
        let report = ModDiagnostics.run(store: store, deployer: deployer, buildChanged: false, gameRunning: false)
        XCTAssertEqual(report.mods.first?.problems, [.targetsMissingGameFile(hashes: [hashGone])])
        XCTAssertTrue(report.hasBlockingProblems)
    }

    func testEmptyVariant() throws {
        let (store, deployer) = try makeStore()
        try write("src/Variants/manifest.json", #"{"Version":1,"Name":"Variants","Options":[{"Name":"A","Include":["a"]},{"Name":"Broken","Include":["missing"]}]}"#)
        try write("src/Variants/a/\(hashA).patch_0")
        var mod = try store.install(from: tmp.appendingPathComponent("src/Variants"))
        mod.selectedOption = 1
        try store.update(mod)
        let report = ModDiagnostics.run(store: store, deployer: deployer, buildChanged: false, gameRunning: false)
        XCTAssertEqual(report.mods.first?.problems, [.noPatchFiles])
    }

    func testOverriddenAndDisabledAndForeign() throws {
        let (store, deployer) = try makeStore()
        let first = try install("First", files: ["\(hashA).patch_0", "\(hashB).patch_0"], into: store)
        let second = try install("Second", files: ["\(hashA).patch_0"], into: store)
        var off = try install("Off", files: ["\(hashB).patch_0"], into: store)
        off.enabled = false
        try store.update(off)
        try write("\(hashB).patch_0", "manual", in: data) // installed by hand, before syncing
        try deployer.sync(store.resolvedEnabledMods())

        let report = ModDiagnostics.run(store: store, deployer: deployer, buildChanged: false, gameRunning: false)
        XCTAssertEqual(report.mods.first { $0.modID == first.id }?.problems, [.overriddenBy(["Second"])])
        XCTAssertEqual(report.mods.first { $0.modID == second.id }?.problems, [])
        XCTAssertEqual(report.mods.first { $0.modID == off.id }?.problems, [.disabled])
        XCTAssertEqual(report.global, [.foreignPatchFiles(count: 1)])
        XCTAssertFalse(report.hasBlockingProblems)
    }

    func testParseRequirements() {
        let json = """
        {"data":{"legacyModsByDomain":{"nodes":[{"modId":5,"modRequirements":{"nexusRequirements":{"nodes":[
          {"modId":"42","modName":"Base Armor Framework","url":"https://www.nexusmods.com/helldivers2/mods/42","notes":"Required","externalRequirement":false},
          {"modId":null,"modName":"Some Tool","url":"https://example.com/tool","externalRequirement":true},
          {"modName":""}
        ]}}}]}}}
        """
        let requirements = NexusClient.parseRequirements(Data(json.utf8))
        XCTAssertEqual(requirements?.map(\.name), ["Base Armor Framework", "Some Tool"])
        XCTAssertEqual(requirements?.first?.modID, 42)
        XCTAssertEqual(requirements?.last?.isExternal, true)
        XCTAssertEqual(NexusClient.parseRequirements(Data(#"{"data":{"legacyModsByDomain":{"nodes":[]}}}"#.utf8)), [])
        XCTAssertNil(NexusClient.parseRequirements(Data(#"{"errors":[{"message":"nope"}]}"#.utf8)))
    }

    func testMissingRequirements() throws {
        let (store, _) = try makeStore()
        var needy = try install("Needy", files: ["\(hashA).patch_0"], into: store)
        var base = try install("Base", files: ["\(hashB).patch_0"], into: store)
        needy.requirements = [
            NexusRequirement(modID: 42, name: "Base", url: nil, isExternal: false, notes: nil),
            NexusRequirement(modID: 77, name: "Other", url: nil, isExternal: false, notes: nil),
            NexusRequirement(modID: nil, name: "Tool", url: "https://example.com", isExternal: true, notes: nil),
        ]
        try store.update(needy)
        base.nexusModID = 42
        try store.update(base)
        XCTAssertEqual(needy.missingRequirements(installed: store.mods).map(\.name), ["Other"])

        // Requirements survive a reload of mods.json.
        let reopened = try ModStore(rootURL: tmp.appendingPathComponent("store"))
        XCTAssertEqual(reopened.mods.first { $0.id == needy.id }?.requirements?.count, 3)
    }
}
