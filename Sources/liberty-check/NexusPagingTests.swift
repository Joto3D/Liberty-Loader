import Foundation
@testable import LibertyCore

/// Stub transport for the GraphQL paging tests: records every request body and answers a canned reply.
final class PagingStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var bodies: [Data] = []
    nonisolated(unsafe) static var headers: [[String: String]] = []
    nonisolated(unsafe) static var reply = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        Self.bodies.append(body)
        Self.headers.append(request.allHTTPHeaderFields ?? [:])
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.reply)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class PagingBox: @unchecked Sendable {
    var page: NexusPage?
    var error: Error?
}

final class NexusPagingTests: XCTestCase {
    private func page(total: Int, nodes: String) -> String {
        "{\"data\":{\"mods\":{\"totalCount\":\(total),\"nodes\":[\(nodes)]}}}"
    }

    private let mixedNodes = """
    {"modId":109,"name":"HD2ModManager","adultContent":false,"status":"published","endorsements":17542,"uploader":{"name":"A"}},
    {"modId":2,"name":"Spicy","adultContent":true,"status":"published"},
    {"modId":3,"name":"Gone","adultContent":false,"status":"hidden"},
    {"modId":4,"name":"Draft","adultContent":false,"status":"under_moderation"}
    """

    private func browse(_ json: String, sort: NexusSort = .endorsements, offset: Int = 0, count: Int = 4) -> PagingBox {
        PagingStubProtocol.bodies = []
        PagingStubProtocol.headers = []
        PagingStubProtocol.reply = Data(json.utf8)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PagingStubProtocol.self]
        var client = NexusClient(apiKey: "test-key-not-real")
        client.session = URLSession(configuration: config)
        let box = PagingBox()
        let done = DispatchSemaphore(value: 0)
        Task {
            do { box.page = try await client.browse(sort: sort, offset: offset, count: count, game: "g") }
            catch { box.error = error }
            done.signal()
        }
        done.wait()
        return box
    }

    private func sentVariables(_ index: Int = 0) -> [String: Any] {
        let body = PagingStubProtocol.bodies[index]
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        return json?["variables"] as? [String: Any] ?? [:]
    }

    func testBrowseParsesTotalCountAndMapsFields() throws {
        let box = browse(page(total: 13762, nodes: mixedNodes))
        let result = try XCTUnwrap(box.page)
        XCTAssertEqual(result.totalCount, 13762)
        XCTAssertEqual(result.mods.map(\.id), [109])
        XCTAssertEqual(result.mods[0].name, "HD2ModManager")
        XCTAssertEqual(result.mods[0].endorsement_count, 17542)
        XCTAssertEqual(result.mods[0].author, "A")
        XCTAssertEqual(result.mods[0].available, true)
        XCTAssertEqual(result.mods[0].contains_adult_content, false)
    }

    func testStatusMapsToAvailable() throws {
        let nodes = NexusClient.parseSearch(Data(page(total: 4, nodes: mixedNodes).utf8)) ?? []
        XCTAssertEqual(nodes[0].available, true)
        XCTAssertEqual(nodes[2].available, false)
        XCTAssertEqual(nodes[3].available, false)
        XCTAssertFalse(nodes[2].isListable)
        XCTAssertFalse(nodes[3].isListable)
    }

    func testAdultContentIsFilteredOut() throws {
        let nodes = """
        {"modId":1,"name":"Clean","adultContent":false,"status":"published"},
        {"modId":2,"name":"Spicy","adultContent":true,"status":"published"}
        """
        let result = try XCTUnwrap(browse(page(total: 2, nodes: nodes)).page)
        XCTAssertEqual(result.mods.map(\.id), [1])
    }

    func testHasMoreTrueWhenOffsetPlusCountBelowTotal() throws {
        let nodes = """
        {"modId":1,"name":"A","status":"published"},{"modId":2,"name":"B","status":"published"}
        """
        let result = try XCTUnwrap(browse(page(total: 5, nodes: nodes), offset: 0, count: 2).page)
        XCTAssertTrue(result.hasMore)
    }

    func testHasMoreFalseAtEnd() throws {
        let nodes = """
        {"modId":5,"name":"E","status":"published"}
        """
        let result = try XCTUnwrap(browse(page(total: 5, nodes: nodes), offset: 4, count: 2).page)
        XCTAssertFalse(result.hasMore)
        XCTAssertEqual(result.mods.map(\.id), [5])
    }

    func testHasMoreSurvivesFullyFilteredPage() throws {
        let nodes = """
        {"modId":2,"name":"Spicy","adultContent":true,"status":"published"},
        {"modId":3,"name":"Gone","adultContent":false,"status":"hidden"}
        """
        let result = try XCTUnwrap(browse(page(total: 100, nodes: nodes), offset: 10, count: 2).page)
        XCTAssertTrue(result.mods.isEmpty)
        XCTAssertTrue(result.hasMore)
        XCTAssertEqual(result.totalCount, 100)
    }

    func testEverySortProducesExpectedVariables() throws {
        let expected: [NexusSort: String] = [
            .endorsements: "DESC", .downloads: "DESC", .createdAt: "DESC", .updatedAt: "DESC", .name: "ASC",
        ]
        XCTAssertEqual(NexusSort.allCases.count, expected.count)
        for sort in NexusSort.allCases {
            let box = browse(page(total: 0, nodes: ""), sort: sort, offset: 0, count: 3)
            XCTAssertNotNil(box.page)
            let vars = sentVariables()
            let sortArray = try XCTUnwrap(vars["sort"] as? [[String: Any]])
            XCTAssertEqual(sortArray.count, 1)
            let entry = try XCTUnwrap(sortArray.first)
            XCTAssertEqual(Array(entry.keys), [sort.rawValue])
            let direction = (entry[sort.rawValue] as? [String: Any])?["direction"] as? String
            XCTAssertEqual(direction, expected[sort])
            XCTAssertEqual(vars["count"] as? Int, 3)
            XCTAssertEqual(vars["offset"] as? Int, 0)
            let filter = vars["filter"] as? [String: Any]
            let domain = (filter?["gameDomainName"] as? [[String: Any]])?.first
            XCTAssertEqual(domain?["value"] as? String, "g")
            XCTAssertEqual(domain?["op"] as? String, "EQUALS")
        }
    }

    func testGraphQLErrorsArrayIsFailure() {
        let json = "{\"errors\":[{\"message\":\"Cannot query field available on type Mod\"}],\"data\":null}"
        let box = browse(json)
        XCTAssertNil(box.page)
        XCTAssertNotNil(box.error)
        if case NexusBrowseError.graphQL(let message)? = box.error {
            XCTAssertTrue(message.contains("Cannot query field"))
        } else {
            XCTFail("expected NexusBrowseError.graphQL, got \(String(describing: box.error))")
        }
    }

    func testMissingModsNodeIsMalformed() {
        let box = browse("{\"data\":{}}")
        XCTAssertNil(box.page)
        XCTAssertNotNil(box.error)
    }

    func testDifferentOffsetsProduceDifferentRequests() throws {
        _ = browse(page(total: 100, nodes: ""), offset: 0, count: 40)
        let first = PagingStubProtocol.bodies[0]
        let firstOffset = sentVariables()["offset"] as? Int
        _ = browse(page(total: 100, nodes: ""), offset: 40, count: 40)
        let second = PagingStubProtocol.bodies[0]
        XCTAssertEqual(firstOffset, 0)
        XCTAssertEqual(sentVariables()["offset"] as? Int, 40)
        XCTAssertTrue(first != second)
    }

    func testRequestHeadersAndQuery() throws {
        _ = browse(page(total: 0, nodes: ""))
        let headers = PagingStubProtocol.headers[0]
        XCTAssertEqual(headers["Content-Type"], "application/json")
        XCTAssertEqual(headers["Application-Name"], "LibertyLoader")
        XCTAssertEqual(headers["apikey"], "test-key-not-real")
        let json = (try? JSONSerialization.jsonObject(with: PagingStubProtocol.bodies[0])) as? [String: Any]
        let query = json?["query"] as? String ?? ""
        XCTAssertTrue(query.contains("totalCount"))
        XCTAssertTrue(query.contains("$sort: [ModsSort!]"))
    }
}
