import Foundation

/// Heuristic crash detection: the game vanished soon after it appeared, without the user stopping it.
public struct CrashDetector: Equatable, Sendable {
    public var minimumHealthySession: TimeInterval
    public private(set) var startedAt: Date?
    private var userStopped = false

    public init(minimumHealthySession: TimeInterval = 90) {
        self.minimumHealthySession = minimumHealthySession
    }

    public mutating func gameStarted(at date: Date = Date()) {
        startedAt = date
        userStopped = false
    }

    /// Call before Liberty Loader stops the game itself (Force Quit), so that isn't reported.
    public mutating func userWillStopGame() {
        userStopped = true
    }

    /// Returns true when the session that just ended looks like a crash.
    public mutating func gameStopped(at date: Date = Date()) -> Bool {
        defer { startedAt = nil; userStopped = false }
        guard let startedAt, !userStopped else { return false }
        return date.timeIntervalSince(startedAt) < minimumHealthySession
    }

    /// Crash dumps or error logs written to the game's AppData folder since `since`, newest first.
    public static func recentCrashFiles(in directory: URL, since: Date) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else {
            return []
        }
        var found: [(URL, Date)] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent.lowercased()
            guard name.hasSuffix(".dmp") || name.contains("crash") || name.contains("error") else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let modified = values?.contentModificationDate, modified >= since else { continue }
            found.append((url, modified))
        }
        return found.sorted { $0.1 > $1.1 }.map(\.0)
    }
}

extension GamePaths {
    /// `%APPDATA%\Arrowhead\Helldivers2`
    public var appDataDir: URL { userSettingsURL.deletingLastPathComponent() }
}
