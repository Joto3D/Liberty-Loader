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
    public var metalFX: Bool? = nil

    public static let ultraLow = PerformancePreset(
        id: "ultra-low",
        name: "Ultra Low",
        summary: "Below the game's lowest settings, like the Ultimate Performance mod. Every effect off, even sun shadows, for weak Macs or the highest FPS.",
        gameSettings: [
            "shadows": "0",
            "particle_quality": "0",
            "terrain_quality": "0",
            "texture_quality": "0",
            "volumetric_clouds_quality": "0",
            "volumetric_fog_quality": "0",
            "reflection_quality": "0",
            "lighting_and_material_quality": "0",
            "upscaling_quality": "0",
            "ssao_enabled": "0",
            "ssr_enabled": "false",
            "dof_enabled": "false",
            "motion_blur_enabled": "false",
            "bloom_enabled": "false",
            "vsync": "false",
            "framerate_limit_enabled": "true",
            "framerate_limit": "60",
            "view_distance": "\"low\"",
            "object_lod_quality": "0",
            "space_quality": "0",
            "particles_tessellation": "false",
            "heathaze_enabled": "false",
            "sun_shadows": "false",
            "far_scatter_enabled": "false",
            "particles_receive_shadows": "false",
            "particles_local_lighting": "false",
            "wind_enabled": "false",
        ],
        graphicsBackend: .d3dmetal,
        msync: true
    )

    public static let maxPerformance = PerformancePreset(
        id: "max-performance",
        name: "Max Performance",
        summary: "For base M1–M4 chips and 8–16 GB Macs. Lowest shadows, particles and view distance, 30 FPS cap for stable frame times.",
        gameSettings: [
            "shadows": "0",
            "particle_quality": "0",
            "terrain_quality": "0",
            "texture_quality": "1",
            "volumetric_clouds_quality": "0",
            "volumetric_fog_quality": "0",
            "reflection_quality": "0",
            "lighting_and_material_quality": "0",
            "upscaling_quality": "0",
            "ssao_enabled": "0",
            "ssr_enabled": "false",
            "dof_enabled": "false",
            "motion_blur_enabled": "false",
            "bloom_enabled": "false",
            "vsync": "false",
            "framerate_limit_enabled": "true",
            "framerate_limit": "30",
            "view_distance": "\"low\"",
            "object_lod_quality": "0",
            "space_quality": "0",
            "particles_tessellation": "false",
            "heathaze_enabled": "false",
        ],
        graphicsBackend: .d3dmetal,
        msync: true
    )

    public static let balanced = PerformancePreset(
        id: "balanced",
        name: "Balanced",
        summary: "For Pro chips with 16–32 GB. Medium shadows and effects, 60 FPS cap.",
        gameSettings: [
            "shadows": "1",
            "particle_quality": "1",
            "terrain_quality": "1",
            "texture_quality": "2",
            "volumetric_clouds_quality": "1",
            "volumetric_fog_quality": "1",
            "reflection_quality": "1",
            "lighting_and_material_quality": "1",
            "upscaling_quality": "1",
            "ssao_enabled": "1",
            "ssr_enabled": "false",
            "dof_enabled": "false",
            "motion_blur_enabled": "false",
            "bloom_enabled": "true",
            "vsync": "false",
            "framerate_limit_enabled": "true",
            "framerate_limit": "60",
        ],
        graphicsBackend: .d3dmetal,
        msync: true
    )

    public static let quality = PerformancePreset(
        id: "quality",
        name: "Quality",
        summary: "For Max/Ultra chips. High shadows, reflections and effects.",
        gameSettings: [
            "shadows": "2",
            "particle_quality": "2",
            "terrain_quality": "2",
            "texture_quality": "3",
            "volumetric_clouds_quality": "2",
            "volumetric_fog_quality": "2",
            "reflection_quality": "2",
            "lighting_and_material_quality": "2",
            "upscaling_quality": "2",
            "ssao_enabled": "1",
            "ssr_enabled": "true",
            "dof_enabled": "true",
            "motion_blur_enabled": "false",
            "bloom_enabled": "true",
            "vsync": "false",
            "framerate_limit_enabled": "true",
            "framerate_limit": "60",
        ],
        graphicsBackend: .d3dmetal,
        msync: true
    )

    /// Settings from the real HD2 config that only cost performance on a Mac: the Nvidia/AMD latency
    /// features, a resource debug option, and the "GPU drivers are out of date" prompt that CrossOver's
    /// emulated Nvidia GPU triggers.
    public static let macFriendlySettings: [String: String] = [
        "IGNORE_APPROVED_DRIVER_WARNING": "true",
        "enable_resource_lock_debug": "false",
        "reflex_mode": "0",
        "anti_lag": "false",
    ]

    /// What a preset writes: built-ins also get the Mac-friendly settings.
    public var settingsToApply: [String: String] {
        isBuiltIn ? gameSettings.merging(Self.macFriendlySettings) { preset, _ in preset } : gameSettings
    }

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
