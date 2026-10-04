import XCTest
@testable import LibertyCore

final class DirectXReportTests: TempDirTestCase {
    var game: GamePaths!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let bottle = tmp.appendingPathComponent("Bottle")
        let steam = bottle.appendingPathComponent("drive_c/Program Files (x86)/Steam")
        game = GamePaths(bottleURL: bottle, steamRootURL: steam, libraryURL: steam)
        try FileManager.default.createDirectory(at: steam, withIntermediateDirectories: true)
    }

    private func localConfig(_ options: String) -> String {
        "\"UserLocalConfigStore\"\n{\n\"apps\"\n{\n\"553850\"\n{\n\"LaunchOptions\"\t\t\"\(options)\"\n}\n}\n}\n"
    }

    func testCleanBottleFindsNoCause() {
        let report = DirectXReport.collect(game: game, extraArguments: "", choice: .dx12)
        XCTAssertEqual(report.findings, [.noCauseFound])
        XCTAssertTrue(report.text.contains("Launch arguments: (none)"))
    }

    func testSteamUserForcingDX11() throws {
        try write("1/config/localconfig.vdf", localConfig("-windowed"), in: game.steamRootURL.appendingPathComponent("userdata"))
        try write("2/config/localconfig.vdf", localConfig("-dx11"), in: game.steamRootURL.appendingPathComponent("userdata"))
        let report = DirectXReport.collect(game: game, extraArguments: "", choice: .dx12)
        XCTAssertEqual(report.steamLaunchOptions.count, 2)
        XCTAssertEqual(report.findings, [.steamForcesDX11(user: "2")])
    }

    func testDisabledD3D12InRegistry() throws {
        try write("user.reg", """
        WINE REGISTRY Version 2

        [Software\\\\Wine\\\\DllOverrides] 1
        "*d3d12"=""
        "winhttp"="native,builtin"

        [Software\\\\Wine\\\\AppDefaults\\\\helldivers2.exe\\\\DllOverrides] 1
        "dxgi"="native"
        """, in: game.bottleURL)
        let report = DirectXReport.collect(game: game, extraArguments: "", choice: .dx12)
        XCTAssertEqual(report.overrides.count, 2)
        XCTAssertEqual(report.findings, [.dllDisabled(name: "*d3d12", source: "user.reg [Software\\Wine\\DllOverrides]")])
    }

    func testWineDLLOverridesEnvironment() throws {
        XCTAssertEqual(DirectXReport.parseDLLOverrides("d3d12=;dxgi,d3d11=n,b").map { "\($0.0)=\($0.1)" }, ["d3d12=", "dxgi=n,b", "d3d11=n,b"])
        try write("cxbottle.conf", "[EnvironmentVariables]\n\"WINEDLLOVERRIDES\" = \"d3d12=\"\n\"CX_GRAPHICS_BACKEND\" = \"dxvk\"", in: game.bottleURL)
        let report = DirectXReport.collect(game: game, extraArguments: "", choice: .dx12)
        XCTAssertEqual(report.findings, [
            .dllDisabled(name: "d3d12", source: "cxbottle.conf WINEDLLOVERRIDES"),
            .backendWithoutDX12("dxvk"),
        ])
    }

    func testDX11ChoiceIsNotAProblem() {
        let report = DirectXReport.collect(game: game, extraArguments: "", choice: .dx11)
        XCTAssertEqual(report.findings, [.launchArgumentsForceDX11])
        XCTAssertTrue(report.text.contains("--use-d3d11"))
    }
}
