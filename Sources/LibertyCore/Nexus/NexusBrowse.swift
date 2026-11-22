import Foundation

/// A mod as shown in the browser (Nexus "trending"/"latest" lists and search results).
public struct NexusModSummary: Decodable, Identifiable, Equatable, Sendable {
    public let mod_id: Int
    public let name: String?
    public let summary: String?
    public let picture_url: String?
    public let endorsement_count: Int?
    public let author: String?
    public let version: String?
    public let available: Bool?
    public let contains_adult_content: Bool?

    public var id: Int { mod_id }
    public var pictureURL: URL? { picture_url.flatMap(URL.init(string:)) }
    public var pageURL: URL {
        URL(string: "https://www.nexusmods.com/\(NexusClient.gameDomain)/mods/\(mod_id)")!
    }

    public init(modID: Int, name: String?, summary: String?, pictureURL: String?, endorsements: Int?, author: String?, version: String?,
                available: Bool? = true, containsAdultContent: Bool? = false) {
        mod_id = modID
        self.name = name
        self.summary = summary
        picture_url = pictureURL
        endorsement_count = endorsements
        self.author = author
        self.version = version
        self.available = available
        contains_adult_content = containsAdultContent
    }

    /// Hidden or adult mods are never shown.
    public var isListable: Bool { available != false && contains_adult_content != true && name != nil }
}

public struct NexusFile: Decodable, Equatable, Sendable {
    public let file_id: Int
    public let name: String?
    public let version: String?
    public let category_name: String?
    public let is_primary: Bool?
    public let uploaded_timestamp: Int?
}

struct NexusFileList: Decodable {
    let files: [NexusFile]
}

public struct NexusUser: Decodable, Equatable, Sendable {
    public let name: String?
    public let is_premium: Bool?
}

/// One page of a browse list. `hasMore` comes from the list itself, never from a count guess.
public struct NexusPage: Equatable, Sendable {
    public let mods: [NexusModSummary]
    public let hasMore: Bool
    /// Server-side total for the query (all matching mods, before client filtering). 0 when unknown.
    public let totalCount: Int

    public init(mods: [NexusModSummary], hasMore: Bool, totalCount: Int = 0) {
        self.mods = mods
        self.hasMore = hasMore
        self.totalCount = totalCount
    }

    /// Slices an already-filtered list. Out-of-range pages are empty with `hasMore == false`.
    static func slice(_ all: [NexusModSummary], page: Int, pageSize: Int) -> NexusPage {
        guard page >= 0, pageSize > 0 else { return NexusPage(mods: [], hasMore: false) }
        let (start, overflow) = page.multipliedReportingOverflow(by: pageSize)
        guard !overflow, start < all.count else { return NexusPage(mods: [], hasMore: false) }
        let end = min(all.count, start + pageSize)
        return NexusPage(mods: Array(all[start..<end]), hasMore: end < all.count)
    }
}

public enum NexusList: String, CaseIterable, Sendable {
    case trending
    case latestAdded = "latest_added"
    case latestUpdated = "latest_updated"
}

/// Sort orders for the paged v2 browse. Raw values are the GraphQL `ModsSort` field names.
public enum NexusSort: String, CaseIterable, Sendable {
    case endorsements, downloads, createdAt, updatedAt, name

    /// Natural direction: popularity and recency descend, names ascend.
    public var direction: String { self == .name ? "ASC" : "DESC" }

    /// The `sort` GraphQL variable: `[{ <field>: { direction: ... } }]`.
    public var variable: [[String: Any]] { [[rawValue: ["direction": direction]]] }
}

public enum NexusBrowseError: Error, LocalizedError {
    case graphQL(String)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .graphQL(let message): return String(localized: "Nexus Mods rejected the browse query: \(message)")
        case .malformedResponse: return String(localized: "Nexus Mods returned an unexpected browse response.")
        }
    }
}

extension NexusClient {
    public func list(_ list: NexusList, game: String = NexusClient.gameDomain) async throws -> [NexusModSummary] {
        let mods: [NexusModSummary] = try await get("games/\(game)/mods/\(list.rawValue).json")
        return mods.filter(\.isListable)
    }

