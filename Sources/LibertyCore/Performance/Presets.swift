import Foundation

/// A bundle of game and bottle settings tuned for a performance target.
public struct PerformancePreset: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    /// `user_settings.config` keys. Keys missing from the user's file are skipped and reported.
    public let gameSettings: [String: String]
    public let graphicsBackend: BottleConfig.GraphicsBackend
    public let msync: Bool
    /// Only set by custom presets; nil leaves the bottle setting unchanged.
    public var esync: Bool? = nil
    public var metalHUD: Bool? = nil

    public static let ultraLow = PerformancePreset(
        id: "ultra-low",
        name: "Ultra Low",
        summary: "Below the game's lowest settings, like the Ultimate Performance mod. Half resolution and every effect off, for weak Macs or the highest FPS.",
        gameSettings: [
            "render_resolution_scale": "0.5",
            "upscaling_quality": "0",
            "shadow_quality": "0",
            "particle_quality": "0",
            "ambient_occlusion": "false",
            "screen_space_global_illumination": "false",
            "volumetric_clouds_quality": "0",
            "volumetric_fog_quality": "0",
            "reflection_quality": "0",
            "lighting_quality": "0",
            "terrain_quality": "0",
            "texture_quality": "0",
            "depth_of_field": "false",
            "motion_blur": "false",
            "bloom": "false",
            "vsync": "false",
            "max_fps": "60",
        ],
        graphicsBackend: .d3dmetal,
        msync: true
    )

    public static let maxPerformance = PerformancePreset(
        id: "max-performance",
        name: "Max Performance",
        summary: "For base M1/M2/M3 chips and 8–16 GB Macs. Lowest shadows and particles, heavy FSR upscaling, 30 FPS cap for stable frame times.",
        gameSettings: [
            "render_resolution_scale": "0.6",
            "upscaling_quality": "0",
            "shadow_quality": "0",
            "particle_quality": "0",
            "ambient_occlusion": "false",
            "screen_space_global_illumination": "false",
            "volumetric_clouds_quality": "0",
            "volumetric_fog_quality": "0",
            "reflection_quality": "0",
            "lighting_quality": "0",
            "terrain_quality": "0",
            "texture_quality": "1",
            "depth_of_field": "false",
            "motion_blur": "false",
            "bloom": "false",
            "vsync": "false",
            "max_fps": "30",
        ],
        graphicsBackend: .d3dmetal,
        msync: true
    )

    public static let balanced = PerformancePreset(
        id: "balanced",
        name: "Balanced",
        summary: "For Pro chips with 16–32 GB. Medium shadows, light upscaling, 60 FPS cap.",
        gameSettings: [
            "render_resolution_scale": "0.75",
            "upscaling_quality": "1",
            "shadow_quality": "1",
            "particle_quality": "1",
            "ambient_occlusion": "true",
            "screen_space_global_illumination": "false",
            "volumetric_clouds_quality": "1",
            "volumetric_fog_quality": "1",
            "reflection_quality": "1",
            "lighting_quality": "1",
            "terrain_quality": "1",
            "texture_quality": "2",
            "depth_of_field": "false",
            "motion_blur": "false",
            "bloom": "true",
            "vsync": "false",
            "max_fps": "60",
        ],
        graphicsBackend: .d3dmetal,
        msync: true
    )

    public static let quality = PerformancePreset(
        id: "quality",
        name: "Quality",
        summary: "For Max/Ultra chips. High settings with native-ish resolution.",
        gameSettings: [
            "render_resolution_scale": "1.0",
            "upscaling_quality": "2",
            "shadow_quality": "2",
            "particle_quality": "2",
            "ambient_occlusion": "true",
            "screen_space_global_illumination": "true",
            "volumetric_clouds_quality": "2",
            "volumetric_fog_quality": "2",
            "reflection_quality": "2",
            "lighting_quality": "2",
            "terrain_quality": "2",
            "texture_quality": "3",
            "depth_of_field": "true",
            "motion_blur": "false",
            "bloom": "true",
            "vsync": "false",
            "max_fps": "60",
        ],
        graphicsBackend: .d3dmetal,
        msync: true
    )

    public static let all = [ultraLow, maxPerformance, balanced, quality]

    /// Suggests a preset from the chip name (e.g. "Apple M2 Pro") and installed memory.
    public static func recommended(cpuBrand: String, memoryBytes: UInt64) -> PerformancePreset {
        let gb = memoryBytes / 1_073_741_824
        if cpuBrand.contains("Max") || cpuBrand.contains("Ultra") { return quality }
        if cpuBrand.contains("Pro") || gb >= 24 { return balanced }
        return maxPerformance
    }
}

public enum SystemInfo {
    public static var cpuBrand: String {
        #if os(macOS)
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
        #else
        return "Unknown"
        #endif
    }

    public static var memoryBytes: UInt64 { ProcessInfo.processInfo.physicalMemory }
}
