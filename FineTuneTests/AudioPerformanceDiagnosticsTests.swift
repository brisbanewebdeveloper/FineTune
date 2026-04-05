import XCTest
@testable import FineTune

final class AudioPerformanceDiagnosticsTests: XCTestCase {

    func testZeroDiagnosticsHasNoCallbackOrRouteData() {
        let diagnostics = AudioPerformanceDiagnostics.zero

        XCTAssertFalse(diagnostics.hasCallbackData)
        XCTAssertFalse(diagnostics.hasRouteSwitchData)
        XCTAssertEqual(diagnostics.callbackAverageMilliseconds, 0)
        XCTAssertEqual(diagnostics.callbackPeakMilliseconds, 0)
        XCTAssertEqual(diagnostics.callbackBudgetMilliseconds, 0)
        XCTAssertEqual(diagnostics.callbackFramesPerBuffer, 0)
        XCTAssertEqual(diagnostics.callbackSampleRateHz, 0)
        XCTAssertEqual(diagnostics.callbackCount, 0)
        XCTAssertFalse(diagnostics.hasCallbackBudget)
        XCTAssertFalse(diagnostics.hasCallbackFormat)
        XCTAssertFalse(diagnostics.callbackPeakExceedsBudget)
        XCTAssertEqual(diagnostics.routeSwitch, .zero)
    }

    func testCallbackPeakExceedsBudgetWhenPeakIsHigherThanBudget() {
        let diagnostics = AudioPerformanceDiagnostics(
            callbackAverageMilliseconds: 4.3,
            callbackPeakMilliseconds: 6.4,
            callbackBudgetMilliseconds: 5.8,
            callbackFramesPerBuffer: 512,
            callbackSampleRateHz: 48_000,
            callbackCount: 128,
            routeSwitch: .zero
        )

        XCTAssertTrue(diagnostics.hasCallbackBudget)
        XCTAssertTrue(diagnostics.hasCallbackFormat)
        XCTAssertTrue(diagnostics.callbackPeakExceedsBudget)
    }

    func testRouteSwitchDiagnosticsWithTotalPreservesBreakdown() {
        let diagnostics = RouteSwitchDiagnostics(
            totalMilliseconds: 0,
            tapCreationMilliseconds: 18.2,
            warmupMilliseconds: 300.4,
            crossfadeMilliseconds: 34.8,
            promotionMilliseconds: 10.1
        ).withTotalMilliseconds(363.5)

        XCTAssertTrue(diagnostics.hasData)
        XCTAssertEqual(diagnostics.totalMilliseconds, 363.5)
        XCTAssertEqual(diagnostics.tapCreationMilliseconds, 18.2)
        XCTAssertEqual(diagnostics.warmupMilliseconds, 300.4)
        XCTAssertEqual(diagnostics.crossfadeMilliseconds, 34.8)
        XCTAssertEqual(diagnostics.promotionMilliseconds, 10.1)
    }
}