    /// One page of a browse list. The v1 list endpoint does not page, so this fetches the whole
    /// list once and slices it. The fetched list is cached inside this client instance (and any
    /// copies of it) so later pages do not refetch; use a new `NexusClient` to refresh.
    @available(*, deprecated, message: "The v1 list endpoint returns about ten mods and cannot page, so this can never show more. Use browse(sort:offset:count:game:).")
    public func list(_ list: NexusList, page: Int, pageSize: Int, game: String = NexusClient.gameDomain) async throws -> NexusPage {
        let key = "\(game)/\(list.rawValue)"
        let all: [NexusModSummary]
        if let cached = await listCache.value(for: key) {
            all = cached
        } else {
            all = try await self.list(list, game: game)
            await listCache.store(all, for: key)
        }
        return NexusPage.slice(all, page: page, pageSize: pageSize)
    }

    /// One server-side page of the v2 GraphQL mod list. `hasMore` is computed from the unfiltered
    /// node count against `totalCount`, so a page that is entirely filtered out does not stall paging.
    public func browse(sort: NexusSort, offset: Int, count: Int, game: String = NexusClient.gameDomain) async throws -> NexusPage {
        let request = try browseRequest(sort: sort, offset: offset, count: count, game: game)
        let (data, response) = try await session.data(for: request)
        if let code = (response as? HTTPURLResponse)?.statusCode, code != 200 { throw ClientError.http(code) }
        return try Self.parseBrowse(data, offset: offset)
    }

    static let browseQuery = """
    query Browse($filter: ModsFilter, $sort: [ModsSort!], $offset: Int, $count: Int) {
      mods(filter: $filter, sort: $sort, offset: $offset, count: $count) {
        totalCount
        nodes { modId name summary pictureUrl endorsements version adultContent status uploader { name } }
      }
    }
    """

    static func browseVariables(sort: NexusSort, offset: Int, count: Int, game: String) -> [String: Any] {
        [
            "count": count,
            "offset": offset,
            "filter": ["gameDomainName": [["value": game, "op": "EQUALS"]]],
            "sort": sort.variable,
        ]
    }

    func browseRequest(sort: NexusSort, offset: Int, count: Int, game: String) throws -> URLRequest {
        guard let request = graphQLRequest(query: Self.browseQuery,
                                           variables: Self.browseVariables(sort: sort, offset: offset, count: count, game: game))
        else { throw NexusBrowseError.malformedResponse }
        return request
    }

