import XCTest
@testable import LibertyCore

final class V3FeatureTests: TempDirTestCase {
    // MARK: Nexus browse

    func testDecodeTrendingAndFilter() throws {
        let json = """
        [{"mod_id":1,"name":"Armor Pack","summary":"Cool","picture_url":"https://x/1.jpg","endorsement_count":50,"author":"A","version":"1.0","available":true,"contains_adult_content":false},
         {"mod_id":2,"name":"Hidden","available":false},
         {"mod_id":3,"name":"Spicy","available":true,"contains_adult_content":true},
         {"mod_id":4,"available":true}]
        """
        let mods = try JSONDecoder().decode([NexusModSummary].self, from: Data(json.utf8)).filter(\.isListable)
        XCTAssertEqual(mods.map(\.id), [1])
        XCTAssertEqual(mods[0].pictureURL?.absoluteString, "https://x/1.jpg")
        XCTAssertEqual(mods[0].pageURL.absoluteString, "https://www.nexusmods.com/helldivers2/mods/1")
    }

    func testPreferredFile() throws {
        let json = """
        {"files":[{"file_id":1,"category_name":"OLD_VERSION","uploaded_timestamp":10},
                  {"file_id":2,"category_name":"MAIN","uploaded_timestamp":20},
                  {"file_id":3,"category_name":"MAIN","uploaded_timestamp":30},
                  {"file_id":4,"category_name":"OPTIONAL","uploaded_timestamp":40}]}
        """
        let files = try JSONDecoder().decode(NexusFileList.self, from: Data(json.utf8)).files
        XCTAssertEqual(NexusClient.preferredFile(files)?.file_id, 3)
        let withPrimary = files + [NexusFile(file_id: 9, name: nil, version: nil, category_name: "MISCELLANEOUS", is_primary: true, uploaded_timestamp: 1)]
        XCTAssertEqual(NexusClient.preferredFile(withPrimary)?.file_id, 9)
        XCTAssertNil(NexusClient.preferredFile([]))
    }

