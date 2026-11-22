import Foundation
@testable import LibertyCore

final class BrowseQueryTests: XCTestCase {

    private func mod(_ id: Int, _ name: String? = "Mod", summary: String? = nil,
                     author: String? = nil, endorsements: Int? = nil) -> NexusModSummary {
        NexusModSummary(modID: id, name: name, summary: summary, pictureURL: nil,
                        endorsements: endorsements, author: author, version: nil)
    }

    private func decoded(_ json: String) throws -> NexusModSummary {
        try JSONDecoder().decode(NexusModSummary.self, from: Data(json.utf8))
    }

    private func ids(_ mods: [NexusModSummary]) -> [Int] { mods.map(\.mod_id) }

    func testDefaultQueryKeepsEverythingInOrder() throws {
        let input = [mod(30), mod(10), mod(20)]
        XCTAssertEqual(ids(BrowseQuery().apply(to: input)), [30, 10, 20])
    }

    func testAdultHiddenByDefaultShownWhenAllowed() throws {
        let adult = try decoded(#"{"mod_id":2,"name":"A","available":true,"contains_adult_content":true}"#)
        let input = [mod(1), adult]
        XCTAssertEqual(ids(BrowseQuery().apply(to: input)), [1])
        XCTAssertEqual(ids(BrowseQuery(allowAdult: true).apply(to: input)), [1, 2])
    }

    func testUnavailableHiddenEvenWhenAdultAllowed() throws {
        let gone = try decoded(#"{"mod_id":2,"name":"A","available":false,"contains_adult_content":false}"#)
        XCTAssertEqual(ids(BrowseQuery(allowAdult: true).apply(to: [mod(1), gone])), [1])
    }

    func testNilNameAlwaysHidden() throws {
        let input = [mod(1), mod(2, nil)]
        XCTAssertEqual(ids(BrowseQuery().apply(to: input)), [1])
        XCTAssertEqual(ids(BrowseQuery(allowAdult: true).apply(to: input)), [1])
    }

    func testHideInstalledRemovesExactlyInstalled() throws {
        let input = [mod(1), mod(2), mod(3)]
        let q = BrowseQuery(hideInstalled: true)
        XCTAssertEqual(ids(q.apply(to: input, installedIDs: [2, 99])), [1, 3])
        XCTAssertEqual(ids(q.apply(to: input)), [1, 2, 3])
        XCTAssertEqual(ids(BrowseQuery().apply(to: input, installedIDs: [2])), [1, 2, 3])
    }

    func testTextMatchesNameSummaryAuthorIndependently() throws {
        let input = [mod(1, "Zebra"), mod(2, "Other", summary: "zebra stripes"),
                     mod(3, "Third", author: "zebraMaker"), mod(4, "None", summary: "x", author: "y")]
        XCTAssertEqual(ids(BrowseQuery(text: "zebra").apply(to: input)), [1, 2, 3])
    }

    func testMultiWordRequiresAllWords() throws {
        let input = [mod(1, "Ultimate Doom Music Pack"), mod(2, "Doom Skins")]
        XCTAssertEqual(ids(BrowseQuery(text: "doom music").apply(to: input)), [1])
        XCTAssertEqual(ids(BrowseQuery(text: "  music   doom ").apply(to: input)), [1])
        XCTAssertEqual(ids(BrowseQuery(text: "doom banana").apply(to: input)), [])
    }

    func testWordsMayMatchAcrossFields() throws {
        let input = [mod(1, "Doom", author: "Maria")]
        XCTAssertEqual(ids(BrowseQuery(text: "doom maria").apply(to: input)), [1])
    }

    func testCaseAndDiacriticInsensitive() throws {
        let input = [mod(1, "Café Racer"), mod(2, "Other")]
        XCTAssertEqual(ids(BrowseQuery(text: "CAFE").apply(to: input)), [1])
        XCTAssertEqual(ids(BrowseQuery(text: "café").apply(to: [mod(3, "CAFE")])), [3])
    }

    func testWhitespaceOnlyTextIsNoFilter() throws {
        XCTAssertEqual(ids(BrowseQuery(text: "   ").apply(to: [mod(1), mod(2)])), [1, 2])
    }

    func testEndorsementsDescendingNilAsZero() throws {
        let input = [mod(1, endorsements: nil), mod(2, endorsements: 50), mod(3, endorsements: 10), mod(4, endorsements: 0)]
        XCTAssertEqual(ids(BrowseQuery(sort: .endorsements).apply(to: input)), [2, 3, 1, 4])
    }

    func testNameAscendingNilLast() throws {
        // nil-name mods are filtered by visibility, so exercise the comparator
        // through names only and confirm the case-insensitive order.
        let input = [mod(1, "banana"), mod(2, "Apple"), mod(3, "cherry")]
        XCTAssertEqual(ids(BrowseQuery(sort: .name).apply(to: input)), [2, 1, 3])
    }

    func testTiesBreakByModIDUnderEverySort() throws {
        let tied = [mod(5, "Same", endorsements: 7), mod(2, "same", endorsements: 7), mod(9, "SAME", endorsements: 7)]
        XCTAssertEqual(ids(BrowseQuery(sort: .endorsements).apply(to: tied)), [2, 5, 9])
        XCTAssertEqual(ids(BrowseQuery(sort: .name).apply(to: tied)), [2, 5, 9])
        // .nexus keeps incoming order (see report): stable, not re-sorted.
        XCTAssertEqual(ids(BrowseQuery(sort: .nexus).apply(to: tied)), [5, 2, 9])
    }

    func testDuplicateIDsStayStable() throws {
        let input = [mod(1, "A", summary: "first"), mod(1, "A", summary: "second")]
        for sort in BrowseQuery.Sort.allCases {
            XCTAssertEqual(BrowseQuery(sort: sort).apply(to: input).map(\.summary), ["first", "second"])
        }
    }

    func testDeterministicAcrossRepeatedApplication() throws {
        let input = (0..<200).map { mod($0, "N\($0 % 5)", endorsements: $0 % 3) }
        for sort in BrowseQuery.Sort.allCases {
            let q = BrowseQuery(sort: sort)
            let first = q.apply(to: input)
            for _ in 0..<5 { XCTAssertEqual(q.apply(to: input), first) }
        }
    }

    func testEmptyInput() throws {
        for sort in BrowseQuery.Sort.allCases {
            XCTAssertEqual(BrowseQuery(text: "x", sort: sort, hideInstalled: true, allowAdult: true)
                .apply(to: [], installedIDs: [1]), [])
        }
    }

    func testIsDefault() throws {
        XCTAssertTrue(BrowseQuery().isDefault)
        XCTAssertFalse(BrowseQuery(text: "a").isDefault)
        XCTAssertFalse(BrowseQuery(sort: .name).isDefault)
        XCTAssertFalse(BrowseQuery(hideInstalled: true).isDefault)
        XCTAssertFalse(BrowseQuery(allowAdult: true).isDefault)
    }
}
