import XCTest
@testable import LibertyCore

final class LaunchOptionsTests: TempDirTestCase {
    let localConfig = """
    "UserLocalConfigStore"
    {
        "Software"
        {
            "Valve"
            {
                "Steam"
                {
                    "apps"
                    {
                        "730"
                        {
                            "LaunchOptions"		"-novid"
                        }
                        "553850"
                        {
                            "LastPlayed"		"1700000000"
                            "LaunchOptions"		"--use-d3d11 -windowed"
                        }
                    }
                }
            }
        }
    }
    """

    func testReadsHelldiversLaunchOptionsOnly() throws {
        try write("Steam/userdata/123/config/localconfig.vdf", localConfig)
        XCTAssertEqual(SteamLaunchOptions.read(steamRoot: tmp.appendingPathComponent("Steam")), "--use-d3d11 -windowed")
        XCTAssertNil(SteamLaunchOptions.launchOptions(appID: "999", in: localConfig))
        XCTAssertNil(SteamLaunchOptions.read(steamRoot: tmp.appendingPathComponent("Missing")))
    }

    func testDetectsDX11Source() {
        XCTAssertEqual(DirectXMode.dx11Source(libertyArgs: "-dx11", steamArgs: nil), .liberty)
        XCTAssertEqual(DirectXMode.dx11Source(libertyArgs: "", steamArgs: "--USE-D3D11"), .steam)
        XCTAssertNil(DirectXMode.dx11Source(libertyArgs: "-dx110 -windowed", steamArgs: "-novid"))
    }

    func testRemovingDX11KeepsOtherArgs() {
        XCTAssertEqual(DirectXMode.removingDX11(from: "-windowed --use-d3d11  -novid"), "-windowed -novid")
    }

    func testLowMemoryThreshold() {
        let gb: UInt64 = 1_073_741_824
        XCTAssertTrue(MemoryAdvice.isLowMemory(bytes: 16 * gb))
        XCTAssertFalse(MemoryAdvice.isLowMemory(bytes: 24 * gb))
    }
}
