import Foundation

public struct Backup: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var originalPath: String
    public var label: String
    public var createdAt: Date
    /// The very first copy taken of this file — the "Restore original" target. Never pruned.
    public var isOriginal: Bool
    var storedName: String
}

/// Copies config files aside before Liberty Loader changes them.
public final class BackupManager {
    public let directory: URL
    var indexURL: URL { directory.appendingPathComponent("backups.json") }
    public private(set) var backups: [Backup] = []
    /// Non-original backups kept per file.
    public var keepPerFile = 10

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL) {
            backups = try Self.decoder.decode([Backup].self, from: data)
        }
    }

    @discardableResult
    public func backup(_ file: URL, label: String) throws -> Backup? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return nil }
        let path = file.standardizedFileURL.path
        let id = UUID()
        let backup = Backup(
            id: id,
            originalPath: path,
            label: label,
            createdAt: Date(),
            isOriginal: !backups.contains { $0.originalPath == path && $0.isOriginal },
            storedName: "\(id.uuidString)-\(file.lastPathComponent)"
        )
        try fm.copyItem(at: file, to: directory.appendingPathComponent(backup.storedName))
        backups.append(backup)
        prune(path)
        try save()
        return backup
    }

    public func restore(_ backup: Backup) throws {
        let target = URL(fileURLWithPath: backup.originalPath)
        let source = directory.appendingPathComponent(backup.storedName)
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw LibertyError.backupNotFound }
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.copyItem(at: source, to: target)
        LibertyLog.shared.info("Restored \(target.path) from backup \(backup.label)")
    }

    public func original(for file: URL) -> Backup? {
        let path = file.standardizedFileURL.path
        return backups.first { $0.originalPath == path && $0.isOriginal }
    }

    public func restoreOriginal(of file: URL) throws {
        guard let backup = original(for: file) else { throw LibertyError.backupNotFound }
        try restore(backup)
    }

    private func prune(_ path: String) {
        let regular = backups.filter { $0.originalPath == path && !$0.isOriginal }.sorted { $0.createdAt < $1.createdAt }
        for old in regular.dropLast(keepPerFile) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(old.storedName))
            backups.removeAll { $0.id == old.id }
        }
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(backups).write(to: indexURL, options: .atomic)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