    /// Parses a `mods` ModPage response. Throws on a GraphQL `errors` array or a missing `mods` node.
    static func parseBrowse(_ data: Data, offset: Int) throws -> NexusPage {
        if let message = graphQLErrorMessage(in: data) { throw NexusBrowseError.graphQL(message) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mods = (json["data"] as? [String: Any])?["mods"] as? [String: Any],
              let nodes = mods["nodes"] as? [[String: Any]] else { throw NexusBrowseError.malformedResponse }
        let total = mods["totalCount"] as? Int ?? 0
        let all = nodes.compactMap(summary(from:))
        return NexusPage(mods: all.filter(\.isListable),
                         hasMore: offset + nodes.count < total,
                         totalCount: total)
    }

    /// Requirements for a mod before it is installed, via the existing v2 lookup.
    /// Throws `ClientError.requirementsUnavailable` when the API is unreachable or its schema changed.
    public func requirementsBeforeInstall(modID: Int, game: String = NexusClient.gameDomain) async throws -> [NexusRequirement] {
        guard let found = await requirements(modID: modID, game: game) else { throw ClientError.requirementsUnavailable }
        return found
    }

    public func files(modID: Int, game: String = NexusClient.gameDomain) async throws -> [NexusFile] {
        let list: NexusFileList = try await get("games/\(game)/mods/\(modID)/files.json")
        return list.files
    }

    public func validateUser() async throws -> NexusUser {
        try await get("users/validate.json")
    }

    /// The file a one-click install should use: the primary file, else the newest MAIN file.
    public static func preferredFile(_ files: [NexusFile]) -> NexusFile? {
        if let primary = files.first(where: { $0.is_primary == true }) { return primary }
        let main = files.filter { $0.category_name?.uppercased() == "MAIN" }
        return (main.isEmpty ? files : main).max { ($0.uploaded_timestamp ?? 0) < ($1.uploaded_timestamp ?? 0) }
    }

    /// Searches mods by name through the Nexus v2 GraphQL API.
    /// The schema is outside our control, so any failure returns nil and callers fall back to local filtering.
    public func search(_ term: String, game: String = NexusClient.gameDomain, count: Int = 30) async -> [NexusModSummary]? {
        // `adultContent` lets search hide the same mods the browse lists hide.
        // The field name is taken from the v2 schema, which is outside our
        // control: if it is ever wrong or removed, GraphQL rejects the whole
        // query and search would stop working altogether. So ask for it, and
        // if the request fails, ask again without it. Losing the adult filter
        // on search is a much smaller harm than losing search.
        for fields in [Self.searchFields(includeAdult: true), Self.searchFields(includeAdult: false)] {
            if let found = await searchOnce(term: term, game: game, count: count, fields: fields) {
                return found
            }
        }
        return nil
    }

    private static func searchFields(includeAdult: Bool) -> String {
        "modId name summary pictureUrl endorsements version\(includeAdult ? " adultContent" : "") uploader { name }"
    }

    private func searchOnce(term: String, game: String, count: Int, fields: String) async -> [NexusModSummary]? {
        let query = """
        query Search($filter: ModsFilter, $count: Int) {
          mods(filter: $filter, count: $count) {
            nodes { \(fields) }
          }
        }
        """
        let variables: [String: Any] = [
            "count": count,
            "filter": [
                "gameDomainName": [["value": game, "op": "EQUALS"]],
                "name": [["value": term, "op": "WILDCARD"]],
            ],
        ]
        guard let request = graphQLRequest(query: query, variables: variables),
              let result = try? await session.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        // GraphQL answers an unknown field with 200 and an `errors` array, so a
        // status code alone does not mean the query was understood.
        if Self.graphQLErrorMessage(in: result.0) != nil { return nil }
        return Self.parseSearch(result.0)?.filter(\.isListable)
    }

    /// A v2 GraphQL POST with the standard headers. Nil only if the body cannot be encoded.
    func graphQLRequest(query: String, variables: [String: Any]) -> URLRequest? {
        guard let url = URL(string: "https://api.nexusmods.com/v2/graphql"),
              let body = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("LibertyLoader", forHTTPHeaderField: "Application-Name")
        if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "apikey") }
        return request
    }

    /// The first message of a non-empty GraphQL `errors` array, else nil.
    static func graphQLErrorMessage(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = json["errors"] as? [[String: Any]], !errors.isEmpty else { return nil }
        return errors.first?["message"] as? String ?? "unknown GraphQL error"
    }

    static func summary(from node: [String: Any]) -> NexusModSummary? {
        guard let id = node["modId"] as? Int else { return nil }
        return NexusModSummary(
            modID: id,
            name: node["name"] as? String,
            summary: node["summary"] as? String,
            pictureURL: node["pictureUrl"] as? String,
            endorsements: node["endorsements"] as? Int,
            author: (node["uploader"] as? [String: Any])?["name"] as? String,
            version: node["version"] as? String,
            // Absent stays nil so behaviour is unchanged for responses without these fields.
            available: (node["status"] as? String).map { $0.lowercased() == "published" },
            containsAdultContent: node["adultContent"] as? Bool
        )
    }

    static func parseSearch(_ data: Data) -> [NexusModSummary]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataNode = json["data"] as? [String: Any],
              let mods = dataNode["mods"] as? [String: Any],
              let nodes = mods["nodes"] as? [[String: Any]] else { return nil }
        return nodes.compactMap(summary(from:))
    }
}

extension Array where Element == NexusRequirement {
    /// Requirements that mean this mod runs code in the game, as opposed to
    /// replacing assets. Bingus Shared Loader and HD2Runtime exist to patch
    /// the running game, so needing either is the pre-install equivalent of
    /// CosmeticCheck's runtimeDependency signal. Mod managers are excluded:
    /// Liberty Loader replaces them on the Mac.
    public var runtimeRequirements: [NexusRequirement] {
        filter { requirement in
            guard !requirement.isModManager else { return false }
            let name = requirement.name.lowercased()
            return ["bingus", "hd2runtime", "hd2 runtime"].contains { name.contains($0) }
        }
    }

    public var needsModRuntime: Bool { !runtimeRequirements.isEmpty }
}
