import XCTest
@testable import LibertyCore

final class PerformanceTests: TempDirTestCase {
    let sample = """
    // Helldivers 2 settings
    shadow_quality = 2
    vsync = true
    render_resolution_scale = 1.0
    screen_resolution = [
        1920
        1080
    ]
    controls = {
        shadow_quality = 99
    }
    player_name = "Diver = 1"
    """

    func testParsesOnlyTopLevelEntries() {
        let config = UserSettingsConfig(text: sample)
        XCTAssertEqual(config.entries.map(\.key), ["shadow_quality", "vsync", "render_resolution_scale", "player_name"])
        XCTAssertEqual(config.value(for: "player_name"), "\"Diver = 1\"")
    }

    func testEditPreservesEverythingElse() {
        var config = UserSettingsConfig(text: sample)
        let missing = config.apply(["shadow_quality": "0", "vsync": "false", "made_up_key": "1"])
        XCTAssertEqual(missing, ["made_up_key"])
        let expected = sample
            .replacingOccurrences(of: "shadow_quality = 2", with: "shadow_quality = 0")
            .replacingOccurrences(of: "vsync = true", with: "vsync = false")
        XCTAssertEqual(config.text, expected)
        XCTAssertTrue(config.text.contains("shadow_quality = 99"))
    }

    func testBottleConfigEditing() {
        var config = BottleConfig(text: """
        [Bottle]
        "Template" = "win10_64"

        [EnvironmentVariables]
        "FOO" = "bar"

        [Other]
        "X" = "1"
        """)
        XCTAssertNil(config.graphicsBackend)
        config.graphicsBackend = .dxvk
        config.msyncEnabled = true
        XCTAssertEqual(config.graphicsBackend, .dxvk)
        XCTAssertTrue(config.msyncEnabled)
        XCTAssertEqual(config.value("FOO", in: "EnvironmentVariables"), "bar")
        XCTAssertEqual(config.value("X", in: "Other"), "1")
        XCTAssertTrue(config.text.contains("\"FOO\" = \"bar\"\n\"CX_GRAPHICS_BACKEND\" = \"dxvk\"\n\"WINEMSYNC\" = \"1\"\n\n[Other]"))

        config.msyncEnabled = false
        XCTAssertFalse(config.text.contains("WINEMSYNC"))
    }

    func testBottleConfigCreatesSection() {
        var config = BottleConfig(text: "[Bottle]\n\"Template\" = \"win10_64\"")
        config.metalHUDEnabled = true
        XCTAssertEqual(config.text, "[Bottle]\n\"Template\" = \"win10_64\"\n\n[EnvironmentVariables]\n\"MTL_HUD_ENABLED\" = \"1\"")
    }

    func testMetalFXToggle() {
        var config = BottleConfig(text: "[EnvironmentVariables]")
        XCTAssertFalse(config.metalFXEnabled)
        config.metalFXEnabled = true
        XCTAssertTrue(config.text.contains("\"D3DM_ENABLE_METALFX\" = \"1\""))
        XCTAssertTrue(config.text.contains("\"DXMT_ENABLE_NVEXT\" = \"1\""))
        config.metalFXEnabled = false
        XCTAssertFalse(config.text.contains("METALFX"))
        XCTAssertFalse(config.text.contains("NVEXT"))
        XCTAssertTrue(BottleConfig(text: "[EnvironmentVariables]\n\"DXMT_ENABLE_NVEXT\" = \"1\"").metalFXEnabled)
    }

    func testPresetWithoutMetalFXStillDecodes() throws {
        let json = #"{"id":"x","name":"Old","summary":"s","gameSettings":{},"graphicsBackend":"d3dmetal","msync":true}"#
        let preset = try JSONDecoder().decode(PerformancePreset.self, from: Data(json.utf8))
        XCTAssertNil(preset.metalFX)
    }

    func testPresetRecommendation() {
        let gb: UInt64 = 1_073_741_824
        XCTAssertEqual(PerformancePreset.recommended(cpuBrand: "Apple M1", memoryBytes: 8 * gb).id, "max-performance")
        XCTAssertEqual(PerformancePreset.recommended(cpuBrand: "Apple M3 Pro", memoryBytes: 18 * gb).id, "balanced")
        XCTAssertEqual(PerformancePreset.recommended(cpuBrand: "Apple M2 Max", memoryBytes: 32 * gb).id, "quality")
    }

    func testBackupAndRestoreOriginal() throws {
        let file = try write("user_settings.config", "original")
        let manager = try BackupManager(directory: tmp.appendingPathComponent("backups"))
        manager.keepPerFile = 2

        try manager.backup(file, label: "first")
        for i in 1...4 {
            try "edit \(i)".write(to: file, atomically: true, encoding: .utf8)
            try manager.backup(file, label: "edit \(i)")
        }
        XCTAssertEqual(manager.backups.filter(\.isOriginal).count, 1)
        XCTAssertEqual(manager.backups.count, 3) // original + 2 most recent

        try manager.restoreOriginal(of: file)
        XCTAssertEqual(try read(file), "original")

        let reloaded = try BackupManager(directory: tmp.appendingPathComponent("backups"))
        XCTAssertEqual(reloaded.backups.count, 3)
    }

    func testVDF() {
        let text = "\"AppState\" { \"buildid\" \"42\" \"path\" \"C:\\\\a\\\\b\" }"
        XCTAssertEqual(VDF.value(forKey: "buildid", in: text), "42")
        XCTAssertEqual(VDF.value(forKey: "path", in: text), "C:\\a\\b")
    }
}
