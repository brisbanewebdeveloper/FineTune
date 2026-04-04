import XCTest
@testable import FineTune

final class LoudnessNormalizationProcessorTests: XCTestCase {
    @MainActor
    func testDisabledProcessorLeavesSamplesUnchanged() {
        let processor = LoudnessNormalizationProcessor(sampleRate: 48_000)
        processor.updateSettings(.bypassed)

        XCTAssertNil(processor.processingState())

        var left: Float = 0.25
        var right: Float = -0.125
        processor.processStereoFrame(left: &left, right: &right)

        XCTAssertEqual(left, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(right, -0.125, accuracy: 0.000_001)
    }

    @MainActor
    func testProcessingStateMatchesDirectProcessing() throws {
        let settings = NormalizationSettings(isEnabled: true)
        let perFrameProcessor = LoudnessNormalizationProcessor(sampleRate: 48_000)
        perFrameProcessor.updateSettings(settings)

        let bufferedProcessor = LoudnessNormalizationProcessor(sampleRate: 48_000)
        bufferedProcessor.updateSettings(settings)
        let bufferedState = try XCTUnwrap(
            bufferedProcessor.processingState(),
            "Expected processing state when normalization is enabled."
        )

        var perFrameSamples: [Float] = [0.04, -0.03, 0.07, -0.06, 0.11, -0.10, 0.14, -0.12]
        var bufferedSamples = perFrameSamples

        for frame in stride(from: 0, to: perFrameSamples.count, by: 2) {
            var perFrameLeft = perFrameSamples[frame]
            var perFrameRight = perFrameSamples[frame + 1]
            perFrameProcessor.processStereoFrame(left: &perFrameLeft, right: &perFrameRight)
            perFrameSamples[frame] = perFrameLeft
            perFrameSamples[frame + 1] = perFrameRight

            var bufferedLeft = bufferedSamples[frame]
            var bufferedRight = bufferedSamples[frame + 1]
            bufferedProcessor.processStereoFrameForBuffer(left: &bufferedLeft, right: &bufferedRight, state: bufferedState)
            bufferedSamples[frame] = bufferedLeft
            bufferedSamples[frame + 1] = bufferedRight
        }

        for (perFrame, buffered) in zip(perFrameSamples, bufferedSamples) {
            XCTAssertEqual(perFrame, buffered, accuracy: 0.000_001)
        }
    }

    @MainActor
    func testQuietSignalBoostsAndHotSignalAttenuates() {
        let quietProcessor = LoudnessNormalizationProcessor(sampleRate: 48_000)
        quietProcessor.updateSettings(NormalizationSettings(isEnabled: true))

        var quietLeft: Float = 0.05
        var quietRight: Float = 0.05
        for _ in 0..<4096 {
            quietLeft = 0.05
            quietRight = 0.05
            quietProcessor.processStereoFrame(left: &quietLeft, right: &quietRight)
        }

        let hotProcessor = LoudnessNormalizationProcessor(sampleRate: 48_000)
        hotProcessor.updateSettings(NormalizationSettings(isEnabled: true))

        var hotLeft: Float = 0.60
        var hotRight: Float = 0.60
        for _ in 0..<4096 {
            hotLeft = 0.60
            hotRight = 0.60
            hotProcessor.processStereoFrame(left: &hotLeft, right: &hotRight)
        }

        XCTAssertGreaterThan(quietLeft, 0.05)
        XCTAssertLessThan(hotLeft, 0.60)
        XCTAssertEqual(quietLeft, quietRight, accuracy: 0.000_001)
        XCTAssertEqual(hotLeft, hotRight, accuracy: 0.000_001)
    }

    @MainActor
    func testSilenceDoesNotProduceNaN() {
        let processor = LoudnessNormalizationProcessor(sampleRate: 48_000)
        processor.updateSettings(NormalizationSettings(isEnabled: true))

        var left: Float = 0.0
        var right: Float = 0.0
        for _ in 0..<1024 {
            processor.processStereoFrame(left: &left, right: &right)
        }

        XCTAssertTrue(left.isFinite)
        XCTAssertTrue(right.isFinite)
        XCTAssertEqual(left, 0.0, accuracy: 0.000_001)
        XCTAssertEqual(right, 0.0, accuracy: 0.000_001)
    }
}
