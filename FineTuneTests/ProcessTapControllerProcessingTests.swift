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

        let expectedFrameCount = expectedSamples.count / 2
        expectedSamples.withUnsafeMutableBufferPointer { expectedPointer in
            guard let baseAddress = expectedPointer.baseAddress else {
                XCTFail("Expected sample buffer missing base address")
                return
            }

            for frame in stride(from: 0, to: expectedFrameCount * 2, by: 2) {
                var left = baseAddress[frame]
                var right = baseAddress[frame + 1]
                if let expectedCompressorState {
                    expectedCompressor.processStereoFrame(left: &left, right: &right, state: expectedCompressorState)
                }
                baseAddress[frame] = left
                baseAddress[frame + 1] = right
            }

            expectedEQ.process(input: baseAddress, output: baseAddress, frameCount: expectedFrameCount)
            SoftLimiter.processBuffer(baseAddress, sampleCount: expectedFrameCount * 2)
        }

        XCTAssertEqual(outputSamples.count, expectedSamples.count)
        for (actual, expected) in zip(outputSamples, expectedSamples) {
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
    }

    @MainActor
    func testProcessMappedBuffersCapturesRealtimeBandLevelsAcrossCheckpoints() {
        var inputSamples: [Float] = [
            0.12, 0.08,
            0.90, 0.72,
            0.24, 0.16,
            0.84, 0.68,
            0.18, 0.10,
            0.76, 0.58
        ]
        var outputSamples = Array(repeating: Float.zero, count: inputSamples.count)
        let byteSize = UInt32(inputSamples.count * MemoryLayout<Float>.size)

        let compressorSettings = CompressorSettings(isEnabled: true, amount: 1.0)
        let eqSettings = EQSettings(
            bandGains: [5, 3, 1, 0, -1, -2, -3, -4, -5, -6],
            isEnabled: true
        )

        let compressor = MultiBandCompressorProcessor(sampleRate: 48_000)
        compressor.updateSettings(compressorSettings)

        let eq = EQProcessor(sampleRate: 48_000)
        eq.updateSettings(eqSettings)

        let originalMeter = MultiBandLevelAnalyzer(sampleRate: 48_000)
        originalMeter.setEnabled(true)
        let compressedMeter = MultiBandLevelAnalyzer(sampleRate: 48_000)
        compressedMeter.setEnabled(true)
        let equalizedMeter = MultiBandLevelAnalyzer(sampleRate: 48_000)
        equalizedMeter.setEnabled(true)

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
                            autoEQProc: nil,
                            originalBandAnalyzer: originalMeter,
                            compressedBandAnalyzer: compressedMeter,
                            equalizedBandAnalyzer: equalizedMeter
                        )
                    }
                }
            }
        }

        let actualLevels = RealtimeBandLevels(
            original: originalMeter.snapshot(),
            afterCompressor: compressedMeter.snapshot(),
            afterEQ: equalizedMeter.snapshot()
        )

        let expectedOriginalMeter = MultiBandLevelAnalyzer(sampleRate: 48_000)
        expectedOriginalMeter.setEnabled(true)
        analyzeStereoFrames(inputSamples, with: expectedOriginalMeter)

        var compressedSamples = inputSamples
        let expectedCompressor = MultiBandCompressorProcessor(sampleRate: 48_000)
        expectedCompressor.updateSettings(compressorSettings)
        let expectedCompressorState = try? XCTUnwrap(expectedCompressor.processingState())
        if let expectedCompressorState {
            for frame in stride(from: 0, to: compressedSamples.count, by: 2) {
                var left = compressedSamples[frame]
                var right = compressedSamples[frame + 1]
                expectedCompressor.processStereoFrame(left: &left, right: &right, state: expectedCompressorState)
                compressedSamples[frame] = left
                compressedSamples[frame + 1] = right
            }
        } else {
            XCTFail("Expected compression state for meter verification")
        }

        let expectedCompressedMeter = MultiBandLevelAnalyzer(sampleRate: 48_000)
        expectedCompressedMeter.setEnabled(true)
        analyzeStereoFrames(compressedSamples, with: expectedCompressedMeter)

        var equalizedSamples = compressedSamples
        let expectedEQ = EQProcessor(sampleRate: 48_000)
        expectedEQ.updateSettings(eqSettings)
        let equalizedFrameCount = equalizedSamples.count / 2
        equalizedSamples.withUnsafeMutableBufferPointer { bufferPointer in
            guard let baseAddress = bufferPointer.baseAddress else {
                XCTFail("Expected EQ buffer base address")
                return
            }

            expectedEQ.process(input: baseAddress, output: baseAddress, frameCount: equalizedFrameCount)
        }

        let expectedEqualizedMeter = MultiBandLevelAnalyzer(sampleRate: 48_000)
        expectedEqualizedMeter.setEnabled(true)
        analyzeStereoFrames(equalizedSamples, with: expectedEqualizedMeter)

        let expectedLevels = RealtimeBandLevels(
            original: expectedOriginalMeter.snapshot(),
            afterCompressor: expectedCompressedMeter.snapshot(),
            afterEQ: expectedEqualizedMeter.snapshot()
        )

        XCTAssertBandRowsEqual(actualLevels.original, expectedLevels.original)
        XCTAssertBandRowsEqual(actualLevels.afterCompressor, expectedLevels.afterCompressor)
        XCTAssertBandRowsEqual(actualLevels.afterEQ, expectedLevels.afterEQ)

        XCTAssertTrue(actualLevels.original.contains(where: { $0 > 0 }))
        XCTAssertTrue(actualLevels.afterCompressor.contains(where: { $0 > 0 }))
        XCTAssertTrue(actualLevels.afterEQ.contains(where: { $0 > 0 }))
        XCTAssertNotEqual(actualLevels.original, actualLevels.afterCompressor)
        XCTAssertNotEqual(actualLevels.afterCompressor, actualLevels.afterEQ)
    }

    private func analyzeStereoFrames(_ samples: [Float], with analyzer: MultiBandLevelAnalyzer) {
        guard let state = analyzer.processingState() else {
            XCTFail("Expected analyzer processing state")
            return
        }

        for frame in stride(from: 0, to: samples.count, by: 2) {
            analyzer.processStereoFrame(left: samples[frame], right: samples[frame + 1], state: state)
        }
    }

    private func XCTAssertBandRowsEqual(
        _ actual: [Float],
        _ expected: [Float],
        accuracy: Float = 0.000_001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualValue, expectedValue) in zip(actual, expected) {
            XCTAssertEqual(actualValue, expectedValue, accuracy: accuracy, file: file, line: line)
        }
    }
}
