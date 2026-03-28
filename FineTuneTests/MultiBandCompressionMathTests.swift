import XCTest
@testable import FineTune

final class MultiBandCompressionMathTests: XCTestCase {
    func testZeroAmountProducesBypassBandParameters() {
        let parameters = MultiBandCompressionMath.bandParameters(for: 0)

        XCTAssertEqual(parameters.low, .init(threshold: 1, ratio: 1, makeupGain: 1))
        XCTAssertEqual(parameters.mid, .init(threshold: 1, ratio: 1, makeupGain: 1))
        XCTAssertEqual(parameters.high, .init(threshold: 1, ratio: 1, makeupGain: 1))
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
