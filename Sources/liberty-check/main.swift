// liberty-check: a local stand-in for `swift test`.
//
// This target exists because XCTest is unavailable on machines with only the Command Line
// Tools (no Xcode), and swift-testing's macro plugin is missing too. The test bodies here are
// ported verbatim from Tests/LibertyCoreTests/ and run against Shim.swift's XCTest look-alikes.
// Tests/ REMAINS THE CI SOURCE OF TRUTH: when you add or change a test there, mirror it here
// (copy the file, drop `import XCTest`, add a line to the list below). Do not let them diverge.
//
// Run:  swift run liberty-check        (exits non-zero if any test fails)

import Foundation
import Darwin

typealias TestCase = (name: String, body: () throws -> Void)

/// Builds a registry entry: fresh instance per test, setUp, body, then tearDown (always).
func test<T: XCTestCase>(_ type: T.Type, _ name: String, _ body: @escaping (T) throws -> Void) -> TestCase {
    (name, {
        let instance = T()
        try instance.setUpWithError()
        do { try body(instance) } catch {
            try? instance.tearDownWithError()
            throw error
        }
        try instance.tearDownWithError()
    })
}

let tests: [TestCase] = [
    test(BottleScannerTests.self, "BottleScannerTests.testFindsGameInDefaultSteamLibrary") { try $0.testFindsGameInDefaultSteamLibrary() },
    test(BottleScannerTests.self, "BottleScannerTests.testFindsGameInSecondaryLibrary") { try $0.testFindsGameInSecondaryLibrary() },
    test(BottleScannerTests.self, "BottleScannerTests.testUserSettingsPathPrefersExistingUser") { try $0.testUserSettingsPathPrefersExistingUser() },
    test(BottleScannerTests.self, "BottleScannerTests.testLaunchCommand") { try $0.testLaunchCommand() },
    test(DiagnosticsTests.self, "DiagnosticsTests.testNotDeployedThenOK") { try $0.testNotDeployedThenOK() },
    test(DiagnosticsTests.self, "DiagnosticsTests.testOutdatedModTargetsMissingArchive") { try $0.testOutdatedModTargetsMissingArchive() },
    test(DiagnosticsTests.self, "DiagnosticsTests.testEmptyVariant") { try $0.testEmptyVariant() },
    test(DiagnosticsTests.self, "DiagnosticsTests.testOverriddenAndDisabledAndForeign") { try $0.testOverriddenAndDisabledAndForeign() },
    test(DiagnosticsTests.self, "DiagnosticsTests.testParseRequirements") { $0.testParseRequirements() },
    test(DiagnosticsTests.self, "DiagnosticsTests.testMissingRequirements") { try $0.testMissingRequirements() },
    test(ModManagerRequirementTests.self, "ModManagerRequirementTests.testModManagerRequirementsAreIgnored") { try $0.testModManagerRequirementsAreIgnored() },
    test(ModManagerRequirementTests.self, "ModManagerRequirementTests.testWindowsProgramIsRejectedWithClearError") { try $0.testWindowsProgramIsRejectedWithClearError() },
    test(DirectXReportTests.self, "DirectXReportTests.testCleanBottleFindsNoCause") { $0.testCleanBottleFindsNoCause() },
    test(DirectXReportTests.self, "DirectXReportTests.testSteamUserForcingDX11") { try $0.testSteamUserForcingDX11() },
    test(DirectXReportTests.self, "DirectXReportTests.testDisabledD3D12InRegistry") { try $0.testDisabledD3D12InRegistry() },
    test(DirectXReportTests.self, "DirectXReportTests.testWineDLLOverridesEnvironment") { try $0.testWineDLLOverridesEnvironment() },
    test(DirectXReportTests.self, "DirectXReportTests.testDX11ChoiceIsNotAProblem") { $0.testDX11ChoiceIsNotAProblem() },
    test(FeatureTests.self, "FeatureTests.testUltraLowPresetIsLowest") { $0.testUltraLowPresetIsLowest() },
    test(FeatureTests.self, "FeatureTests.testVersionComparison") { $0.testVersionComparison() },
    test(FeatureTests.self, "FeatureTests.testParseLatestRelease") { try $0.testParseLatestRelease() },
    test(FeatureTests.self, "FeatureTests.testParseNXMLink") { try $0.testParseNXMLink() },
    test(FeatureTests.self, "FeatureTests.testModUpdateFlag") { try $0.testModUpdateFlag() },
    test(FeatureTests.self, "FeatureTests.testReinstallKeepsPositionAndSettings") { try $0.testReinstallKeepsPositionAndSettings() },
    test(FeatureTests.self, "FeatureTests.testPreviewImage") { try $0.testPreviewImage() },
    test(FeatureTests.self, "FeatureTests.testProfilesRestoreOrderAndState") { try $0.testProfilesRestoreOrderAndState() },
    test(FeatureTests.self, "FeatureTests.testRetinaModeEditing") { $0.testRetinaModeEditing() },
    test(FeatureTests.self, "FeatureTests.testRetinaModeAddsMissingSection") { $0.testRetinaModeAddsMissingSection() },
    test(FeatureTests.self, "FeatureTests.testCustomPresetRoundTrip") { try $0.testCustomPresetRoundTrip() },
    test(FeatureTests.self, "FeatureTests.testPlaytime") { $0.testPlaytime() },
    test(FeatureTests.self, "FeatureTests.testLaunchWatchdog") { $0.testLaunchWatchdog() },
    test(LaunchOptionsTests.self, "LaunchOptionsTests.testReadsHelldiversLaunchOptionsOnly") { try $0.testReadsHelldiversLaunchOptionsOnly() },
    test(LaunchOptionsTests.self, "LaunchOptionsTests.testDetectsDX11Source") { $0.testDetectsDX11Source() },
    test(LaunchOptionsTests.self, "LaunchOptionsTests.testRemovingDX11KeepsOtherArgs") { $0.testRemovingDX11KeepsOtherArgs() },
    test(LaunchOptionsTests.self, "LaunchOptionsTests.testDirectXVersionArguments") { $0.testDirectXVersionArguments() },
    test(LaunchOptionsTests.self, "LaunchOptionsTests.testLowMemoryThreshold") { $0.testLowMemoryThreshold() },
    test(LoadOrderTests.self, "LoadOrderTests.testDetectHints") { $0.testDetectHints() },
    test(LoadOrderTests.self, "LoadOrderTests.testLoaderIsPinnedAndKeptAtBottom") { try $0.testLoaderIsPinnedAndKeptAtBottom() },
    test(LoadOrderTests.self, "LoadOrderTests.testExistingModsGetPinnedOnLoadAndOldIndexDecodes") { try $0.testExistingModsGetPinnedOnLoadAndOldIndexDecodes() },
    test(MemoryWatchTests.self, "MemoryWatchTests.testLevels") { $0.testLevels() },
    test(MemoryWatchTests.self, "MemoryWatchTests.testAlertsOncePerLevel") { $0.testAlertsOncePerLevel() },
    test(MemoryWatchTests.self, "MemoryWatchTests.testFormat") { $0.testFormat() },
    test(ModGuideTests.self, "ModGuideTests.testBBCodeToPlainText") { $0.testBBCodeToPlainText() },
    test(ModGuideTests.self, "ModGuideTests.testInstructionHighlights") { $0.testInstructionHighlights() },
    test(ModGuideTests.self, "ModGuideTests.testNoFalseHighlights") { $0.testNoFalseHighlights() },
    test(ModGuideTests.self, "ModGuideTests.testReadmeDiscoveryAndOldIndex") { try $0.testReadmeDiscoveryAndOldIndex() },
    test(ModLogsTests.self, "ModLogsTests.testFindLogsNewestFirst") { try $0.testFindLogsNewestFirst() },
    test(ModLogsTests.self, "ModLogsTests.testFindThroughGamePaths") { try $0.testFindThroughGamePaths() },
    test(ModLogsTests.self, "ModLogsTests.testTailAndParsing") { try $0.testTailAndParsing() },
    test(ModLogsTests.self, "ModLogsTests.testLoaderDidNotRun") { $0.testLoaderDidNotRun() },
    test(ModLogsTests.self, "ModLogsTests.testPlaytimeSessionTimestamps") { try $0.testPlaytimeSessionTimestamps() },
    test(ModTests.self, "ModTests.testParsePatchFileNames") { $0.testParsePatchFileNames() },
    test(ModTests.self, "ModTests.testManifestV1WithOptions") { try $0.testManifestV1WithOptions() },
    test(ModTests.self, "ModTests.testLegacyManifest") { try $0.testLegacyManifest() },
    test(ModTests.self, "ModTests.testInstallFolderUnwrapsAndUsesManifest") { try $0.testInstallFolderUnwrapsAndUsesManifest() },
    test(ModTests.self, "ModTests.testInstallRejectsFolderWithoutPatches") { try $0.testInstallRejectsFolderWithoutPatches() },
    test(ModTests.self, "ModTests.testMoveMatchesOnMoveSemantics") { try $0.testMoveMatchesOnMoveSemantics() },
    test(ModTests.self, "ModTests.testDeployRenumbersAndKeepsSiblingsTogether") { try $0.testDeployRenumbersAndKeepsSiblingsTogether() },
    test(ModTests.self, "ModTests.testPathGuard") { $0.testPathGuard() },
    test(PerformanceTests.self, "PerformanceTests.testParsesTopLevelAndNestedEntries") { $0.testParsesTopLevelAndNestedEntries() },
    test(PerformanceTests.self, "PerformanceTests.testEditPreservesEverythingElse") { $0.testEditPreservesEverythingElse() },
    test(PerformanceTests.self, "PerformanceTests.testNestedRenderSettings") { $0.testNestedRenderSettings() },
    test(PerformanceTests.self, "PerformanceTests.testBuiltInPresetsMatchRealConfigKeys") { $0.testBuiltInPresetsMatchRealConfigKeys() },
    test(PerformanceTests.self, "PerformanceTests.testBuiltInPresetsAddMacFriendlySettings") { $0.testBuiltInPresetsAddMacFriendlySettings() },
    test(PerformanceTests.self, "PerformanceTests.testBottleConfigEditing") { $0.testBottleConfigEditing() },
    test(PerformanceTests.self, "PerformanceTests.testBottleConfigCreatesSection") { $0.testBottleConfigCreatesSection() },
    test(PerformanceTests.self, "PerformanceTests.testMetalFXToggle") { $0.testMetalFXToggle() },
    test(PerformanceTests.self, "PerformanceTests.testPresetWithoutMetalFXStillDecodes") { try $0.testPresetWithoutMetalFXStillDecodes() },
    test(PerformanceTests.self, "PerformanceTests.testPresetRecommendation") { $0.testPresetRecommendation() },
    test(PerformanceTests.self, "PerformanceTests.testBackupAndRestoreOriginal") { try $0.testBackupAndRestoreOriginal() },
    test(PerformanceTests.self, "PerformanceTests.testVDF") { $0.testVDF() },
    test(V3FeatureTests.self, "V3FeatureTests.testDecodeTrendingAndFilter") { try $0.testDecodeTrendingAndFilter() },
    test(V3FeatureTests.self, "V3FeatureTests.testPreferredFile") { try $0.testPreferredFile() },
    test(V3FeatureTests.self, "V3FeatureTests.testParseGraphQLSearch") { $0.testParseGraphQLSearch() },
    test(V3FeatureTests.self, "V3FeatureTests.testParseWar") { $0.testParseWar() },
    test(V3FeatureTests.self, "V3FeatureTests.testParseWarToleratesMissingData") { $0.testParseWarToleratesMissingData() },
    test(V3FeatureTests.self, "V3FeatureTests.testDiscordFrameEncoding") { try $0.testDiscordFrameEncoding() },
    test(V3FeatureTests.self, "V3FeatureTests.testDiscordActivityPayload") { try $0.testDiscordActivityPayload() },
    test(V3FeatureTests.self, "V3FeatureTests.testCrashDetection") { $0.testCrashDetection() },
    test(V3FeatureTests.self, "V3FeatureTests.testRecentCrashFiles") { try $0.testRecentCrashFiles() },
    test(V3FeatureTests.self, "V3FeatureTests.testSetupStatus") { try $0.testSetupStatus() },
    test(InstallSelectionTests.self, "InstallSelectionTests.testNilKeyPicksFirst") { try $0.testNilKeyPicksFirst() },
    test(InstallSelectionTests.self, "InstallSelectionTests.testEmptyListResolvesToNil") { try $0.testEmptyListResolvesToNil() },
    test(InstallSelectionTests.self, "InstallSelectionTests.testResolvesByGameRootID") { try $0.testResolvesByGameRootID() },
    test(InstallSelectionTests.self, "InstallSelectionTests.testLegacyBottlePathStillResolves") { try $0.testLegacyBottlePathStillResolves() },
    test(InstallSelectionTests.self, "InstallSelectionTests.testUnknownKeyFallsBackToFirst") { try $0.testUnknownKeyFallsBackToFirst() },
    test(InstallSelectionTests.self, "InstallSelectionTests.testGameChangedNeedsBothSides") { try $0.testGameChangedNeedsBothSides() },
    test(InstallSelectionTests.self, "InstallSelectionTests.testGameChangedOnDifferentBuildID") { try $0.testGameChangedOnDifferentBuildID() },
    test(InstallSelectionTests.self, "InstallSelectionTests.testSwitchingSourcesIsNotAnUpdate") { try $0.testSwitchingSourcesIsNotAnUpdate() },
    test(InstallSelectionTests.self, "InstallSelectionTests.testGameChangedOnDifferentHash") { try $0.testGameChangedOnDifferentHash() },
    test(CosmeticCheckTests.self, "CosmeticCheckTests.testSoundModIsAssetsOnly") { try $0.testSoundModIsAssetsOnly() },
    test(CosmeticCheckTests.self, "CosmeticCheckTests.testDllIsNativeCode") { try $0.testDllIsNativeCode() },
    test(CosmeticCheckTests.self, "CosmeticCheckTests.testLuaIsScript") { try $0.testLuaIsScript() },
    test(CosmeticCheckTests.self, "CosmeticCheckTests.testManifestRequiringHD2Runtime") { try $0.testManifestRequiringHD2Runtime() },
    test(CosmeticCheckTests.self, "CosmeticCheckTests.testBingusFilenameIsRuntimeDependency") { try $0.testBingusFilenameIsRuntimeDependency() },
    test(CosmeticCheckTests.self, "CosmeticCheckTests.testManifestWithoutRequiresIsNotASignal") { try $0.testManifestWithoutRequiresIsNotASignal() },
    test(CosmeticCheckTests.self, "CosmeticCheckTests.testMalformedManifestDoesNotCrash") { try $0.testMalformedManifestDoesNotCrash() },
    test(CosmeticCheckTests.self, "CosmeticCheckTests.testRuntimeFolderIsRuntimeDependency") { try $0.testRuntimeFolderIsRuntimeDependency() },
    test(CosmeticCheckTests.self, "CosmeticCheckTests.testExecutableShellScriptIsReportedOnce") { try $0.testExecutableShellScriptIsReportedOnce() },
    test(CosmeticCheckTests.self, "CosmeticCheckTests.testExecutableBitOnPlainFile") { try $0.testExecutableBitOnPlainFile() },
    test(CosmeticCheckTests.self, "CosmeticCheckTests.testEmptyFolderIsInconclusive") { try $0.testEmptyFolderIsInconclusive() },
    test(CosmeticCheckTests.self, "CosmeticCheckTests.testMissingFolderIsInconclusive") { try $0.testMissingFolderIsInconclusive() },
    test(CosmeticCheckTests.self, "CosmeticCheckTests.testUnrecognisedFilesAreCounted") { try $0.testUnrecognisedFilesAreCounted() },
    test(CosmeticCheckTests.self, "CosmeticCheckTests.testSymlinksAreNotFollowed") { try $0.testSymlinksAreNotFollowed() },
    test(CosmeticCheckTests.self, "CosmeticCheckTests.testSignalOrderingIsDeterministic") { try $0.testSignalOrderingIsDeterministic() },
    test(CosmeticCheckTests.self, "CosmeticCheckTests.testPathsAreRelative") { try $0.testPathsAreRelative() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testDefaultQueryKeepsEverythingInOrder") { try $0.testDefaultQueryKeepsEverythingInOrder() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testAdultHiddenByDefaultShownWhenAllowed") { try $0.testAdultHiddenByDefaultShownWhenAllowed() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testUnavailableHiddenEvenWhenAdultAllowed") { try $0.testUnavailableHiddenEvenWhenAdultAllowed() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testNilNameAlwaysHidden") { try $0.testNilNameAlwaysHidden() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testHideInstalledRemovesExactlyInstalled") { try $0.testHideInstalledRemovesExactlyInstalled() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testTextMatchesNameSummaryAuthorIndependently") { try $0.testTextMatchesNameSummaryAuthorIndependently() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testMultiWordRequiresAllWords") { try $0.testMultiWordRequiresAllWords() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testWordsMayMatchAcrossFields") { try $0.testWordsMayMatchAcrossFields() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testCaseAndDiacriticInsensitive") { try $0.testCaseAndDiacriticInsensitive() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testWhitespaceOnlyTextIsNoFilter") { try $0.testWhitespaceOnlyTextIsNoFilter() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testEndorsementsDescendingNilAsZero") { try $0.testEndorsementsDescendingNilAsZero() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testNameAscendingNilLast") { try $0.testNameAscendingNilLast() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testTiesBreakByModIDUnderEverySort") { try $0.testTiesBreakByModIDUnderEverySort() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testDuplicateIDsStayStable") { try $0.testDuplicateIDsStayStable() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testDeterministicAcrossRepeatedApplication") { try $0.testDeterministicAcrossRepeatedApplication() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testEmptyInput") { try $0.testEmptyInput() },
    test(BrowseQueryTests.self, "BrowseQueryTests.testIsDefault") { try $0.testIsDefault() },
    test(NexusBrowseTests.self, "NexusBrowseTests.testParseSearchReadsAdultAndAvailability") { try $0.testParseSearchReadsAdultAndAvailability() },
    test(NexusBrowseTests.self, "NexusBrowseTests.testParseSearchWithoutFieldsLeavesNil") { try $0.testParseSearchWithoutFieldsLeavesNil() },
    test(NexusBrowseTests.self, "NexusBrowseTests.testSearchResultsFilterAdultAndUnavailable") { try $0.testSearchResultsFilterAdultAndUnavailable() },
    test(NexusBrowseTests.self, "NexusBrowseTests.testPagingSlicesAndHasMore") { try $0.testPagingSlicesAndHasMore() },
    test(NexusBrowseTests.self, "NexusBrowseTests.testPagingOutOfRangeIsEmpty") { try $0.testPagingOutOfRangeIsEmpty() },
    test(NexusBrowseTests.self, "NexusBrowseTests.testClientPagingFetchesOnceAndFilters") { try $0.testClientPagingFetchesOnceAndFilters() },
    test(NexusBrowseTests.self, "NexusBrowseTests.testNeedsModRuntime") { try $0.testNeedsModRuntime() },
    test(NexusBrowseTests.self, "NexusBrowseTests.testRequirementsParseFixtureFeedsRuntimeCheck") { try $0.testRequirementsParseFixtureFeedsRuntimeCheck() },
    test(NexusPagingTests.self, "NexusPagingTests.testBrowseParsesTotalCountAndMapsFields") { try $0.testBrowseParsesTotalCountAndMapsFields() },
    test(NexusPagingTests.self, "NexusPagingTests.testStatusMapsToAvailable") { try $0.testStatusMapsToAvailable() },
    test(NexusPagingTests.self, "NexusPagingTests.testAdultContentIsFilteredOut") { try $0.testAdultContentIsFilteredOut() },
    test(NexusPagingTests.self, "NexusPagingTests.testHasMoreTrueWhenOffsetPlusCountBelowTotal") { try $0.testHasMoreTrueWhenOffsetPlusCountBelowTotal() },
    test(NexusPagingTests.self, "NexusPagingTests.testHasMoreFalseAtEnd") { try $0.testHasMoreFalseAtEnd() },
    test(NexusPagingTests.self, "NexusPagingTests.testHasMoreSurvivesFullyFilteredPage") { try $0.testHasMoreSurvivesFullyFilteredPage() },
    test(NexusPagingTests.self, "NexusPagingTests.testEverySortProducesExpectedVariables") { try $0.testEverySortProducesExpectedVariables() },
    test(NexusPagingTests.self, "NexusPagingTests.testGraphQLErrorsArrayIsFailure") { try $0.testGraphQLErrorsArrayIsFailure() },
    test(NexusPagingTests.self, "NexusPagingTests.testMissingModsNodeIsMalformed") { try $0.testMissingModsNodeIsMalformed() },
    test(NexusPagingTests.self, "NexusPagingTests.testDifferentOffsetsProduceDifferentRequests") { try $0.testDifferentOffsetsProduceDifferentRequests() },
    test(NexusPagingTests.self, "NexusPagingTests.testRequestHeadersAndQuery") { try $0.testRequestHeadersAndQuery() }
]

var passed = 0, failed = 0, skipped = 0
for (name, body) in tests {
    Harness.currentFailures = []
    var skipReason: String?
    var thrown: Error?
    do { try body() }
    catch let skip as XCTSkip { skipReason = skip.reason }
    catch is XCTUnwrapFailure {}            // already recorded by XCTUnwrap
    catch { thrown = error }
    if let thrown { Harness.currentFailures.append("test threw error: \(thrown)") }

    if !Harness.currentFailures.isEmpty {
        failed += 1
        print("FAIL \(name)")
        for message in Harness.currentFailures { print("     \(message)") }
    } else if let skipReason {
        skipped += 1
        print("SKIP \(name) (\(skipReason))")
    } else {
        passed += 1
        print("PASS \(name)")
    }
}
print("\(tests.count) tests: \(passed) passed, \(skipped) skipped, \(failed) failed")
exit(failed == 0 ? 0 : 1)
