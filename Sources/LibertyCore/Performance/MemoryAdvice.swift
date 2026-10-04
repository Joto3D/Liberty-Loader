import Foundation

/// Helldivers 2 can use well over 16 GB; smaller Macs swap and stutter.
public enum MemoryAdvice {
    public static func isLowMemory(bytes: UInt64) -> Bool {
        bytes <= 16 * 1_073_741_824
    }

    /// The settings that cut the game's memory use the most.
    public static let lowMemorySettings: [String: String] = [
        "texture_quality": "0",
        "terrain_quality": "0",
        "particle_quality": "0",
    ]
}
