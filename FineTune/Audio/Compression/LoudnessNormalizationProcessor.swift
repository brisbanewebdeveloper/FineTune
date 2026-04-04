import Foundation
import Darwin.C

/// RT-safe pre-compression loudness normalization.
///
/// The processor measures a smoothed average across the compressor's 10-band layout,
/// then applies a single broadband gain shift toward a fixed target level. Applying the
/// same shift to every band preserves the source mix while still normalizing each band's
/// contribution before multiband compression runs.
final class LoudnessNormalizationProcessor: @unchecked Sendable {
    struct ProcessingState {
        let crossoverAlphas: UnsafePointer<Float>
        let envelopeAttackCoefficient: Float
        let envelopeReleaseCoefficient: Float
        let gainAttackCoefficient: Float
        let gainReleaseCoefficient: Float
        let targetAverageLevel: Float
        let minimumGain: Float
        let maximumGain: Float
        let silenceFloor: Float
    }

    private enum Constants {
        static let targetAverageLevel: Float = 0.18
        static let minimumGain: Float = 0.5
        static let maximumGain: Float = 2.25
        static let silenceFloor: Float = 0.001
        static let gainAttackTime: Float = 0.020
        static let gainReleaseTime: Float = 0.250
    }

    private(set) var sampleRate: Double
    private var _currentSettings: NormalizationSettings?

    var currentSettings: NormalizationSettings? { _currentSettings }
    var isEnabled: Bool { _normalizationEnabled }

    private nonisolated(unsafe) var _normalizationEnabled = false
    private nonisolated(unsafe) var _envelopeAttackCoefficient: Float = 0.0
    private nonisolated(unsafe) var _envelopeReleaseCoefficient: Float = 0.0
    private nonisolated(unsafe) var _gainAttackCoefficient: Float = 0.0
    private nonisolated(unsafe) var _gainReleaseCoefficient: Float = 0.0
    private nonisolated(unsafe) var currentGain: Float = 1.0
    private let crossoverAlphas: UnsafeMutablePointer<Float>
    private let statesL: UnsafeMutablePointer<Float>
    private let statesR: UnsafeMutablePointer<Float>
    private let envelopesL: UnsafeMutablePointer<Float>
    private let envelopesR: UnsafeMutablePointer<Float>

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        crossoverAlphas = .allocate(capacity: MultiBandCompressionMath.crossoverCount)
        statesL = .allocate(capacity: MultiBandCompressionMath.crossoverCount)
        statesR = .allocate(capacity: MultiBandCompressionMath.crossoverCount)
        envelopesL = .allocate(capacity: MultiBandCompressionMath.bandCount)
        envelopesR = .allocate(capacity: MultiBandCompressionMath.bandCount)

        crossoverAlphas.initialize(repeating: 0.0, count: MultiBandCompressionMath.crossoverCount)
        statesL.initialize(repeating: 0.0, count: MultiBandCompressionMath.crossoverCount)
        statesR.initialize(repeating: 0.0, count: MultiBandCompressionMath.crossoverCount)
        envelopesL.initialize(repeating: 0.0, count: MultiBandCompressionMath.bandCount)
        envelopesR.initialize(repeating: 0.0, count: MultiBandCompressionMath.bandCount)

