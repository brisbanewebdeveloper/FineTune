import XCTest
@testable import FineTune

final class MultiBandCompressionMathTests: XCTestCase {
    func testBandParametersMatchEQBandCount() {
        let parameters = MultiBandCompressionMath.bandParameters(for: 0)

        XCTAssertEqual(parameters.count, EQSettings.bandCount)
        XCTAssertTrue(parameters.allSatisfy { $0 == .init(threshold: 1, ratio: 1, makeupGain: 1) })
    }

    func testCrossoverFrequenciesAlignWithEQBandMidpoints() {
        let expected = zip(EQSettings.frequencies, EQSettings.frequencies.dropFirst()).map {
            Float(sqrt($0 * $1))
        }

        XCTAssertEqual(MultiBandCompressionMath.crossoverFrequencies.count, EQSettings.bandCount - 1)
        XCTAssertEqual(MultiBandCompressionMath.crossoverFrequencies, expected)
    }

    func testCompressionGainReducesSignalsAboveThreshold() {
        let gain = MultiBandCompressionMath.compressedGain(
            envelope: 0.8,
            threshold: 0.4,
            ratio: 4.0
        )

        XCTAssertLessThan(gain, 1.0)
        XCTAssertGreaterThan(gain, 0.0)
    }
}
