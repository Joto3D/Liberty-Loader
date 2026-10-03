import Foundation

/// Minimal client for the Nexus Mods public API (https://app.swaggerhub.com/apis-docs/NexusMods/nexus-mods_public_api_params_in_form_data/1.0).
/// Requires the user's personal API key from nexusmods.com → Settings → API Keys.
public struct NexusClient {
    public static let gameDomain = "helldivers2"

    public struct ModInfo: Decodable, Equatable, Sendable {
        public let name: String?
        public let summary: String?
        public let version: String?
        public let picture_url: String?
    }

    public struct FileInfo: Decodable, Equatable, Sendable {
        public let name: String?
        public let version: String?
        public let file_name: String?
    }

    struct DownloadLink: Decodable {
        let URI: String
    }

    public enum ClientError: Error, LocalizedError {
        case missingAPIKey
        case http(Int)
        case noDownloadLink

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey: return String(localized: "Add your Nexus Mods API key in Settings first.")
            case .http(401): return String(localized: "Nexus Mods rejected the API key. Check it in Settings.")
            case .http(403): return String(localized: "Nexus Mods refused the download. Free accounts must use the “Mod Manager Download” button on the website.")
            case .http(let code): return String(localized: "Nexus Mods returned an error (\(code)).")
            case .noDownloadLink: return String(localized: "Nexus Mods did not return a download link.")
            }
        }
    }

    public let apiKey: String
    public var session: URLSession = .shared
    let base = URL(string: "https://api.nexusmods.com/v1/")!

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public func mod(_ modID: Int, game: String = gameDomain) async throws -> ModInfo {
        try await get("games/\(game)/mods/\(modID).json")
    }

    public func file(_ fileID: Int, mod modID: Int, game: String = gameDomain) async throws -> FileInfo {
        try await get("games/\(game)/mods/\(modID)/files/\(fileID).json")
    }

    public func downloadURL(for link: NXMLink) async throws -> URL {
        var path = "games/\(link.game)/mods/\(link.modID)/files/\(link.fileID)/download_link.json"
        if let key = link.key, let expires = link.expires {
            path += "?key=\(key)&expires=\(expires)"
        }
        let links: [DownloadLink] = try await get(path)
        guard let first = links.first, let url = URL(string: first.URI) else { throw ClientError.noDownloadLink }
        return url
    }

    /// Downloads a file to a temporary location, keeping its original file name (and so its extension).
    public func download(_ url: URL) async throws -> URL {
        let (temp, response) = try await session.download(from: url)
        if let code = (response as? HTTPURLResponse)?.statusCode, code != 200 { throw ClientError.http(code) }
        let name = (response.suggestedFilename ?? url.lastPathComponent).removingPercentEncoding ?? url.lastPathComponent
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(name)
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard !apiKey.isEmpty else { throw ClientError.missingAPIKey }
        guard let url = URL(string: path, relativeTo: base) else { throw ClientError.noDownloadLink }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("LibertyLoader", forHTTPHeaderField: "Application-Name")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let code = (response as? HTTPURLResponse)?.statusCode, code != 200 { throw ClientError.http(code) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
