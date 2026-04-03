import Foundation
import Darwin.C

final class MultiBandLevelAnalyzer: @unchecked Sendable {
    struct ProcessingState {
        let crossoverAlphas: UnsafePointer<Float>
        let attackCoefficient: Float
        let releaseCoefficient: Float
    }

    private(set) var sampleRate: Double

    private nonisolated(unsafe) var _enabled = false
    private nonisolated(unsafe) var _attackCoefficient: Float = 0.0
    private nonisolated(unsafe) var _releaseCoefficient: Float = 0.0
    private let crossoverAlphas: UnsafeMutablePointer<Float>
    private let displayLevels: UnsafeMutablePointer<Float>
    private let statesL: UnsafeMutablePointer<Float>
    private let statesR: UnsafeMutablePointer<Float>
    private let envelopesL: UnsafeMutablePointer<Float>
    private let envelopesR: UnsafeMutablePointer<Float>

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        crossoverAlphas = .allocate(capacity: MultiBandCompressionMath.crossoverCount)
        displayLevels = .allocate(capacity: MultiBandCompressionMath.bandCount)
        statesL = .allocate(capacity: MultiBandCompressionMath.crossoverCount)
        statesR = .allocate(capacity: MultiBandCompressionMath.crossoverCount)
        envelopesL = .allocate(capacity: MultiBandCompressionMath.bandCount)
        envelopesR = .allocate(capacity: MultiBandCompressionMath.bandCount)

        crossoverAlphas.initialize(repeating: 0.0, count: MultiBandCompressionMath.crossoverCount)
        displayLevels.initialize(repeating: 0.0, count: MultiBandCompressionMath.bandCount)
        statesL.initialize(repeating: 0.0, count: MultiBandCompressionMath.crossoverCount)
        statesR.initialize(repeating: 0.0, count: MultiBandCompressionMath.crossoverCount)
        envelopesL.initialize(repeating: 0.0, count: MultiBandCompressionMath.bandCount)
        envelopesR.initialize(repeating: 0.0, count: MultiBandCompressionMath.bandCount)

