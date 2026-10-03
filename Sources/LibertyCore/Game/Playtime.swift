import Foundation

/// Counts time spent in Helldivers 2, based on periodic "is the game running?" checks.
public struct PlaytimeRecord: Codable, Equatable, Sendable {
    public var totalSeconds: TimeInterval = 0
    public var sessionCount = 0
    public var lastSessionSeconds: TimeInterval = 0
    public var sessionStart: Date?
    /// Last time the game was seen running; closes a session if Liberty Loader quit mid-game.
    public var lastSeenRunning: Date?

    public init() {}

    /// Feeds one observation. Returns true when the record changed and should be saved.
    @discardableResult
    public mutating func update(isRunning: Bool, now: Date = Date()) -> Bool {
        if isRunning {
            if sessionStart == nil {
                sessionStart = now
                sessionCount += 1
            }
            lastSeenRunning = now
            return true
        }
        guard let start = sessionStart else { return false }
        let end = lastSeenRunning ?? start
        lastSessionSeconds = max(0, end.timeIntervalSince(start))
        totalSeconds += lastSessionSeconds
        sessionStart = nil
        lastSeenRunning = nil
        return true
    }

    /// Total including the session in progress.
    public func total(now: Date = Date()) -> TimeInterval {
        guard let start = sessionStart else { return totalSeconds }
        return totalSeconds + max(0, now.timeIntervalSince(start))
    }

    public static func format(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}

public final class PlaytimeStore {
    let fileURL: URL
    public private(set) var record: PlaytimeRecord

    public init(rootURL: URL = ModStore.defaultRoot) {
        fileURL = rootURL.appendingPathComponent("playtime.json")
        record = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(PlaytimeRecord.self, from: $0) } ?? PlaytimeRecord()
    }

    /// Returns true when the record changed.
    @discardableResult
    public func update(isRunning: Bool, now: Date = Date()) -> Bool {
        guard record.update(isRunning: isRunning, now: now) else { return false }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(record).write(to: fileURL, options: .atomic)
        return true
    }
}

/// Notices when a launch never results in a running game (Steam stuck, bottle hung).
public struct LaunchWatchdog: Equatable, Sendable {
    public var launchedAt: Date?
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 180) {
        self.timeout = timeout
    }

    public mutating func didLaunch(at date: Date = Date()) { launchedAt = date }
    public mutating func reset() { launchedAt = nil }

    /// True when a launch is pending, the game still isn't running and the timeout has passed.
    public mutating func check(gameRunning: Bool, now: Date = Date()) -> Bool {
        guard let launchedAt else { return false }
        if gameRunning {
            self.launchedAt = nil
            return false
        }
        return now.timeIntervalSince(launchedAt) > timeout
    }
}
