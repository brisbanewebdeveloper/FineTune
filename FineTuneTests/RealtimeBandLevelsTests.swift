import Testing
@testable import FineTune

@Suite("RealtimeBandLevels — Consolidated metrics")
struct RealtimeBandLevelsTests {

    @Test("Average aggregation uses the mean of compressor and EQ-gap bands")
    func averageAggregation() {
        let levels = RealtimeBandLevels(
            original: Array(repeating: 0.0, count: EQSettings.bandCount),
            afterCompressor: [1.0, 0.5, 0.25, 0.0, 0.75, 0.5, 0.25, 0.0, 1.0, 0.5],
            afterEQ: [0.5, 0.5, 0.5, 0.0, 0.5, 0.25, 0.25, 0.0, 0.5, 0.25]
        )

        let consolidated = levels.consolidated(using: .average)

        #expect(abs(consolidated.afterCompressor - 0.475) < 0.0001)
        #expect(abs(consolidated.eqGap - 0.2) < 0.0001)
    }

    @Test("Peak aggregation uses the strongest normalized compressor band and EQ gap")
    func peakAggregation() {
        let levels = RealtimeBandLevels(
            original: Array(repeating: 0.0, count: EQSettings.bandCount),
            afterCompressor: [0.2, 0.4, 0.95, 0.1, 0.3, 0.7, 0.5, 0.2, 0.1, 0.05],
            afterEQ: [0.1, 0.9, 0.25, 0.1, 0.3, 0.6, 0.1, 0.2, 0.1, 0.05]
        )

        let consolidated = levels.consolidated(using: .peak)

        #expect(abs(consolidated.afterCompressor - 0.95) < 0.0001)
        #expect(abs(consolidated.eqGap - 0.7) < 0.0001)
    }

    @Test("Consolidated metrics normalize out-of-range inputs before aggregation")
    func consolidatedMetricsNormalizeInputs() {
        let levels = RealtimeBandLevels(
            original: Array(repeating: 0.0, count: EQSettings.bandCount),
            afterCompressor: [2.0, -1.0, 0.5, Float.nan, 0.25, 0.0, 0.5, 0.25, 0.0, 0.75],
            afterEQ: [0.1, 3.0, -4.0, 0.2, 0.5, 0.0, 0.5, 0.75, Float.infinity, 0.5]
        )

        let consolidated = levels.consolidated(using: .average)

        #expect(abs(consolidated.afterCompressor - 0.325) < 0.0001)
        #expect(abs(consolidated.eqGap - 0.36) < 0.0001)
    }
}
