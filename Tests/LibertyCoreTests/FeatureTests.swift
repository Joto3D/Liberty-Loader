import XCTest
@testable import LibertyCore

final class FeatureTests: TempDirTestCase {
    // MARK: Updates

    func testVersionComparison() {
        XCTAssertTrue(AppVersion("v0.2.0")! > AppVersion("0.1.9")!)
        XCTAssertTrue(AppVersion("1.10")! > AppVersion("1.9.9")!)
        XCTAssertEqual(AppVersion("1.0")!, AppVersion("1.0.0")!)
        XCTAssertEqual(AppVersion("v1.2.3-beta")?.description, "1.2.3")
        XCTAssertNil(AppVersion("latest"))
    }

    func testParseLatestRelease() throws {
        let json = """
        {"tag_name":"v0.3.0","html_url":"https://github.com/Joto3D/Liberty-Loader/releases/tag/v0.3.0",
         "body":"New stuff","draft":false,"prerelease":false,
         "assets":[{"name":"LibertyLoader.dmg","browser_download_url":"https://example.com/a.dmg"},
                   {"name":"LibertyLoader.zip","browser_download_url":"https://example.com/a.zip"}]}
        """
        let release = try XCTUnwrap(UpdateChecker.parseLatestRelease(Data(json.utf8)))
        XCTAssertEqual(release.version.description, "0.3.0")
        XCTAssertEqual(release.zipURL?.absoluteString, "https://example.com/a.zip")
        XCTAssertEqual(release.dmgURL?.absoluteString, "https://example.com/a.dmg")
        XCTAssertEqual(release.notes, "New stuff")

        let prerelease = json.replacingOccurrences(of: "\"prerelease\":false", with: "\"prerelease\":true")
        XCTAssertNil(try UpdateChecker.parseLatestRelease(Data(prerelease.utf8)))
    }

    // MARK: Nexus

    func testParseNXMLink() throws {
        let link = try XCTUnwrap(NXMLink(url: URL(string: "nxm://helldivers2/mods/123/files/456?key=abc&expires=1700000000&user_id=9")!))
        XCTAssertEqual(link.game, "helldivers2")
        XCTAssertEqual(link.modID, 123)
        XCTAssertEqual(link.fileID, 456)
        XCTAssertEqual(link.key, "abc")
        XCTAssertEqual(link.expires, "1700000000")

        let premium = try XCTUnwrap(NXMLink(url: URL(string: "nxm://helldivers2/mods/1/files/2")!))
        XCTAssertNil(premium.key)
        XCTAssertNil(NXMLink(url: URL(string: "https://nexusmods.com/helldivers2/mods/1")!))
        XCTAssertNil(NXMLink(url: URL(string: "nxm://helldivers2/collections/abc")!))
    }

    func testModUpdateFlag() throws {
        try write("A/9ba626afa44a3aa3.patch_0")
        let store = try ModStore(rootURL: tmp.appendingPathComponent("store"))
        var mod = try store.install(from: tmp.appendingPathComponent("A"))
        XCTAssertFalse(mod.hasUpdate)
        mod.version = "1.2"
        mod.latestVersion = "1.10"
        XCTAssertTrue(mod.hasUpdate)
        mod.latestVersion = "1.2.0"
        XCTAssertFalse(mod.hasUpdate)
    }

