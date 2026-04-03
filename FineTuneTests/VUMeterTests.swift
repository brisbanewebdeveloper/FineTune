import Testing
@testable import FineTune

@Suite("VUMeter profile mapping")
struct VUMeterTests {

    @Test("Standard profile preserves existing floor and ceiling")
    func standardProfileThresholdRange() {
        #expect(abs(VUMeter.threshold(forBar: 0, profile: .standard) - 0.01) < 0.000_001)
        #expect(abs(VUMeter.threshold(forBar: 7, profile: .standard) - 1.0) < 0.000_001)
    }

    @Test("Band profile is more sensitive than standard")
    func bandProfileIsMoreSensitive() {
        let quietBandLevel: Float = 0.05
        #expect(VUMeter.litBarCount(for: quietBandLevel, profile: .band) > VUMeter.litBarCount(for: quietBandLevel, profile: .standard))
    }

    @Test("Band profile never requires more level than standard for the same bar")
    func bandThresholdsAreNotHigher() {
        for index in 0..<DesignTokens.Dimensions.vuMeterBarCount {
            #expect(VUMeter.threshold(forBar: index, profile: .band) <= VUMeter.threshold(forBar: index, profile: .standard))
        }
    }
}
