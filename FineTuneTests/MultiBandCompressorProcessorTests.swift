import XCTest
@testable import FineTune

final class MultiBandCompressorProcessorTests: XCTestCase {
    func testBypassedProcessorCanMeterWithoutChangingSignal() {
        let processor = MultiBandCompressorProcessor(sampleRate: 48_000)
        runOnMain {
            processor.updateSettings(.bypassed)
            processor.setMeteringEnabled(true)
        }

        var left: Float = 0.5
        var right: Float = 0.25
        processor.processStereoFrame(left: &left, right: &right)

        XCTAssertEqual(left, 0.5, accuracy: 0.0001)
        XCTAssertEqual(right, 0.25, accuracy: 0.0001)

        let levels = processor.bandLevelsSnapshot()
        XCTAssertEqual(levels.count, EQSettings.bandCount)
        XCTAssertTrue(levels.contains(where: { $0 > 0 }))
    }

    func testDisablingMeteringClearsBandLevelsWhenCompressionIsOff() {
        let processor = MultiBandCompressorProcessor(sampleRate: 48_000)
        runOnMain {
            processor.updateSettings(.bypassed)
            processor.setMeteringEnabled(true)
        }

        var left: Float = 0.4
        var right: Float = 0.4
        processor.processStereoFrame(left: &left, right: &right)

        runOnMain {
            processor.setMeteringEnabled(false)
        }

        XCTAssertEqual(
            processor.bandLevelsSnapshot(),
            Array(repeating: Float.zero, count: EQSettings.bandCount)
        )
    }

    private func runOnMain(_ operation: () -> Void) {
        if Thread.isMainThread {
            operation()
        } else {
            DispatchQueue.main.sync(execute: operation)
        }
    }
}
