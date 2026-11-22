import Foundation
@testable import LibertyCore

/// What `CosmeticCheck` reads out of patch headers. Hash values are the
/// verified Stingray resource type hashes.
final class PatchContentsTests: TempDirTestCase {

    private let wwiseStream: UInt64 = 0x504B55235D63CCCF
    private let wwiseBank: UInt64 = 0x535A7BD3E650D799
    private let texture: UInt64 = 0xCD4238C6A0C69E32
    private let material: UInt64 = 0xEAC0B497876ADEDF

    private func le(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8((v >> (8 * UInt64($0))) & 0xFF) } }

    /// Header magic plus padding, then the hashes, 8-byte aligned.
    private func header(_ hashes: [UInt64]) -> [UInt8] {
        var b: [UInt8] = [0x11, 0x00, 0x00, 0xF0, 0x01, 0x00, 0x00, 0x00]
        b += [UInt8](repeating: 0, count: 8)
        for h in hashes { b += le(h) }
        return b
    }

    private func put(_ name: String, _ bytes: [UInt8]) throws {
        let url = tmp.appendingPathComponent(name)
        try Data(bytes).write(to: url)
    }

    private func inspect() -> CosmeticCheck.Report {
        CosmeticCheck().inspect(modDirectory: tmp)
    }

    func testAudioHashesGiveAudioOnce() throws {
        try put("a.patch_0", header([wwiseStream, wwiseBank, wwiseStream]))
        XCTAssertEqual(inspect().replaces, [.audio])
    }

    func testReplacesFollowsAllCasesOrder() throws {
        try put("a.patch_0", header([material, texture]))
        XCTAssertEqual(inspect().replaces, [.texture, .material])
    }

    func testHashesUnionedAcrossPatchFiles() throws {
        try put("a.patch_0", header([wwiseBank]))
        try put("a.patch_1", header([texture]))
        XCTAssertEqual(inspect().replaces, [.audio, .texture])
    }

    func testUnknownHashContributesNothing() throws {
        try put("a.patch_0", header([0x1234567890ABCDEF, 0xFFFFFFFFFFFFFFFF]))
        let r = inspect()
        XCTAssertTrue(r.replaces.isEmpty)
        XCTAssertEqual(r.replacesSummary, "contents not identified")
    }

    func testHashPastScanLimitIsNotFound() throws {
        var b = header([])
        b += [UInt8](repeating: 0, count: 256 * 1024 - b.count)
        b += le(texture)
        try put("a.patch_0", b)
        XCTAssertTrue(inspect().replaces.isEmpty)
    }

    func testHashJustInsideScanLimitIsFound() throws {
        var b = header([])
        b += [UInt8](repeating: 0, count: 256 * 1024 - 8 - b.count)
        b += le(texture)
        try put("a.patch_0", b)
        XCTAssertEqual(inspect().replaces, [.texture])
    }

    func testUnalignedHashIsNotMatched() throws {
        var b = header([])
        b += [0x00]            // shifts the hash off 8-byte alignment
        b += le(texture)
        try put("a.patch_0", b)
        XCTAssertTrue(inspect().replaces.isEmpty)
    }

    func testTruncatedFilesAreHandled() throws {
        try put("a.patch_0", [0x11, 0x00, 0x00])
        try put("b.patch_0", [])
        let r = inspect()
        XCTAssertTrue(r.replaces.isEmpty)
        XCTAssertEqual(r.patchFileCount, 2)
    }

    func testStreamAndGpuSiblingsAreSkipped() throws {
        try put("a.patch_0.stream", header([texture]))
        try put("a.patch_0.gpu_resources", header([material]))
        try put("a.patch_0", header([wwiseBank]))
        XCTAssertEqual(inspect().replaces, [.audio])
    }

    func testNoPatchesMeansNoAssetPatches() throws {
        try write("readme.txt")
        let r = inspect()
        XCTAssertTrue(r.replaces.isEmpty)
        XCTAssertEqual(r.replacesSummary, "no asset patches")
    }

    func testIsAudioOnly() throws {
        try put("a.patch_0", header([wwiseBank]))
        XCTAssertTrue(inspect().isAudioOnly)
        try put("b.patch_0", header([texture]))
        XCTAssertFalse(inspect().isAudioOnly)
    }

    func testIsAudioOnlyFalseWhenEmpty() throws {
        XCTAssertFalse(inspect().isAudioOnly)
    }
}
