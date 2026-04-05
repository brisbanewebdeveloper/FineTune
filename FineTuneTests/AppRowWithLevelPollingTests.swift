import XCTest
@testable import FineTune

@MainActor
final class AppRowWithLevelPollingTests: XCTestCase {

    func testBandMetersShowNormalizedRealtimeLevelsOnlyWhileMeteringIsEnabled() {
        var state = AppRowBandMeteringState()
        let realtimeLevels = RealtimeBandLevels(
            original: [1.4, -0.2, 0.35],
            afterCompressor: [0.8, 0.5, 1.2],
            afterEQ: [0.1, 0.0, 0.9]
        )

        XCTAssertEqual(state.displayedLevels(from: realtimeLevels), .zero)

        let enabled = state.sync(isPopupVisible: true, isEQExpanded: true)
        XCTAssertTrue(enabled)
        XCTAssertEqual(
            state.displayedLevels(from: realtimeLevels),
            RealtimeBandLevels(
                original: [1.0, 0.0, 0.35] + Array(repeating: 0.0, count: EQSettings.bandCount - 3),
                afterCompressor: [0.8, 0.5, 1.0] + Array(repeating: 0.0, count: EQSettings.bandCount - 3),
                afterEQ: [0.1, 0.0, 0.9] + Array(repeating: 0.0, count: EQSettings.bandCount - 3)
            )
        )

        let disabled = state.sync(isPopupVisible: true, isEQExpanded: false)
        XCTAssertFalse(disabled)
        XCTAssertEqual(state.displayedLevels(from: realtimeLevels), .zero)
    }

    func testBandMeteringOnlyEnablesWhenPopupIsVisibleAndEQIsExpanded() {
        var state = AppRowBandMeteringState()

        XCTAssertFalse(state.sync(isPopupVisible: false, isEQExpanded: false))
        XCTAssertFalse(state.sync(isPopupVisible: false, isEQExpanded: true))
        XCTAssertFalse(state.sync(isPopupVisible: true, isEQExpanded: false))
        XCTAssertTrue(state.sync(isPopupVisible: true, isEQExpanded: true))
    }

    func testPerformanceDiagnosticsReturnsZeroWithoutCallingProviderWhenDisabled() {
        var callCount = 0

        let diagnostics = AppRowPerformanceDiagnosticsState.displayedDiagnostics(isEnabled: false) {
            callCount += 1
            return AudioPerformanceDiagnostics(
                callbackAverageMilliseconds: 1.5,
                callbackPeakMilliseconds: 2.0,
                callbackBudgetMilliseconds: 5.8,
                callbackFramesPerBuffer: 512,
                callbackSampleRateHz: 48_000,
                callbackCount: 4,
                routeSwitch: .zero
            )
        }

        XCTAssertEqual(diagnostics, .zero)
        XCTAssertEqual(callCount, 0)
    }

    func testPerformanceDiagnosticsReturnsProviderValueWhenEnabled() {
        let expected = AudioPerformanceDiagnostics(
            callbackAverageMilliseconds: 1.5,
            callbackPeakMilliseconds: 2.0,
            callbackBudgetMilliseconds: 5.8,
            callbackFramesPerBuffer: 512,
            callbackSampleRateHz: 48_000,
            callbackCount: 4,
            routeSwitch: .zero
        )

        let diagnostics = AppRowPerformanceDiagnosticsState.displayedDiagnostics(isEnabled: true) {
            expected
        }

        XCTAssertEqual(diagnostics, expected)
    }
}