    func testParseGraphQLSearch() {
        let json = """
        {"data":{"mods":{"nodes":[{"modId":7,"name":"Cape","summary":"s","pictureUrl":"https://p","endorsements":3,"version":"2","uploader":{"name":"U"}},{"name":"no id"}]}}}
        """
        let mods = NexusClient.parseSearch(Data(json.utf8))
        XCTAssertEqual(mods?.map(\.id), [7])
        XCTAssertEqual(mods?.first?.author, "U")
        XCTAssertNil(NexusClient.parseSearch(Data(#"{"errors":[{"message":"bad"}]}"#.utf8)))
    }

    // MARK: Galactic War

    func testParseWar() {
        let war = #"{"statistics":{"playerCount":123456}}"#
        let assignments = #"[{"title":"MAJOR ORDER","briefing":"Liberate Malevelon Creek","expiration":"2026-10-05T12:00:00Z"},{"foo":1}]"#
        let campaigns = """
        [{"planet":{"index":10,"name":"Creek","health":250000,"maxHealth":1000000,"statistics":{"playerCount":500}},"faction":"Automatons"},
         {"planet":{"index":11,"name":"Fenrir","health":0,"maxHealth":1000000,"statistics":{"playerCount":9000}},"faction":"Terminids"},
         {"nope":true}]
        """
        let status = WarClient.parse(war: Data(war.utf8), assignments: Data(assignments.utf8), campaigns: Data(campaigns.utf8))
        XCTAssertEqual(status.playerCount, 123456)
        XCTAssertEqual(status.majorOrders.count, 1)
        XCTAssertEqual(status.majorOrders.first?.briefing, "Liberate Malevelon Creek")
        XCTAssertNotNil(status.majorOrders.first?.expiration)
        XCTAssertEqual(status.planets.map(\.name), ["Fenrir", "Creek"])
        XCTAssertEqual(status.planets.last?.liberation ?? 0, 75, accuracy: 0.01)
        XCTAssertEqual(status.planets.first?.liberation ?? 0, 100, accuracy: 0.01)
    }

    func testParseWarToleratesMissingData() {
        let status = WarClient.parse(war: nil, assignments: Data("garbage".utf8), campaigns: nil)
        XCTAssertNil(status.playerCount)
        XCTAssertTrue(status.majorOrders.isEmpty)
        XCTAssertTrue(status.planets.isEmpty)
    }

    // MARK: Discord

    func testDiscordFrameEncoding() throws {
        let data = try XCTUnwrap(DiscordRPC.frame(.handshake, ["v": 1, "client_id": "42"]))
        let json = #"{"client_id":"42","v":1}"#
        XCTAssertEqual(Array(data.prefix(4)), [0, 0, 0, 0])
        XCTAssertEqual(Array(data[4..<8]), [UInt8(json.utf8.count), 0, 0, 0])
        XCTAssertEqual(String(decoding: data.dropFirst(8), as: UTF8.self), json)
    }

    func testDiscordActivityPayload() throws {
        let activity = DiscordRPC.Activity(details: "Helldivers 2", state: "Diving", start: Date(timeIntervalSince1970: 100))
        let payload = DiscordRPC.activityPayload(activity, pid: 7, nonce: "n")
        XCTAssertEqual(payload["cmd"] as? String, "SET_ACTIVITY")
        let args = try XCTUnwrap(payload["args"] as? [String: Any])
        XCTAssertEqual(args["pid"] as? Int, 7)
        let body = try XCTUnwrap(args["activity"] as? [String: Any])
        XCTAssertEqual((body["timestamps"] as? [String: Int])?["start"], 100)
        XCTAssertEqual((body["assets"] as? [String: String])?["large_image"], "logo")

        let cleared = DiscordRPC.activityPayload(nil, pid: 7, nonce: "n")
        XCTAssertNil((cleared["args"] as? [String: Any])?["activity"])
    }

    // MARK: Crash detection

    func testCrashDetection() {
        var detector = CrashDetector(minimumHealthySession: 90)
        let t0 = Date(timeIntervalSince1970: 0)
        detector.gameStarted(at: t0)
        XCTAssertTrue(detector.gameStopped(at: t0.addingTimeInterval(30)))

        detector.gameStarted(at: t0)
        XCTAssertFalse(detector.gameStopped(at: t0.addingTimeInterval(600)))

        detector.gameStarted(at: t0)
        detector.userWillStopGame()
        XCTAssertFalse(detector.gameStopped(at: t0.addingTimeInterval(5)))

        XCTAssertFalse(detector.gameStopped(at: t0)) // never started
    }

    func testRecentCrashFiles() throws {
        let dir = tmp.appendingPathComponent("Helldivers2")
        try write("crash_20261003.dmp", in: dir)
        try write("logs/error_log.txt", in: dir)
        try write("user_settings.config", in: dir)
        let old = try write("old_crash.txt", in: dir)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: old.path)

        let found = CrashDetector.recentCrashFiles(in: dir, since: Date().addingTimeInterval(-600)).map(\.lastPathComponent).sorted()
        XCTAssertEqual(found, ["crash_20261003.dmp", "error_log.txt"])
    }

    // MARK: Setup assistant

    func testSetupStatus() throws {
        let scanner = BottleScanner(bottlesDirectory: tmp)
        var status = SetupStatus(crossOver: nil, bottles: scanner.bottles(), scanner: scanner)
        XCTAssertEqual(status.currentStep, .crossOver)
        XCTAssertFalse(status.isReady)

        let crossOver = CrossOverInstall(appURL: URL(fileURLWithPath: "/Applications/CrossOver.app"), version: "25.0")
        try write("Steam/drive_c/Program Files (x86)/Steam/steam.exe")
        status = SetupStatus(crossOver: crossOver, bottles: scanner.bottles(), scanner: scanner)
        XCTAssertEqual(status.steamBottle?.lastPathComponent, "Steam")
        XCTAssertEqual(status.currentStep, .game)

        try write("Steam/drive_c/Program Files (x86)/Steam/steamapps/common/Helldivers 2/bin/helldivers2.exe")
        status = SetupStatus(crossOver: crossOver, bottles: scanner.bottles(), scanner: scanner)
        XCTAssertTrue(status.isReady)
        XCTAssertEqual(status.currentStep, .preset)

        let steamRoot = try XCTUnwrap(scanner.steamRoot(inBottle: tmp.appendingPathComponent("Steam")))
        let command = try XCTUnwrap(GameLauncher.steamURLCommand(
            crossOver: crossOver, bottleURL: tmp.appendingPathComponent("Steam"), steamRoot: steamRoot, url: "steam://install/553850"))
        XCTAssertEqual(command.arguments, ["--bottle", "Steam", "C:\\Program Files (x86)\\Steam\\steam.exe", "steam://install/553850"])
    }
}
