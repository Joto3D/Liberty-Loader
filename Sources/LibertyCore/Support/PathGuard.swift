import Foundation

/// Refuses file operations outside a set of allowed directories, so a bug can never
/// write or delete anything outside the bottle or Liberty Loader's own folder.
public struct PathGuard: Sendable {
    public let allowedRoots: [URL]

    public init(allowedRoots: [URL]) {
        self.allowedRoots = allowedRoots.map { $0.standardizedFileURL }
    }

    public func isAllowed(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return allowedRoots.contains { root in
            path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/")
        }
    }

    public func check(_ url: URL) throws {
        guard isAllowed(url) else { throw LibertyError.pathNotAllowed(url.path) }
    }
}

public enum LibertyError: Error, LocalizedError, Equatable {
    case pathNotAllowed(String)
    case crossOverNotFound
    case gameNotFound
    case archiveExtractionFailed(String)
    case unsupportedArchive(String)
    case noPatchFiles
    case windowsProgram
    case configNotFound(String)
    case backupNotFound

    public var errorDescription: String? {
        switch self {
        case .pathNotAllowed(let path): return String(localized: "Refusing to modify a file outside the bottle: \(path)")
        case .crossOverNotFound: return String(localized: "CrossOver was not found. Install it or choose its location in Settings.")
        case .gameNotFound: return String(localized: "Helldivers 2 was not found in any CrossOver bottle.")
        case .archiveExtractionFailed(let msg): return String(localized: "Could not extract the mod archive: \(msg)")
        case .unsupportedArchive(let ext): return String(localized: "Unsupported archive type: .\(ext)")
        case .noPatchFiles: return String(localized: "This mod does not contain any Helldivers 2 patch files.")
        case .windowsProgram: return String(localized: "This is a Windows program (for example a mod manager), not a mod. You don't need it: Liberty Loader does that job on your Mac. Download the mod itself instead.")
        case .configNotFound(let path): return String(localized: "Config file not found: \(path)")
        case .backupNotFound: return String(localized: "No backup is available for this file.")
        }
    }
}
