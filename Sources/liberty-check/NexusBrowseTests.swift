import Foundation
@testable import LibertyCore

/// Stub transport so the paging tests never touch the network.
final class StubNexusProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestCount += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class NexusBrowseTests: XCTestCase {
    private let searchJSON = """
    {"data":{"mods":{"nodes":[
      {"modId":1,"name":"Clean","adultContent":false,"status":"published","uploader":{"name":"A"}},
      {"modId":2,"name":"Spicy","adultContent":true,"status":"published"},
      {"modId":3,"name":"Gone","adultContent":false,"status":"hidden"},
      {"modId":4,"name":"Plain"}
    ]}}}
    """

    func testParseSearchReadsAdultAndAvailability() {
        let mods = NexusClient.parseSearch(Data(searchJSON.utf8)) ?? []
        XCTAssertEqual(mods.count, 4)
        XCTAssertEqual(mods[0].contains_adult_content, false)
        XCTAssertEqual(mods[0].available, true)
        XCTAssertEqual(mods[1].contains_adult_content, true)
        XCTAssertEqual(mods[2].available, false)
    }

    func testParseSearchWithoutFieldsLeavesNil() {
        let mods = NexusClient.parseSearch(Data(searchJSON.utf8)) ?? []
        XCTAssertEqual(mods[3].available, nil)
        XCTAssertEqual(mods[3].contains_adult_content, nil)
        XCTAssertTrue(mods[3].isListable)
    }

    func testSearchResultsFilterAdultAndUnavailable() {
        let mods = (NexusClient.parseSearch(Data(searchJSON.utf8)) ?? []).filter(\.isListable)
        XCTAssertEqual(mods.map(\.id), [1, 4])
    }

    private func fixtureMods(_ n: Int) -> [NexusModSummary] {
        (1...n).map { NexusModSummary(modID: $0, name: "Mod \($0)", summary: nil, pictureURL: nil, endorsements: nil, author: nil, version: nil) }
    }

    func testPagingSlicesAndHasMore() {
        let all = fixtureMods(5)
        let first = NexusPage.slice(all, page: 0, pageSize: 3)
        XCTAssertEqual(first.mods.map(\.id), [1, 2, 3])
        XCTAssertTrue(first.hasMore)
        let second = NexusPage.slice(all, page: 1, pageSize: 3)
        XCTAssertEqual(second.mods.map(\.id), [4, 5])
        XCTAssertFalse(second.hasMore)
        let exact = NexusPage.slice(all, page: 0, pageSize: 5)
        XCTAssertFalse(exact.hasMore)
    }

    func testPagingOutOfRangeIsEmpty() {
        let all = fixtureMods(5)
        for (page, size) in [(2, 3), (99, 3), (-1, 3), (0, 0), (Int.max, 10)] {
            let result = NexusPage.slice(all, page: page, pageSize: size)
            XCTAssertTrue(result.mods.isEmpty)
            XCTAssertFalse(result.hasMore)
        }
    }

    func testClientPagingFetchesOnceAndFilters() {
        let json = """
        [{"mod_id":1,"name":"A"},{"mod_id":2,"name":"Spicy","contains_adult_content":true},
         {"mod_id":3,"name":"C"},{"mod_id":4,"name":"D"}]
        """
        StubNexusProtocol.requestCount = 0
        StubNexusProtocol.body = Data(json.utf8)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubNexusProtocol.self]
        var client = NexusClient(apiKey: "test-key-not-real")
        client.session = URLSession(configuration: config)
        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        Task {
            box.first = try? await client.list(.trending, page: 0, pageSize: 2, game: "g")
            box.second = try? await client.list(.trending, page: 1, pageSize: 2, game: "g")
            done.signal()
        }
        done.wait()
        XCTAssertEqual(box.first?.mods.map(\.id), [1, 3])
        XCTAssertEqual(box.first?.hasMore, true)
        XCTAssertEqual(box.second?.mods.map(\.id), [4])
        XCTAssertEqual(box.second?.hasMore, false)
        XCTAssertEqual(StubNexusProtocol.requestCount, 1)
    }

    func testNeedsModRuntime() {
        func req(_ name: String, id: Int? = nil) -> NexusRequirement {
            NexusRequirement(modID: id, name: name, url: nil, isExternal: false, notes: nil)
        }
        XCTAssertTrue([req("Bingus Shared Loader")].needsModRuntime)
        XCTAssertTrue([req("HD2Runtime")].needsModRuntime)
        XCTAssertTrue([req("HD2 Runtime")].needsModRuntime)
        XCTAssertFalse([req("Base Armor Framework")].needsModRuntime)
        XCTAssertFalse([req("HD2 Mod Manager", id: 109)].needsModRuntime)
        XCTAssertEqual([req("Base"), req("hd2runtime")].runtimeRequirements.map(\.name), ["hd2runtime"])
    }

    func testRequirementsParseFixtureFeedsRuntimeCheck() {
        let json = """
        {"data":{"legacyModsByDomain":{"nodes":[{"modId":7,"modRequirements":{"nexusRequirements":{"nodes":[
          {"modId":"12","modName":"Bingus Shared Loader","url":"https://www.nexusmods.com/helldivers2/mods/12","externalRequirement":false},
          {"modId":"109","modName":"HD2 Mod Manager","externalRequirement":false}
        ]}}}]}}}
        """
        let requirements = NexusClient.parseRequirements(Data(json.utf8)) ?? []
        XCTAssertEqual(requirements.map(\.name), ["Bingus Shared Loader", "HD2 Mod Manager"])
        XCTAssertEqual(requirements.runtimeRequirements.map(\.modID), [12])
        XCTAssertTrue(requirements.needsModRuntime)
    }
}

final class ResultBox: @unchecked Sendable {
    var first: NexusPage?
    var second: NexusPage?
}
