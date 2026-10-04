import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// How close the game's memory use is to crashing the Mac.
public enum MemoryLevel: Int, Comparable, Sendable {
    case normal, high, critical

    /// High at 1.5× the Mac's memory, critical at 2× – beyond that macOS swaps until the game dies.
    public init(footprint: UInt64, physical: UInt64) {
        if footprint >= physical * 2 {
            self = .critical
        } else if footprint >= physical * 3 / 2 {
            self = .high
        } else {
            self = .normal
        }
    }

    public static func < (lhs: MemoryLevel, rhs: MemoryLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Makes each warning level fire once per game session.
public struct MemoryAlertState: Equatable, Sendable {
    public private(set) var warned: MemoryLevel = .normal

    public init() {}

    /// The level to warn about now, or nil if the user was already warned about it (or something worse).
    public mutating func next(_ level: MemoryLevel) -> MemoryLevel? {
        guard level > warned else { return nil }
        warned = level
        return level
    }

    public mutating func reset() { warned = .normal }
}

public enum GameMemory {
    /// Memory used by the running Helldivers 2 process(es), as Activity Monitor counts it.
    public static func footprint() -> UInt64? {
        guard let output = try? Shell.run("/usr/bin/pgrep", ["-if", "helldivers2.exe"]), output.status == 0 else { return nil }
        let pids = output.output.split(whereSeparator: \.isNewline).compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        guard !pids.isEmpty else { return nil }
        return pids.reduce(UInt64(0)) { $0 + (footprint(pid: $1) ?? 0) }
    }

    static func footprint(pid: Int32) -> UInt64? {
        #if canImport(Darwin)
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        if result == 0 { return info.ri_phys_footprint }
        #endif
        // Fallback: resident size in KB (misses swapped memory, so it reads low).
        guard let ps = try? Shell.run("/bin/ps", ["-o", "rss=", "-p", String(pid)]),
              let kb = UInt64(ps.output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return kb * 1024
    }

    /// "18.4 GB"
    public static func format(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return gb.formatted(.number.precision(.fractionLength(1))) + " GB"
    }
}
