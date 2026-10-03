import Foundation

/// Another mod (or external tool) a Nexus mod says it needs.
public struct NexusRequirement: Codable, Equatable, Hashable, Sendable {
    public var modID: Int?
    public var name: String
    public var url: String?
    public var isExternal: Bool
    public var notes: String?

    public init(modID: Int?, name: String, url: String?, isExternal: Bool, notes: String?) {
        self.modID = modID
        self.name = name
        self.url = url
        self.isExternal = isExternal
        self.notes = notes
    }

    /// Windows mod managers (like "HD2 Mod Manager", Nexus mod 109) that many mods list as a requirement.
    /// Liberty Loader does their job on the Mac, so they are never needed.
    public var isModManager: Bool {
        if modID == 109 { return true }
        let lowered = name.lowercased()
        return lowered.contains("mod manager") || lowered.contains("modmanager")
    }

    public var pageURL: URL? {
        if let url, let parsed = URL(string: url) { return parsed }
        return modID.flatMap { URL(string: "https://www.nexusmods.com/\(NexusClient.gameDomain)/mods/\($0)") }
    }
}

extension NexusClient {
    /// The mod's requirements from the Nexus v2 GraphQL API. Returns nil when the API is unavailable
    /// or its schema changed; callers then link to the mod page instead.
    public func requirements(modID: Int, game: String = NexusClient.gameDomain) async -> [NexusRequirement]? {
        let query = """
        query Requirements($ids: [CompositeDomainWithIdInput!]!) {
          legacyModsByDomain(ids: $ids) {
            nodes {
              modId
              modRequirements {
                nexusRequirements { nodes { modId modName url notes externalRequirement } }
              }
            }
          }
        }
        """
        let variables: [String: Any] = ["ids": [["gameDomain": game, "modId": modID]]]
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
        return Self.parseRequirements(result.0)
    }

    static func parseRequirements(_ data: Data) -> [NexusRequirement]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let root = json["data"] as? [String: Any],
              let mods = root["legacyModsByDomain"] as? [String: Any],
              let modNodes = mods["nodes"] as? [[String: Any]] else { return nil }
        guard let first = modNodes.first else { return [] }
        let requirements = (first["modRequirements"] as? [String: Any])?["nexusRequirements"] as? [String: Any]
        let nodes = requirements?["nodes"] as? [[String: Any]] ?? []
        return nodes.compactMap { node in
            let name = (node["modName"] as? String) ?? ""
            guard !name.isEmpty else { return nil }
            let id: Int? = (node["modId"] as? Int) ?? (node["modId"] as? String).flatMap(Int.init)
            return NexusRequirement(
                modID: id,
                name: name,
                url: node["url"] as? String,
                isExternal: (node["externalRequirement"] as? Bool) ?? false,
                notes: node["notes"] as? String
            )
        }
    }
}
