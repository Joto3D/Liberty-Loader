import Foundation
import CryptoKit

/// A compact identity for one Helldivers 2 install, used to notice game updates
/// that may break deployed mods.
///
/// Steam installs have an `appmanifest` with an authoritative `buildid`, so that
/// is preferred (`.buildID`). Installs without one (Obelisk) are identified by
/// the SHA-256 of `helldivers2.exe` (`.executableHash`).
///
/// Persist the fingerprint next to the deploy record when mods are deployed and
/// compare with `compare(to:)` on later launches.
///
/// Performance: hashing the ~29 MB executable is not free. Before calling
/// `of(_:)` on every launch, use the cheap path: `of(_:reusing:)` or
/// `executableUnchanged(since:in:)` check only size + modification date and skip
/// the hash entirely when those match the previously stored fingerprint.
public struct InstallFingerprint: Equatable, Sendable, Codable {
    public enum Kind: String, Equatable, Sendable, Codable {
        /// Steam `buildid` from the appmanifest.
        case buildID
        /// SHA-256 of the game executable.
        case executableHash
    }

    /// Result of comparing two fingerprints. Deliberately not a Bool: fingerprints
    /// of different kinds cannot be compared and callers must decide what to do.
    public enum Comparison: Equatable, Sendable {
        case same
        case changed
        /// One is a build id and the other a hash (e.g. the install switched
        /// source). Treat as "unknown", not as "changed" or "same".
        case notComparable
    }

    public let kind: Kind
    /// Steam build id; set when `kind == .buildID`.
    public let buildID: String?
    /// Lowercase hex SHA-256 of the executable; set when `kind == .executableHash`.
    public let sha256: String?
    /// Executable size in bytes at fingerprint time (cheap pre-check).
    public let executableSize: UInt64
    /// Executable modification date at fingerprint time (cheap pre-check).
    public let executableModified: Date

    /// Short stable string for logging and storing: the build id, or the first
    /// 16 hex characters of the digest.
    public var displayValue: String {
        switch kind {
        case .buildID: return buildID ?? ""
        case .executableHash: return String((sha256 ?? "").prefix(16))
        }
    }

    public init(kind: Kind, buildID: String?, sha256: String?,
                executableSize: UInt64, executableModified: Date) {
        self.kind = kind
        self.buildID = buildID
        self.sha256 = sha256
        self.executableSize = executableSize
        self.executableModified = executableModified
    }

    // MARK: Producing

    /// Fingerprints the install. Returns nil only when the executable cannot be read.
    /// Always hashes when no build id is available; see `of(_:reusing:)` to avoid that.
    public static func of(_ paths: GamePaths) -> InstallFingerprint? {
        of(paths, reusing: nil)
    }

    /// Like `of(_:)`, but if `previous` is a hash fingerprint whose executable size
    /// and mtime still match, returns it unchanged without reading the file body.
    /// This is the cheap path to call on every launch.
    public static func of(_ paths: GamePaths, reusing previous: InstallFingerprint?) -> InstallFingerprint? {
        guard let stat = executableStat(paths) else { return nil }
        // Probe readability even when a build id makes the hash unnecessary.
        guard let handle = try? FileHandle(forReadingFrom: paths.executableURL) else { return nil }
        try? handle.close()

        if paths.source.hasSteamAppManifest, let id = paths.buildID, !id.isEmpty {
            return InstallFingerprint(kind: .buildID, buildID: id, sha256: nil,
                                      executableSize: stat.size, executableModified: stat.modified)
        }
        if let prev = previous, prev.kind == .executableHash, prev.sha256 != nil,
           prev.executableSize == stat.size, prev.executableModified == stat.modified {
            return prev
        }
        guard let digest = sha256Hex(ofFileAt: paths.executableURL) else { return nil }
        return InstallFingerprint(kind: .executableHash, buildID: nil, sha256: digest,
                                  executableSize: stat.size, executableModified: stat.modified)
    }

    /// Cheap check (stat only, no hashing): true when the executable's size and
    /// modification date equal those recorded in `previous`, meaning it has almost
    /// certainly not changed. False when either differs or the file is unreadable;
    /// only then is a full `of(_:)` worth its cost.
    public static func executableUnchanged(since previous: InstallFingerprint, in paths: GamePaths) -> Bool {
        guard let stat = executableStat(paths) else { return false }
        return stat.size == previous.executableSize && stat.modified == previous.executableModified
    }

    // MARK: Comparing

    /// Compares this (current) fingerprint with a previously stored one.
    public func compare(to other: InstallFingerprint) -> Comparison {
        guard kind == other.kind else { return .notComparable }
        switch kind {
        case .buildID: return buildID == other.buildID ? .same : .changed
        case .executableHash: return sha256 == other.sha256 ? .same : .changed
        }
    }

    /// Convenience: true only when the fingerprints are comparable and differ.
    /// `.notComparable` yields false, so prefer `compare(to:)` if that matters.
    // Deliberately no `differs(from:) -> Bool`. A Bool has nowhere to put
    // `.notComparable`, and the honest answer there is "I cannot tell", not
    // "no change" — which is what a Bool would imply. This machine shows why:
    // the same game is reachable both as a CrossOver bottle (build id) and as
    // an Obelisk install (executable hash), so switching between them compares
    // a build id to a hash. A Bool would report "unchanged" and the app would
    // quietly keep stale mods deployed. Use `compare(to:)` and handle all three.

    // MARK: Internals

    private static func executableStat(_ paths: GamePaths) -> (size: UInt64, modified: Date)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: paths.executableURL.path),
              (attrs[.type] as? FileAttributeType) == .typeRegular,
              let size = (attrs[.size] as? NSNumber)?.uint64Value,
              let modified = attrs[.modificationDate] as? Date else { return nil }
        return (size, modified)
    }

    /// Streams the file in 1 MiB chunks; never holds the whole file in memory.
    static func sha256Hex(ofFileAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        } catch { return nil }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
