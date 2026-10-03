import Foundation
import XCTest

/// Temporary directory removed after each test.
class TempDirTestCase: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("LibertyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    @discardableResult
    func write(_ relativePath: String, _ contents: String = "x", in base: URL? = nil) throws -> URL {
        let url = (base ?? tmp).appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func files(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }
}