        updateCoefficients(for: sampleRate)
    }

    deinit {
        crossoverAlphas.deinitialize(count: MultiBandCompressionMath.crossoverCount)
        displayLevels.deinitialize(count: MultiBandCompressionMath.bandCount)
        statesL.deinitialize(count: MultiBandCompressionMath.crossoverCount)
        statesR.deinitialize(count: MultiBandCompressionMath.crossoverCount)
        envelopesL.deinitialize(count: MultiBandCompressionMath.bandCount)
        envelopesR.deinitialize(count: MultiBandCompressionMath.bandCount)
        crossoverAlphas.deallocate()
        displayLevels.deallocate()
        statesL.deallocate()
        statesR.deallocate()
        envelopesL.deallocate()
        envelopesR.deallocate()
    }

    func setEnabled(_ enabled: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        _enabled = enabled
        OSMemoryBarrier()

        if !enabled {
            resetState()
        }
    }

    func snapshot() -> [Float] {
        guard _enabled else {
            return RealtimeBandLevels.zero.original
        }

        OSMemoryBarrier()
        return (0..<MultiBandCompressionMath.bandCount).map { index in
            let level = displayLevels[index]
            guard level.isFinite else { return 0.0 }
            return min(max(level, 0.0), 1.0)
        }
    }

    func updateSampleRate(_ newRate: Double) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard newRate != sampleRate else { return }
        sampleRate = newRate

        let wasEnabled = _enabled
        _enabled = false
        OSMemoryBarrier()
        updateCoefficients(for: newRate)
        resetState()
        _enabled = wasEnabled
        OSMemoryBarrier()
    }

    @inline(__always)
    func processingState() -> ProcessingState? {
        guard _enabled else { return nil }
        OSMemoryBarrier()
        return ProcessingState(
            crossoverAlphas: UnsafePointer(crossoverAlphas),
            attackCoefficient: _attackCoefficient,
            releaseCoefficient: _releaseCoefficient
        )
    }

    @inline(__always)
    func processStereoFrame(left: Float, right: Float, state: ProcessingState) {
        analyzeSample(left, state: state, states: statesL, envelopes: envelopesL)
        analyzeSample(right, state: state, states: statesR, envelopes: envelopesR)
        updateDisplayLevels()
    }

    @inline(__always)
    func processBuffer(
        _ samples: UnsafePointer<Float>,
        frameCount: Int,
        channelCount: Int,
        leftChannel: Int,
        rightChannel: Int,
        state: ProcessingState
    ) {
        guard frameCount > 0, channelCount > 0 else { return }

        let safeLeft = min(max(leftChannel, 0), max(channelCount - 1, 0))
        let safeRight = min(max(rightChannel, 0), max(channelCount - 1, 0))

        for frame in 0..<frameCount {
            let base = frame * channelCount
            let left = samples[base + safeLeft]
            let right = samples[base + safeRight]
            processStereoFrame(left: left, right: right, state: state)
        }
    }

    private func updateCoefficients(for sampleRate: Double) {
        for index in 0..<MultiBandCompressionMath.crossoverCount {
            crossoverAlphas[index] = MultiBandCompressionMath.onePoleAlpha(
                cutoff: MultiBandCompressionMath.crossoverFrequencies[index],
                sampleRate: sampleRate
            )
        }
        _attackCoefficient = MultiBandCompressionMath.smoothingCoefficient(
            time: MultiBandCompressionMath.attackTime,
            sampleRate: sampleRate
        )
        _releaseCoefficient = MultiBandCompressionMath.smoothingCoefficient(
            time: MultiBandCompressionMath.releaseTime,
            sampleRate: sampleRate
        )
    }

    @inline(__always)
    private func analyzeSample(
        _ sample: Float,
        state: ProcessingState,
        states: UnsafeMutablePointer<Float>,
        envelopes: UnsafeMutablePointer<Float>
    ) {
        var previousLowpass: Float = 0.0

        for index in 0..<MultiBandCompressionMath.crossoverCount {
            states[index] += state.crossoverAlphas[index] * (sample - states[index])
            let lowpass = states[index]
            let bandSample = lowpass - previousLowpass
            updateEnvelope(
                abs(bandSample),
                attackCoefficient: state.attackCoefficient,
                releaseCoefficient: state.releaseCoefficient,
                envelope: &envelopes[index]
            )
            previousLowpass = lowpass
        }

        updateEnvelope(
            abs(sample - previousLowpass),
            attackCoefficient: state.attackCoefficient,
            releaseCoefficient: state.releaseCoefficient,
            envelope: &envelopes[MultiBandCompressionMath.bandCount - 1]
        )
    }

    @inline(__always)
    private func updateEnvelope(
        _ magnitude: Float,
        attackCoefficient: Float,
        releaseCoefficient: Float,
        envelope: inout Float
    ) {
        let coefficient = magnitude > envelope ? attackCoefficient : releaseCoefficient
        envelope = coefficient * envelope + (1.0 - coefficient) * magnitude
    }

    @inline(__always)
    private func updateDisplayLevels() {
        for index in 0..<MultiBandCompressionMath.bandCount {
            let level = max(envelopesL[index], envelopesR[index])
            displayLevels[index] = level.isFinite ? min(max(level, 0.0), 1.0) : 0.0
        }
    }

    private func resetState() {
        memset(statesL, 0, MultiBandCompressionMath.crossoverCount * MemoryLayout<Float>.size)
        memset(statesR, 0, MultiBandCompressionMath.crossoverCount * MemoryLayout<Float>.size)
        memset(envelopesL, 0, MultiBandCompressionMath.bandCount * MemoryLayout<Float>.size)
        memset(envelopesR, 0, MultiBandCompressionMath.bandCount * MemoryLayout<Float>.size)
        memset(displayLevels, 0, MultiBandCompressionMath.bandCount * MemoryLayout<Float>.size)
    }
}