        updateCoefficients(for: sampleRate)
        updateSettings(.bypassed)
    }

    deinit {
        crossoverAlphas.deinitialize(count: MultiBandCompressionMath.crossoverCount)
        statesL.deinitialize(count: MultiBandCompressionMath.crossoverCount)
        statesR.deinitialize(count: MultiBandCompressionMath.crossoverCount)
        envelopesL.deinitialize(count: MultiBandCompressionMath.bandCount)
        envelopesR.deinitialize(count: MultiBandCompressionMath.bandCount)
        crossoverAlphas.deallocate()
        statesL.deallocate()
        statesR.deallocate()
        envelopesL.deallocate()
        envelopesR.deallocate()
    }

    func updateSettings(_ settings: NormalizationSettings) {
        dispatchPrecondition(condition: .onQueue(.main))
        _currentSettings = settings

        if !settings.isEnabled {
            _normalizationEnabled = false
            OSMemoryBarrier()
            resetState()
            return
        }

        OSMemoryBarrier()
        _normalizationEnabled = true
    }

    func updateSampleRate(_ newRate: Double) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard newRate != sampleRate else { return }
        sampleRate = newRate

        let wasEnabled = _normalizationEnabled
        _normalizationEnabled = false
        OSMemoryBarrier()
        updateCoefficients(for: newRate)
        resetState()
        _normalizationEnabled = wasEnabled
        OSMemoryBarrier()
    }

    @inline(__always)
    func processingState() -> ProcessingState? {
        guard _normalizationEnabled else { return nil }
        OSMemoryBarrier()
        return ProcessingState(
            crossoverAlphas: UnsafePointer(crossoverAlphas),
            envelopeAttackCoefficient: _envelopeAttackCoefficient,
            envelopeReleaseCoefficient: _envelopeReleaseCoefficient,
            gainAttackCoefficient: _gainAttackCoefficient,
            gainReleaseCoefficient: _gainReleaseCoefficient,
            targetAverageLevel: Constants.targetAverageLevel,
            minimumGain: Constants.minimumGain,
            maximumGain: Constants.maximumGain,
            silenceFloor: Constants.silenceFloor
        )
    }

    func processStereoFrame(left: inout Float, right: inout Float) {
        guard let state = processingState() else { return }
        processStereoFrame(left: &left, right: &right, state: state)
    }

    @inline(__always)
    func processStereoFrame(left: inout Float, right: inout Float, state: ProcessingState) {
        processStereoFrameForBuffer(left: &left, right: &right, state: state)
    }

    @inline(__always)
    func processStereoFrameForBuffer(left: inout Float, right: inout Float, state: ProcessingState) {
        analyzeSample(
            left,
            state: state,
            states: statesL,
            envelopes: envelopesL
        )
        analyzeSample(
            right,
            state: state,
            states: statesR,
            envelopes: envelopesR
        )

        let measuredAverage = averageEnvelope()
        let targetGain = Self.targetGain(for: measuredAverage, state: state)
        let coefficient = targetGain < currentGain ? state.gainAttackCoefficient : state.gainReleaseCoefficient
        currentGain = coefficient * currentGain + (1.0 - coefficient) * targetGain

        guard currentGain.isFinite else {
            resetState()
            left = 0.0
            right = 0.0
            return
        }

        left *= currentGain
        right *= currentGain
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
                attackCoefficient: state.envelopeAttackCoefficient,
                releaseCoefficient: state.envelopeReleaseCoefficient,
                envelope: &envelopes[index]
            )
            previousLowpass = lowpass
        }

        updateEnvelope(
            abs(sample - previousLowpass),
            attackCoefficient: state.envelopeAttackCoefficient,
            releaseCoefficient: state.envelopeReleaseCoefficient,
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
    private func averageEnvelope() -> Float {
        var total: Float = 0.0
        for index in 0..<MultiBandCompressionMath.bandCount {
            total += max(envelopesL[index], envelopesR[index])
        }
        return min(max(total, 0.0), 1.0)
    }

    private func updateCoefficients(for sampleRate: Double) {
        for index in 0..<MultiBandCompressionMath.crossoverCount {
            crossoverAlphas[index] = MultiBandCompressionMath.onePoleAlpha(
                cutoff: MultiBandCompressionMath.crossoverFrequencies[index],
                sampleRate: sampleRate
            )
        }
        _envelopeAttackCoefficient = MultiBandCompressionMath.smoothingCoefficient(
            time: MultiBandCompressionMath.attackTime,
            sampleRate: sampleRate
        )
        _envelopeReleaseCoefficient = MultiBandCompressionMath.smoothingCoefficient(
            time: MultiBandCompressionMath.releaseTime,
            sampleRate: sampleRate
        )
        _gainAttackCoefficient = MultiBandCompressionMath.smoothingCoefficient(
            time: Constants.gainAttackTime,
            sampleRate: sampleRate
        )
        _gainReleaseCoefficient = MultiBandCompressionMath.smoothingCoefficient(
            time: Constants.gainReleaseTime,
            sampleRate: sampleRate
        )
    }

    private func resetState() {
        memset(statesL, 0, MultiBandCompressionMath.crossoverCount * MemoryLayout<Float>.size)
        memset(statesR, 0, MultiBandCompressionMath.crossoverCount * MemoryLayout<Float>.size)
        memset(envelopesL, 0, MultiBandCompressionMath.bandCount * MemoryLayout<Float>.size)
        memset(envelopesR, 0, MultiBandCompressionMath.bandCount * MemoryLayout<Float>.size)
        currentGain = 1.0
    }

    @inline(__always)
    private static func targetGain(for measuredAverage: Float, state: ProcessingState) -> Float {
        guard measuredAverage.isFinite, measuredAverage > state.silenceFloor else {
            return 1.0
        }

        let unclampedGain = state.targetAverageLevel / measuredAverage
        guard unclampedGain.isFinite else { return 1.0 }
        return min(max(unclampedGain, state.minimumGain), state.maximumGain)
    }
}
