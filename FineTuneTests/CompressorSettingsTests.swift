import XCTest
@testable import FineTune

final class CompressorSettingsTests: XCTestCase {
    func testInitClampsAmountIntoSupportedRange() {
        XCTAssertEqual(CompressorSettings(isEnabled: true, amount: -1).amount, 0)
        XCTAssertEqual(CompressorSettings(isEnabled: true, amount: 3).amount, 1)
    }

    func testDecodeDefaultsMissingFields() throws {
        let settings = try JSONDecoder().decode(CompressorSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(settings, .bypassed)
        XCTAssertEqual(settings.clampedAmount, 1.0)
    }
}
