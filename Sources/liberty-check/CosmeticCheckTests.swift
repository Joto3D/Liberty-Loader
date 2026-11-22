import Foundation
@testable import LibertyCore

/// What the cosmetic check can see. `.assetsOnly` is never a safety claim, so
/// none of these tests assert one.
final class CosmeticCheckTests: TempDirTestCase {

    private func inspect() -> CosmeticCheck.Report {
        CosmeticCheck().inspect(modDirectory: tmp)
    }

    func testSoundModIsAssetsOnly() throws {
        try write("9ba626afa44a3aa3.patch_0")
        try write("9ba626afa44a3aa3.patch_0.stream")
        try write("preview.png")
        let r = inspect()
        XCTAssertEqual(r.verdict, .assetsOnly)
        XCTAssertEqual(r.patchFileCount, 1)
        XCTAssertTrue(r.signals.isEmpty)
        XCTAssertEqual(r.unrecognisedFileCount, 0)
    }

    func testDllIsNativeCode() throws {
        try write("a.patch_0")
        try write("hook/Loader.DLL")
        let r = inspect()
        XCTAssertEqual(r.verdict, .runsCode)
        XCTAssertTrue(r.signals.contains { $0.kind == .nativeCode && $0.path == "hook/Loader.DLL" })
    }

    func testLuaIsScript() throws {
        try write("a.patch_0")
        try write("init.lua")
        let r = inspect()
        XCTAssertEqual(r.verdict, .runsCode)
        XCTAssertTrue(r.signals.contains { $0.kind == .script && $0.path == "init.lua" })
    }

    func testManifestRequiringHD2Runtime() throws {
        try write("a.patch_0")
        try write("manifest.json", #"{"name":"x","requires":{"hd2runtime":{"version":"0.31.3"}}}"#)
        let r = inspect()
        XCTAssertEqual(r.verdict, .runsCode)
        let s = r.signals.first { $0.kind == .runtimeDependency }
        XCTAssertEqual(s?.path, "manifest.json")
        XCTAssertTrue(s?.detail.contains("HD2Runtime") == true)
        XCTAssertTrue(s?.detail.contains("0.31.3") == true)
    }

    func testBingusFilenameIsRuntimeDependency() throws {
        try write("BingusSharedLoader-manifest.json", "not json at all")
        let r = inspect()
        XCTAssertEqual(r.verdict, .runsCode)
        XCTAssertEqual(r.signals.map(\.kind), [.runtimeDependency])
    }

    func testManifestWithoutRequiresIsNotASignal() throws {
        try write("a.patch_0")
        try write("manifest.json", #"{"name":"x","requires":{"somethingelse":"1"}}"#)
        XCTAssertEqual(inspect().verdict, .assetsOnly)
    }

    func testMalformedManifestDoesNotCrash() throws {
        try write("a.patch_0")
        try write("manifest.json", "{{{")
        XCTAssertEqual(inspect().verdict, .assetsOnly)
    }

    func testRuntimeFolderIsRuntimeDependency() throws {
        try write("runtime/payload.bin")
        let r = inspect()
        XCTAssertEqual(r.verdict, .runsCode)
        XCTAssertTrue(r.signals.contains { $0.kind == .runtimeDependency && $0.path == "runtime" })
    }

    func testExecutableShellScriptIsReportedOnce() throws {
        let url = try write("run.sh", "#!/bin/sh\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        let r = inspect()
        XCTAssertEqual(r.signals.count, 1)
        XCTAssertEqual(r.signals.first?.kind, .script)
    }

    func testExecutableBitOnPlainFile() throws {
        let url = try write("tool")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        let r = inspect()
        XCTAssertEqual(r.signals.map(\.kind), [.executableBit])
        XCTAssertEqual(r.verdict, .runsCode)
    }

    func testEmptyFolderIsInconclusive() throws {
        XCTAssertEqual(inspect().verdict, .inconclusive)
    }

    func testMissingFolderIsInconclusive() throws {
        let missing = tmp.appendingPathComponent("nope")
        let r = CosmeticCheck().inspect(modDirectory: missing)
        XCTAssertEqual(r.verdict, .inconclusive)
        XCTAssertTrue(r.signals.isEmpty)
    }

    func testUnrecognisedFilesAreCounted() throws {
        try write("a.patch_0")
        try write("weird.bin")
        let r = inspect()
        XCTAssertEqual(r.verdict, .assetsOnly)
        XCTAssertEqual(r.unrecognisedFileCount, 1)
    }

    func testSymlinksAreNotFollowed() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibertyOutside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try write("evil.dll", in: outside)
        try write("a.patch_0")
        try FileManager.default.createSymbolicLink(at: tmp.appendingPathComponent("link"), withDestinationURL: outside)
        XCTAssertEqual(inspect().verdict, .assetsOnly)
    }

    func testSignalOrderingIsDeterministic() throws {
        for name in ["z.lua", "b.dll", "a.lua", "sub/c.dll", "BingusX.json"] { try write(name) }
        let first = inspect()
        let second = inspect()
        XCTAssertEqual(first.signals, second.signals)
        XCTAssertEqual(first.signals.map(\.path), ["b.dll", "sub/c.dll", "a.lua", "z.lua", "BingusX.json"])
    }

    func testPathsAreRelative() throws {
        try write("deep/er/x.dll")
        let r = inspect()
        XCTAssertEqual(r.signals.first?.path, "deep/er/x.dll")
        for s in r.signals {
            XCTAssertFalse(s.path.hasPrefix("/"))
            XCTAssertFalse(s.path.contains(tmp.lastPathComponent))
        }
    }
}
