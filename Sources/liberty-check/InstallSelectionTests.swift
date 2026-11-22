import Foundation
@testable import LibertyCore

/// Selecting between installs, and deciding when the game really changed.
/// These cover the upgrade path: settings written before Obelisk support
/// stored a bottle path, and must keep pointing at the same install.
final class InstallSelectionTests: XCTestCase {

    private func crossOverInstall(bottle: String) -> GameInstall {
        let bottleURL = URL(fileURLWithPath: "/Bottles/\(bottle)")
        let steam = bottleURL.appendingPathComponent("drive_c/Program Files (x86)/Steam")
        return GameInstall(name: bottle,
                           paths: GamePaths(bottleURL: bottleURL, steamRootURL: steam, libraryURL: steam))
    }

    private func obeliskInstall(game: String) -> GameInstall {
        GameInstall(name: "Obelisk",
                    paths: GamePaths(obeliskGameRoot: URL(fileURLWithPath: game),
                                     prefixRoot: URL(fileURLWithPath: "\(game)-prefix")))
    }

    func testNilKeyPicksFirst() throws {
        let installs = [self.crossOverInstall(bottle: "Steam"), self.obeliskInstall(game: "/Games/HD2")]
        XCTAssertEqual(InstallScanner.resolve(key: nil, among: installs)?.name, "Steam")
        XCTAssertEqual(InstallScanner.resolve(key: "", among: installs)?.name, "Steam")
    }

    func testEmptyListResolvesToNil() throws {
        XCTAssertNil(InstallScanner.resolve(key: "anything", among: []))
        XCTAssertNil(InstallScanner.resolve(key: nil, among: []))
    }

    func testResolvesByGameRootID() throws {
        let obelisk = self.obeliskInstall(game: "/Games/HD2")
        let installs = [self.crossOverInstall(bottle: "Steam"), obelisk]
        XCTAssertEqual(InstallScanner.resolve(key: obelisk.id, among: installs)?.source, .obelisk)
    }

    /// The upgrade case: a settings file written before Obelisk support holds a
    /// bottle path, not a game root.
    func testLegacyBottlePathStillResolves() throws {
        let installs = [self.crossOverInstall(bottle: "Steam"), self.crossOverInstall(bottle: "Obelisk-HD2")]
        let chosen = InstallScanner.resolve(key: "/Bottles/Obelisk-HD2", among: installs)
        XCTAssertEqual(chosen?.name, "Obelisk-HD2")
    }

    /// An install that has gone away must fall back, not strand the app.
    func testUnknownKeyFallsBackToFirst() throws {
        let installs = [self.crossOverInstall(bottle: "Steam")]
        XCTAssertEqual(InstallScanner.resolve(key: "/Bottles/Deleted", among: installs)?.name, "Steam")
    }

    func testGameChangedNeedsBothSides() throws {
        let a = InstallFingerprint(kind: .buildID, buildID: "1", sha256: nil,
                                   executableSize: 1, executableModified: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(InstallFingerprint.gameChanged(current: a, lastDeployed: nil))
        XCTAssertFalse(InstallFingerprint.gameChanged(current: nil, lastDeployed: a))
        XCTAssertFalse(InstallFingerprint.gameChanged(current: nil, lastDeployed: nil))
    }

    func testGameChangedOnDifferentBuildID() throws {
        let date = Date(timeIntervalSince1970: 0)
        let a = InstallFingerprint(kind: .buildID, buildID: "1", sha256: nil, executableSize: 1, executableModified: date)
        let b = InstallFingerprint(kind: .buildID, buildID: "2", sha256: nil, executableSize: 1, executableModified: date)
        XCTAssertTrue(InstallFingerprint.gameChanged(current: b, lastDeployed: a))
        XCTAssertFalse(InstallFingerprint.gameChanged(current: a, lastDeployed: a))
    }

    /// Switching between a CrossOver install and an Obelisk one compares a
    /// build id to a hash. That is a different install, not a patched game, and
    /// must not raise "Helldivers 2 was updated".
    func testSwitchingSourcesIsNotAnUpdate() throws {
        let date = Date(timeIntervalSince1970: 0)
        let viaBottle = InstallFingerprint(kind: .buildID, buildID: "26088801", sha256: nil,
                                           executableSize: 28743256, executableModified: date)
        let viaObelisk = InstallFingerprint(kind: .executableHash, buildID: nil,
                                            sha256: String(repeating: "a", count: 64),
                                            executableSize: 28743256, executableModified: date)
        XCTAssertEqual(viaObelisk.compare(to: viaBottle), .notComparable)
        XCTAssertFalse(InstallFingerprint.gameChanged(current: viaObelisk, lastDeployed: viaBottle))
    }

    func testGameChangedOnDifferentHash() throws {
        let date = Date(timeIntervalSince1970: 0)
        let a = InstallFingerprint(kind: .executableHash, buildID: nil, sha256: String(repeating: "a", count: 64),
                                   executableSize: 10, executableModified: date)
        let b = InstallFingerprint(kind: .executableHash, buildID: nil, sha256: String(repeating: "b", count: 64),
                                   executableSize: 10, executableModified: date)
        XCTAssertTrue(InstallFingerprint.gameChanged(current: b, lastDeployed: a))
    }
}
