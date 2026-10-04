import XCTest
@testable import LibertyCore

final class ModLogsTests: TempDirTestCase {
    func testFindLogsNewestFirst() throws {
        let local = tmp.appendingPathComponent("users/crossover/AppData/Local")
        let old = try write("CowboyBingus/Helldivers2/Logs/old.log", "old", in: local)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: old.path)
        try write("CowboyBingus/Helldivers2/Logs/new.log", "new", in: local)
        try write("CowboyBingus/Helldivers2/Logs/image.png", "x", in: local)
        try write("SomethingElse/OtherGame/log.log", "x", in: local)

        let logs = ModLogs.find(inLocalAppData: [local])
        XCTAssertEqual(logs.map(\.url.lastPathComponent), ["new.log", "old.log"])
        XCTAssertEqual(logs.first?.source, "CowboyBingus")
    }

    func testFindThroughGamePaths() throws {
        try write("B/drive_c/Program Files (x86)/Steam/steamapps/common/Helldivers 2/bin/helldivers2.exe")
        try write("B/drive_c/users/crossover/AppData/Local/CowboyBingus/Helldivers2/Logs/run.log", "hi")
        let game = try XCTUnwrap(BottleScanner(bottlesDirectory: tmp).findGame(inBottle: tmp.appendingPathComponent("B")))
        XCTAssertEqual(ModLogs.find(game: game).map(\.url.lastPathComponent), ["run.log"])
    }

    func testTailAndParsing() throws {
        let lines = (1...500).map { "line \($0)" } + [
            "[INFO] discovered mods/cowboybingus/mod_options_menu",
            "[INFO] discovered mods/cowboybingus/mod_bindings_menu",
            "[ERROR] Build mismatch: expected 25480438, got 25611111",
            "[ERROR] Build mismatch: expected 25480438, got 25611111",
            "[WARN] resource not found: mods/other/thing",
        ]
        let file = try write("log.log", lines.joined(separator: "\n"))
        let tail = ModLogs.tail(file, maxLines: 5)
        XCTAssertEqual(tail.components(separatedBy: "\n").count, 5)
        XCTAssertTrue(tail.hasPrefix("[INFO] discovered mods/cowboybingus/mod_options_menu"))

        XCTAssertEqual(ModLogs.problemLines(in: tail), [
            "[ERROR] Build mismatch: expected 25480438, got 25611111",
            "[WARN] resource not found: mods/other/thing",
        ])
        XCTAssertEqual(ModLogs.foundMods(in: tail), ["mods/cowboybingus/mod_options_menu", "mods/cowboybingus/mod_bindings_menu", "mods/other/thing"])
        XCTAssertEqual(ModLogs.problemLines(in: "[INFO] all good\nloaded 3 mods"), [])
    }

    func testLoaderDidNotRun() {
        let start = Date(timeIntervalSince1970: 10_000)
        let end = start.addingTimeInterval(1800)
        let during = ModLogFile(url: URL(fileURLWithPath: "/a.log"), source: "CowboyBingus", modified: start.addingTimeInterval(30))
        let before = ModLogFile(url: URL(fileURLWithPath: "/b.log"), source: "CowboyBingus", modified: start.addingTimeInterval(-86_400))
        XCTAssertFalse(ModLogs.loaderDidNotRun(logs: [during], source: "CowboyBingus", sessionStart: start, sessionEnd: end, lastDeploy: nil))
        XCTAssertTrue(ModLogs.loaderDidNotRun(logs: [before], source: "CowboyBingus", sessionStart: start, sessionEnd: end, lastDeploy: nil))
        XCTAssertTrue(ModLogs.loaderDidNotRun(logs: [], source: nil, sessionStart: start, sessionEnd: end, lastDeploy: nil))
        // Mods were changed after the session: no conclusion yet.
        XCTAssertFalse(ModLogs.loaderDidNotRun(logs: [], source: nil, sessionStart: start, sessionEnd: end, lastDeploy: end.addingTimeInterval(60)))
        XCTAssertFalse(ModLogs.loaderDidNotRun(logs: [], source: nil, sessionStart: nil, sessionEnd: nil, lastDeploy: nil))
    }

    func testPlaytimeSessionTimestamps() throws {
        var record = PlaytimeRecord()
        let t0 = Date(timeIntervalSince1970: 0)
        record.update(isRunning: true, now: t0)
        record.update(isRunning: true, now: t0.addingTimeInterval(100))
        record.update(isRunning: false, now: t0.addingTimeInterval(200))
        XCTAssertEqual(record.lastSessionStart, t0)
        XCTAssertEqual(record.lastSessionEnd, t0.addingTimeInterval(100))

        let old = #"{"totalSeconds":5,"sessionCount":1,"lastSessionSeconds":5}"#
        let decoded = try JSONDecoder().decode(PlaytimeRecord.self, from: Data(old.utf8))
        XCTAssertNil(decoded.lastSessionStart)
        XCTAssertEqual(decoded.totalSeconds, 5)
    }
}
