import Foundation

struct RouteSwitchDiagnostics: Equatable, Sendable {
    let totalMilliseconds: Double
    let tapCreationMilliseconds: Double
    let warmupMilliseconds: Double
    let crossfadeMilliseconds: Double
    let promotionMilliseconds: Double

    static let zero = RouteSwitchDiagnostics(
        totalMilliseconds: 0,
        tapCreationMilliseconds: 0,
        warmupMilliseconds: 0,
        crossfadeMilliseconds: 0,
        promotionMilliseconds: 0
    )

    var hasData: Bool { totalMilliseconds > 0 }

    func withTotalMilliseconds(_ totalMilliseconds: Double) -> RouteSwitchDiagnostics {
        RouteSwitchDiagnostics(
            totalMilliseconds: totalMilliseconds,
            tapCreationMilliseconds: tapCreationMilliseconds,
            warmupMilliseconds: warmupMilliseconds,
            crossfadeMilliseconds: crossfadeMilliseconds,
            promotionMilliseconds: promotionMilliseconds
        )
    }
}

struct AudioPerformanceDiagnostics: Equatable, Sendable {
    let callbackAverageMilliseconds: Double
    let callbackPeakMilliseconds: Double
    let callbackBudgetMilliseconds: Double
    let callbackFramesPerBuffer: UInt32
    let callbackSampleRateHz: Double
    let callbackCount: UInt64
    let routeSwitch: RouteSwitchDiagnostics

    static let zero = AudioPerformanceDiagnostics(
        callbackAverageMilliseconds: 0,
        callbackPeakMilliseconds: 0,
        callbackBudgetMilliseconds: 0,
        callbackFramesPerBuffer: 0,
        callbackSampleRateHz: 0,
        callbackCount: 0,
        routeSwitch: .zero
    )

    var hasCallbackData: Bool { callbackCount > 0 }
    var hasCallbackBudget: Bool { callbackBudgetMilliseconds > 0 }
    var hasCallbackFormat: Bool { callbackFramesPerBuffer > 0 && callbackSampleRateHz.isFinite && callbackSampleRateHz > 0 }
    var callbackPeakExceedsBudget: Bool { hasCallbackBudget && callbackPeakMilliseconds > callbackBudgetMilliseconds }
    var hasRouteSwitchData: Bool { routeSwitch.hasData }
}
