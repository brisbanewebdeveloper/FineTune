import XCTest
import AudioToolbox
@testable import FineTune

final class ProcessTapControllerProcessingTests: XCTestCase {
    @MainActor
    func testDisabledCompressorHasNoProcessingStateAndLeavesSamplesUnchanged() throws {
        let disabledCompressor = MultiBandCompressorProcessor(sampleRate: 48_000)
        disabledCompressor.updateSettings(.bypassed)

        XCTAssertNil(disabledCompressor.processingState())

        var left: Float = 0.25
        var right: Float = -0.4
        disabledCompressor.processStereoFrame(left: &left, right: &right)

        XCTAssertEqual(left, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(right, -0.4, accuracy: 0.000_001)
    }

    @MainActor
    func testCompressorProcessingStateProducesSameOutputAsDirectProcessing() throws {
        let settings = CompressorSettings(isEnabled: true, amount: 1.0)
        let perFrameCompressor = MultiBandCompressorProcessor(sampleRate: 48_000)
        perFrameCompressor.updateSettings(settings)

        let bufferedCompressor = MultiBandCompressorProcessor(sampleRate: 48_000)
        bufferedCompressor.updateSettings(settings)
        let bufferedState = try XCTUnwrap(
            bufferedCompressor.processingState(),
            "Expected processingState() to return a snapshot when compression is enabled."
        )

        var perFrameSamples: [Float] = [0.05, -0.04, 0.8, -0.7, 0.08, -0.09, 0.9, -0.85]
        var bufferedSamples = perFrameSamples

        for frame in stride(from: 0, to: perFrameSamples.count, by: 2) {
            var perFrameLeft = perFrameSamples[frame]
            var perFrameRight = perFrameSamples[frame + 1]
            perFrameCompressor.processStereoFrame(left: &perFrameLeft, right: &perFrameRight)
            perFrameSamples[frame] = perFrameLeft
            perFrameSamples[frame + 1] = perFrameRight

            var bufferedLeft = bufferedSamples[frame]
            var bufferedRight = bufferedSamples[frame + 1]
            bufferedCompressor.processStereoFrame(left: &bufferedLeft, right: &bufferedRight, state: bufferedState)
            bufferedSamples[frame] = bufferedLeft
            bufferedSamples[frame + 1] = bufferedRight
        }

        XCTAssertEqual(perFrameSamples.count, bufferedSamples.count)
        for (perFrame, buffered) in zip(perFrameSamples, bufferedSamples) {
            XCTAssertEqual(perFrame, buffered, accuracy: 0.000_001)
        }
    }

    @MainActor
    func testProcessMappedBuffersAppliesEQAfterCompression() {
        var inputSamples: [Float] = [
            0.05, 0.05,
            0.80, 0.80,
            0.08, 0.08,
            0.90, 0.90
        ]
        var outputSamples = Array(repeating: Float.zero, count: inputSamples.count)
        let byteSize = UInt32(inputSamples.count * MemoryLayout<Float>.size)

        let compressorSettings = CompressorSettings(isEnabled: true, amount: 1.0)
        let eqSettings = EQSettings(
            bandGains: [4, 2, 0, 0, 0, 0, -1, -2, -3, -4],
            isEnabled: true
        )

        let compressor = MultiBandCompressorProcessor(sampleRate: 48_000)
        compressor.updateSettings(compressorSettings)

        let eq = EQProcessor(sampleRate: 48_000)
        eq.updateSettings(eqSettings)

        var currentVol: Float = 1.0

        inputSamples.withUnsafeMutableBufferPointer { inputBufferPointer in
            outputSamples.withUnsafeMutableBufferPointer { outputBufferPointer in
                var inputList = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: 2,
                        mDataByteSize: byteSize,
                        mData: UnsafeMutableRawPointer(inputBufferPointer.baseAddress)
                    )
                )
                var outputList = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: 2,
                        mDataByteSize: byteSize,
                        mData: UnsafeMutableRawPointer(outputBufferPointer.baseAddress)
                    )
                )

                withUnsafeMutablePointer(to: &inputList) { inputListPointer in
                    withUnsafeMutablePointer(to: &outputList) { outputListPointer in
                        ProcessTapController.processMappedBuffers(
                            inputBuffers: UnsafeMutableAudioBufferListPointer(inputListPointer),
                            outputBuffers: UnsafeMutableAudioBufferListPointer(outputListPointer),
                            targetVol: 1.0,
                            crossfadeMultiplier: 1.0,
                            rampCoefficient: 1.0,
                            preferredStereoLeft: 0,
                            preferredStereoRight: 1,
                            currentVol: &currentVol,
                            compressorProc: compressor,
                            eqProc: eq,
                            autoEQProc: nil
                        )
                    }
                }
            }
        }

        var expectedSamples = inputSamples
        let expectedCompressor = MultiBandCompressorProcessor(sampleRate: 48_000)
        expectedCompressor.updateSettings(compressorSettings)
        let expectedCompressorState = expectedCompressor.processingState()
        let expectedEQ = EQProcessor(sampleRate: 48_000)
        expectedEQ.updateSettings(eqSettings)

        expectedSamples.withUnsafeMutableBufferPointer { expectedPointer in
            guard let baseAddress = expectedPointer.baseAddress else {
                XCTFail("Expected sample buffer missing base address")
                return
            }

            for frame in stride(from: 0, to: expectedSamples.count, by: 2) {
                var left = baseAddress[frame]
                var right = baseAddress[frame + 1]
                if let expectedCompressorState {
                    expectedCompressor.processStereoFrame(left: &left, right: &right, state: expectedCompressorState)
                }
                baseAddress[frame] = left
                baseAddress[frame + 1] = right
            }

            expectedEQ.process(input: baseAddress, output: baseAddress, frameCount: expectedSamples.count / 2)
            SoftLimiter.processBuffer(baseAddress, sampleCount: expectedSamples.count)
        }

        XCTAssertEqual(outputSamples.count, expectedSamples.count)
        for (actual, expected) in zip(outputSamples, expectedSamples) {
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
    }
}
