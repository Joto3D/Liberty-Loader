import Foundation

/// A Nexus Mods "Mod Manager Download" link, e.g.
/// `nxm://helldivers2/mods/123/files/456?key=abc&expires=1700000000&user_id=42`.
public struct NXMLink: Equatable, Sendable {
    public let game: String
    public let modID: Int
    public let fileID: Int
    /// One-time download key (free accounts); premium accounts can download without it.
    public let key: String?
    public let expires: String?

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "nxm", let host = url.host else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 4, parts[0] == "mods", parts[2] == "files",
              let mod = Int(parts[1]), let file = Int(parts[3]) else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        game = host.lowercased()
        modID = mod
        fileID = file
        key = query.first { $0.name == "key" }?.value
        expires = query.first { $0.name == "expires" }?.value
    }
}
