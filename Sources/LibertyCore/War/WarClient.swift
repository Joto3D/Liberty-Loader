import Foundation

/// Galactic War status from the community API at https://api.helldivers2.dev.
public struct WarStatus: Equatable, Sendable {
    public struct MajorOrder: Equatable, Sendable {
        public var title: String
        public var briefing: String
        public var expiration: Date?
    }

    public struct Planet: Equatable, Identifiable, Sendable {
        public var id: Int
        public var name: String
        public var faction: String
        /// 0…100
        public var liberation: Double
        public var players: Int
    }

    public var playerCount: Int?
    public var majorOrders: [MajorOrder]
    /// Active campaigns, most players first.
    public var planets: [Planet]
}

public enum WarClient {
    public static let base = URL(string: "https://api.helldivers2.dev/api/v1/")!

    public static func fetch(session: URLSession = .shared) async throws -> WarStatus {
        async let war = get("war", session: session)
        async let assignments = get("assignments", session: session)
        async let campaigns = get("campaigns", session: session)
        return parse(war: try? await war, assignments: try? await assignments, campaigns: try await campaigns)
    }

    static func get(_ path: String, session: URLSession) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
        // The API asks clients to identify themselves.
        request.setValue("LibertyLoader", forHTTPHeaderField: "X-Super-Client")
        request.setValue("https://github.com/Joto3D/Liberty-Loader", forHTTPHeaderField: "X-Super-Contact")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Locale.preferredLanguages.first ?? "en-US", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    /// Tolerant parsing: every field is optional, unknown shapes are skipped.
    public static func parse(war: Data?, assignments: Data?, campaigns: Data?) -> WarStatus {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        func date(_ any: Any?) -> Date? {
            guard let s = any as? String else { return nil }
            return iso.date(from: s) ?? isoPlain.date(from: s)
        }
        func number(_ any: Any?) -> Double? {
            (any as? NSNumber)?.doubleValue
        }

        var playerCount: Int?
        if let war, let json = try? JSONSerialization.jsonObject(with: war) as? [String: Any],
           let stats = json["statistics"] as? [String: Any] {
            playerCount = number(stats["playerCount"]).map { Int($0) }
        }

        var orders: [WarStatus.MajorOrder] = []
        if let assignments, let list = try? JSONSerialization.jsonObject(with: assignments) as? [[String: Any]] {
            orders = list.compactMap { item in
                let title = (item["title"] as? String) ?? ""
                let briefing = (item["briefing"] as? String) ?? (item["description"] as? String) ?? ""
                guard !(title.isEmpty && briefing.isEmpty) else { return nil }
                return .init(title: title.isEmpty ? "Major Order" : title, briefing: briefing, expiration: date(item["expiration"]))
            }
        }

        var planets: [WarStatus.Planet] = []
        if let campaigns, let list = try? JSONSerialization.jsonObject(with: campaigns) as? [[String: Any]] {
            planets = list.compactMap { item in
                guard let planet = item["planet"] as? [String: Any],
                      let name = planet["name"] as? String else { return nil }
                let index = number(planet["index"]).map { Int($0) } ?? (number(item["id"]).map { Int($0) } ?? name.hashValue)
                let health = number(planet["health"]) ?? 0
                let maxHealth = number(planet["maxHealth"]) ?? 0
                let liberation = maxHealth > 0 ? max(0, min(100, (maxHealth - health) / maxHealth * 100)) : 0
                let stats = planet["statistics"] as? [String: Any]
                let players = number(stats?["playerCount"]).map { Int($0) } ?? 0
                let faction = (item["faction"] as? String) ?? (planet["currentOwner"] as? String) ?? ""
                return .init(id: index, name: name, faction: faction, liberation: liberation, players: players)
            }
            .sorted { $0.players > $1.players }
        }
        return WarStatus(playerCount: playerCount, majorOrders: orders, planets: planets)
    }
}
