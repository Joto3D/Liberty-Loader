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

    public init(modID: Int, name: String?, summary: String?, pictureURL: String?, endorsements: Int?, author: String?, version: String?) {
        mod_id = modID
        self.name = name
        self.summary = summary
        picture_url = pictureURL
        endorsement_count = endorsements
        self.author = author
        self.version = version
        available = true
        contains_adult_content = false
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

public enum NexusList: String, CaseIterable, Sendable {
    case trending
    case latestAdded = "latest_added"
    case latestUpdated = "latest_updated"
}

extension NexusClient {
    public func list(_ list: NexusList, game: String = NexusClient.gameDomain) async throws -> [NexusModSummary] {
        let mods: [NexusModSummary] = try await get("games/\(game)/mods/\(list.rawValue).json")
        return mods.filter(\.isListable)
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
        let query = """
        query Search($filter: ModsFilter, $count: Int) {
          mods(filter: $filter, count: $count) {
            nodes { modId name summary pictureUrl endorsements version uploader { name } }
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
        guard let url = URL(string: "https://api.nexusmods.com/v2/graphql"),
              let body = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("LibertyLoader", forHTTPHeaderField: "Application-Name")
        if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "apikey") }
        guard let result = try? await session.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return Self.parseSearch(result.0)
    }

    static func parseSearch(_ data: Data) -> [NexusModSummary]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataNode = json["data"] as? [String: Any],
              let mods = dataNode["mods"] as? [String: Any],
              let nodes = mods["nodes"] as? [[String: Any]] else { return nil }
        return nodes.compactMap { node in
            guard let id = node["modId"] as? Int else { return nil }
            return NexusModSummary(
                modID: id,
                name: node["name"] as? String,
                summary: node["summary"] as? String,
                pictureURL: node["pictureUrl"] as? String,
                endorsements: node["endorsements"] as? Int,
                author: (node["uploader"] as? [String: Any])?["name"] as? String,
                version: node["version"] as? String
            )
        }
    }
}
