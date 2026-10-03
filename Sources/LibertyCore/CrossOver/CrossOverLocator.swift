import Foundation

public struct CrossOverInstall: Equatable, Sendable {
    public let appURL: URL
    public let version: String?

    public var binDirectory: URL { appURL.appendingPathComponent("Contents/SharedSupport/CrossOver/bin") }
    public var wineURL: URL { binDirectory.appendingPathComponent("wine") }

    public var majorVersion: Int? {
        version.flatMap { $0.split(separator: ".").first }.flatMap { Int($0) }
    }

    /// Helldivers 2 needs CrossOver 24 or newer.
    public static let minimumMajorVersion = 24
    public var isSupportedVersion: Bool { (majorVersion ?? 0) >= Self.minimumMajorVersion }
}

public enum CrossOverLocator {
    public static var defaultCandidates: [URL] {
        [
            URL(fileURLWithPath: "/Applications/CrossOver.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/CrossOver.app"),
        ]
    }

    public static func locate(preferred: URL? = nil, candidates: [URL] = defaultCandidates) -> CrossOverInstall? {
        for url in [preferred].compactMap({ $0 }) + candidates {
            if let install = inspect(url) { return install }
        }
        return nil
    }

    public static func inspect(_ appURL: URL) -> CrossOverInstall? {
        let install = CrossOverInstall(appURL: appURL, version: readVersion(appURL))
        guard FileManager.default.fileExists(atPath: install.wineURL.path) else { return nil }
        return install
    }

    static func readVersion(_ appURL: URL) -> String? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return plist["CFBundleShortVersionString"] as? String
    }
}
