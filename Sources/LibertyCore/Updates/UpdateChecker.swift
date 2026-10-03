import Foundation

/// Dotted numeric version ("v1.2.3", "0.4") that compares numerically, not as text.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]

    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        let core = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        let parts = core.split(separator: "-").first.map { $0.split(separator: ".") } ?? []
        let numbers = parts.compactMap { Int($0) }
        guard !numbers.isEmpty, numbers.count == parts.count else { return nil }
        components = numbers
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    public let notes: String
    public let pageURL: URL
    /// Zipped `Liberty Loader.app`, used for in-place updates.
    public let zipURL: URL?
    public let dmgURL: URL?

    public static func == (lhs: ReleaseInfo, rhs: ReleaseInfo) -> Bool {
        lhs.version == rhs.version && lhs.pageURL == rhs.pageURL
    }
}

/// Looks up the newest release on GitHub.
public enum UpdateChecker {
    public static let repository = "Joto3D/Liberty-Loader"

    public static func parseLatestRelease(_ data: Data) throws -> ReleaseInfo? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let version = AppVersion(tag),
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        if json["draft"] as? Bool == true || json["prerelease"] as? Bool == true { return nil }
        let assets = (json["assets"] as? [[String: Any]] ?? []).compactMap { asset -> (String, URL)? in
            guard let name = asset["name"] as? String,
                  let url = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)) else { return nil }
            return (name.lowercased(), url)
        }
        return ReleaseInfo(
            version: version,
            notes: json["body"] as? String ?? "",
            pageURL: page,
            zipURL: assets.first { $0.0.hasSuffix(".zip") }?.1,
            dmgURL: assets.first { $0.0.hasSuffix(".dmg") }?.1
        )
    }

    /// Returns the latest release when it is newer than `current`.
    public static func checkForUpdate(current: AppVersion, session: URLSession = .shared) async throws -> ReleaseInfo? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("LibertyLoader", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        // 404 simply means no release has been published yet.
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        guard let release = try parseLatestRelease(data), release.version > current else { return nil }
        return release
    }
}
