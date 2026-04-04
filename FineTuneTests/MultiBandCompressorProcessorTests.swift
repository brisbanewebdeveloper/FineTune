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

    func testBufferedMeterRefreshMatchesPerFrameProcessing() throws {
        let settings = CompressorSettings(isEnabled: true, amount: 1.0)
        let perFrameProcessor = MultiBandCompressorProcessor(sampleRate: 48_000)
        let bufferedProcessor = MultiBandCompressorProcessor(sampleRate: 48_000)

        runOnMain {
            perFrameProcessor.updateSettings(settings)
            perFrameProcessor.setMeteringEnabled(true)
            bufferedProcessor.updateSettings(settings)
            bufferedProcessor.setMeteringEnabled(true)
        }

        let bufferedState = try XCTUnwrap(bufferedProcessor.processingState())
        var perFrameSamples: [Float] = [0.05, -0.04, 0.8, -0.7, 0.08, -0.09, 0.9, -0.85]
        var bufferedSamples = perFrameSamples

        for frame in stride(from: 0, to: perFrameSamples.count, by: 2) {
            var directLeft = perFrameSamples[frame]
            var directRight = perFrameSamples[frame + 1]
            perFrameProcessor.processStereoFrame(left: &directLeft, right: &directRight)
            perFrameSamples[frame] = directLeft
            perFrameSamples[frame + 1] = directRight

            var bufferedLeft = bufferedSamples[frame]
            var bufferedRight = bufferedSamples[frame + 1]
            bufferedProcessor.processStereoFrameForBuffer(left: &bufferedLeft, right: &bufferedRight, state: bufferedState)
            bufferedSamples[frame] = bufferedLeft
            bufferedSamples[frame + 1] = bufferedRight
        }

        bufferedProcessor.refreshDisplayLevels(state: bufferedState)

        XCTAssertEqual(perFrameSamples.count, bufferedSamples.count)
        for (perFrame, buffered) in zip(perFrameSamples, bufferedSamples) {
            XCTAssertEqual(perFrame, buffered, accuracy: 0.000_001)
        }

        let perFrameLevels = perFrameProcessor.bandLevelsSnapshot()
        let bufferedLevels = bufferedProcessor.bandLevelsSnapshot()
        XCTAssertEqual(perFrameLevels.count, bufferedLevels.count)
        for (perFrame, buffered) in zip(perFrameLevels, bufferedLevels) {
            XCTAssertEqual(perFrame, buffered, accuracy: 0.000_001)
        }
    }

    private func runOnMain(_ operation: () -> Void) {
        if Thread.isMainThread {
            operation()
        } else {
            DispatchQueue.main.sync(execute: operation)
        }
    }
}
