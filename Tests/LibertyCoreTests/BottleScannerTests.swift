import XCTest
@testable import LibertyCore

final class BottleScannerTests: TempDirTestCase {
    func testFindsGameInDefaultSteamLibrary() throws {
        try write("Steam/drive_c/Program Files (x86)/Steam/steam.exe")
        try write("Steam/drive_c/Program Files (x86)/Steam/steamapps/common/Helldivers 2/bin/helldivers2.exe")
        try write("Steam/drive_c/Program Files (x86)/Steam/steamapps/appmanifest_553850.acf",
                  "\"AppState\"\n{\n\t\"appid\"\t\t\"553850\"\n\t\"buildid\"\t\t\"16125432\"\n}")
        try write("Other/drive_c/windows/system.ini")

        let bottles = BottleScanner(bottlesDirectory: tmp).bottles()
        XCTAssertEqual(bottles.map(\.name), ["Other", "Steam"])

        let game = try XCTUnwrap(bottles.first { $0.name == "Steam" }?.game)
        XCTAssertNil(bottles.first { $0.name == "Other" }?.game)
        XCTAssertEqual(game.bottleName, "Steam")
        XCTAssertEqual(game.steamWindowsPath, "C:\\Program Files (x86)\\Steam\\steam.exe")
        XCTAssertEqual(game.buildID, "16125432")
        XCTAssertEqual(game.dataDir.lastPathComponent, "data")
    }

    func testFindsGameInSecondaryLibrary() throws {
        let vdf = """
        "libraryfolders"
        {
            "0" { "path" "C:\\\\Program Files (x86)\\\\Steam" }
            "1" { "path" "C:\\\\Games\\\\SteamLibrary" }
        }
        """
        try write("B/drive_c/Program Files (x86)/Steam/steamapps/libraryfolders.vdf", vdf)
        try write("B/drive_c/Games/SteamLibrary/steamapps/common/Helldivers 2/bin/helldivers2.exe")

        let game = try XCTUnwrap(BottleScanner(bottlesDirectory: tmp).findGame(inBottle: tmp.appendingPathComponent("B")))
        XCTAssertTrue(game.libraryURL.path.hasSuffix("drive_c/Games/SteamLibrary"))
        XCTAssertTrue(game.steamRootURL.path.hasSuffix("Program Files (x86)/Steam"))
    }

    func testUserSettingsPathPrefersExistingUser() throws {
        try write("B/drive_c/Program Files (x86)/Steam/steamapps/common/Helldivers 2/bin/helldivers2.exe")
        try write("B/drive_c/users/Public/readme.txt")
        try write("B/drive_c/users/someone/AppData/Roaming/Arrowhead/Helldivers2/user_settings.config")
        let game = try XCTUnwrap(BottleScanner(bottlesDirectory: tmp).findGame(inBottle: tmp.appendingPathComponent("B")))
        XCTAssertTrue(game.userSettingsURL.path.contains("/users/someone/"))
    }

    func testLaunchCommand() throws {
        try write("B/drive_c/Program Files (x86)/Steam/steamapps/common/Helldivers 2/bin/helldivers2.exe")
        let game = try XCTUnwrap(BottleScanner(bottlesDirectory: tmp).findGame(inBottle: tmp.appendingPathComponent("B")))
        let crossOver = CrossOverInstall(appURL: URL(fileURLWithPath: "/Applications/CrossOver.app"), version: "25.0.1")
        let command = try GameLauncher.command(crossOver: crossOver, game: game, launchArguments: ["--foo"], environment: ["MTL_HUD_ENABLED": "1"])
        XCTAssertEqual(command.executableURL.path, "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine")
        XCTAssertEqual(command.arguments, ["--bottle", "B", "C:\\Program Files (x86)\\Steam\\steam.exe", "-applaunch", "553850", "--foo"])
        XCTAssertEqual(command.environment["MTL_HUD_ENABLED"], "1")
        XCTAssertTrue(crossOver.isSupportedVersion)
        XCTAssertFalse(CrossOverInstall(appURL: crossOver.appURL, version: "23.7").isSupportedVersion)
    }
}