    func testReinstallKeepsPositionAndSettings() throws {
        let store = try ModStore(rootURL: tmp.appendingPathComponent("store"))
        try write("A/9ba626afa44a3aa3.patch_0", "old")
        try write("B/9ba626afa44a3aa3.patch_0")
        let a = try store.install(from: tmp.appendingPathComponent("A"))
        try store.install(from: tmp.appendingPathComponent("B"))
        var disabled = a
        disabled.enabled = false
        try store.update(disabled)

        try write("A2/9ba626afa44a3aa3.patch_0", "new")
        let updated = try store.install(from: tmp.appendingPathComponent("A2"), replacing: a.id)
        XCTAssertEqual(store.mods.count, 2)
        XCTAssertEqual(store.mods.first?.id, a.id)
        XCTAssertFalse(updated.enabled)
        XCTAssertEqual(try read(store.resolve(updated).patchSets[0].files[""]!), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.modsDirectory.appendingPathComponent(a.folderName).path))
    }

    func testPreviewImage() throws {
        try write("A/manifest.json", #"{"Name":"A","IconPath":"icon.png"}"#)
        try write("A/icon.png")
        try write("A/9ba626afa44a3aa3.patch_0")
        let store = try ModStore(rootURL: tmp.appendingPathComponent("store"))
        let mod = try store.install(from: tmp.appendingPathComponent("A"))
        XCTAssertEqual(store.previewImageURL(for: mod)?.lastPathComponent, "icon.png")
    }

    // MARK: Profiles

    func testProfilesRestoreOrderAndState() throws {
        let store = try ModStore(rootURL: tmp.appendingPathComponent("store"))
        for name in ["A", "B", "C"] {
            try write("\(name)/9ba626afa44a3aa3.patch_0")
            try store.install(from: tmp.appendingPathComponent(name))
        }
        let profiles = ModProfileStore(rootURL: tmp.appendingPathComponent("store"))
        try store.setAllEnabled(false)
        let allOff = try profiles.save(name: "Vanilla", from: store.mods)

        try store.setAllEnabled(true)
        try store.move(fromOffsets: IndexSet(integer: 0), toOffset: 3) // B, C, A
        try profiles.save(name: "Everything", from: store.mods)

        try write("D/9ba626afa44a3aa3.patch_0")
        try store.install(from: tmp.appendingPathComponent("D"))

        try store.apply(allOff)
        XCTAssertEqual(store.mods.map(\.name), ["A", "B", "C", "D"])
        XCTAssertEqual(store.mods.map(\.enabled), [false, false, false, false])

        let reloaded = ModProfileStore(rootURL: tmp.appendingPathComponent("store"))
        XCTAssertEqual(reloaded.profiles.map(\.name), ["Vanilla", "Everything"])
        try store.apply(reloaded.profiles[1])
        XCTAssertEqual(store.mods.map(\.name), ["B", "C", "A", "D"])
        XCTAssertEqual(store.mods.map(\.enabled), [true, true, true, false])
    }

    // MARK: Retina

    func testRetinaModeEditing() {
        let text = """
        WINE REGISTRY Version 2
        ;; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000

        [Software\\\\Wine\\\\Mac Driver] 1700000000
        #time=1da1234
        "RetinaMode"="y"

        [Software\\\\Wine\\\\X11 Driver] 1700000000
        "Foo"="bar"
        """
        var registry = WineRegistryFile(text: text)
        XCTAssertTrue(RetinaMode.isEnabled(in: registry))
        RetinaMode.set(false, in: &registry)
        XCTAssertFalse(RetinaMode.isEnabled(in: registry))
        XCTAssertEqual(registry.text, text.replacingOccurrences(of: "\"RetinaMode\"=\"y\"", with: "\"RetinaMode\"=\"n\""))
    }

    func testRetinaModeAddsMissingSection() {
        var registry = WineRegistryFile(text: "WINE REGISTRY Version 2\n\n[Software\\\\Other] 1\n\"A\"=\"b\"\n")
        XCTAssertFalse(RetinaMode.isEnabled(in: registry))
        registry.setString("n", for: "RetinaMode", in: RetinaMode.key, now: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(registry.text, "WINE REGISTRY Version 2\n\n[Software\\\\Other] 1\n\"A\"=\"b\"\n\n[Software\\\\Wine\\\\Mac Driver] 5\n\"RetinaMode\"=\"n\"\n")
        XCTAssertEqual(registry.string("RetinaMode", in: RetinaMode.key), "n")
    }

    // MARK: Custom presets

    func testCustomPresetRoundTrip() throws {
        let config = UserSettingsConfig(text: "shadow_quality = 1\nvsync = false")
        var bottle = BottleConfig(text: "")
        bottle.graphicsBackend = .dxvk
        bottle.metalHUDEnabled = true
        let preset = PerformancePreset.custom(name: "Mine", config: config, bottle: bottle)
        XCTAssertFalse(preset.isBuiltIn)
        XCTAssertEqual(preset.gameSettings, ["shadow_quality": "1", "vsync": "false"])

        let store = PresetStore(rootURL: tmp)
        try store.add(preset)
        let reloaded = PresetStore(rootURL: tmp)
        XCTAssertEqual(reloaded.custom, [preset])
        XCTAssertEqual(reloaded.custom.first?.graphicsBackend, .dxvk)
        XCTAssertEqual(reloaded.custom.first?.metalHUD, true)
        XCTAssertEqual(reloaded.all.count, PerformancePreset.all.count + 1)
        try reloaded.delete(id: preset.id)
        XCTAssertTrue(PresetStore(rootURL: tmp).custom.isEmpty)
    }

    // MARK: Playtime & watchdog

    func testPlaytime() {
        var record = PlaytimeRecord()
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(record.update(isRunning: false, now: t0))
        record.update(isRunning: true, now: t0)
        record.update(isRunning: true, now: t0.addingTimeInterval(600))
        XCTAssertEqual(record.total(now: t0.addingTimeInterval(900)), 900)
        record.update(isRunning: false, now: t0.addingTimeInterval(900))
        XCTAssertEqual(record.totalSeconds, 600) // last seen running at +600
        XCTAssertEqual(record.sessionCount, 1)
        XCTAssertEqual(PlaytimeRecord.format(3 * 3600 + 5 * 60), "3 h 5 min")
        XCTAssertEqual(PlaytimeRecord.format(59), "0 min")
    }

    func testLaunchWatchdog() {
        var watchdog = LaunchWatchdog(timeout: 60)
        let t0 = Date(timeIntervalSince1970: 0)
        XCTAssertFalse(watchdog.check(gameRunning: false, now: t0))
        watchdog.didLaunch(at: t0)
        XCTAssertFalse(watchdog.check(gameRunning: false, now: t0.addingTimeInterval(30)))
        XCTAssertTrue(watchdog.check(gameRunning: false, now: t0.addingTimeInterval(61)))
        XCTAssertFalse(watchdog.check(gameRunning: true, now: t0.addingTimeInterval(62)))
        XCTAssertNil(watchdog.launchedAt)
    }
}
