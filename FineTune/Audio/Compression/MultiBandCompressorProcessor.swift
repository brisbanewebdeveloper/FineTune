import Foundation
import Darwin.C

/// RT-safe 10-band compressor for per-source dynamic range control.
///
/// The signal is split into ranges aligned to the EQ's 10 band frequencies using
/// one-pole crossover points at the geometric midpoints between adjacent EQ bands.
/// Each range uses independent envelope tracking, downward compression, and
/// fixed makeup gain so quieter content is lifted while louder peaks are reduced.
final class MultiBandCompressorProcessor: @unchecked Sendable {
    /// Snapshot of real-time-readable compressor parameters for a single callback/buffer pass.
    /// The pointed-to storage remains owned by the processor and must only be used while
    /// the processor instance is alive, from the active callback/buffer pass that requested
    /// the snapshot, and not retained across subsequent main-thread settings/sample-rate updates.
    struct ProcessingState {
        let crossoverAlphas: UnsafeMutablePointer<Float>
        let thresholds: UnsafeMutablePointer<Float>
        let ratios: UnsafeMutablePointer<Float>
        let makeupGains: UnsafeMutablePointer<Float>
        let attackCoefficient: Float
        let releaseCoefficient: Float
    }

    private(set) var sampleRate: Double
    private var _currentSettings: CompressorSettings?

    var currentSettings: CompressorSettings? { _currentSettings }
    var isEnabled: Bool { _isEnabled }

    private nonisolated(unsafe) var _isEnabled = false
    private nonisolated(unsafe) var _attackCoefficient: Float = 0.0
    private nonisolated(unsafe) var _releaseCoefficient: Float = 0.0
    private let crossoverAlphas: UnsafeMutablePointer<Float>
    private let thresholds: UnsafeMutablePointer<Float>
    private let ratios: UnsafeMutablePointer<Float>
    private let makeupGains: UnsafeMutablePointer<Float>
    private let statesL: UnsafeMutablePointer<Float>
    private let statesR: UnsafeMutablePointer<Float>
    private let envelopesL: UnsafeMutablePointer<Float>
    private let envelopesR: UnsafeMutablePointer<Float>

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        crossoverAlphas = .allocate(capacity: MultiBandCompressionMath.crossoverCount)
        thresholds = .allocate(capacity: MultiBandCompressionMath.bandCount)
        ratios = .allocate(capacity: MultiBandCompressionMath.bandCount)
        makeupGains = .allocate(capacity: MultiBandCompressionMath.bandCount)
        statesL = .allocate(capacity: MultiBandCompressionMath.crossoverCount)
        statesR = .allocate(capacity: MultiBandCompressionMath.crossoverCount)
        envelopesL = .allocate(capacity: MultiBandCompressionMath.bandCount)
        envelopesR = .allocate(capacity: MultiBandCompressionMath.bandCount)

        crossoverAlphas.initialize(repeating: 0.0, count: MultiBandCompressionMath.crossoverCount)
        thresholds.initialize(repeating: 1.0, count: MultiBandCompressionMath.bandCount)
        ratios.initialize(repeating: 1.0, count: MultiBandCompressionMath.bandCount)
        makeupGains.initialize(repeating: 1.0, count: MultiBandCompressionMath.bandCount)
        statesL.initialize(repeating: 0.0, count: MultiBandCompressionMath.crossoverCount)
        statesR.initialize(repeating: 0.0, count: MultiBandCompressionMath.crossoverCount)
        envelopesL.initialize(repeating: 0.0, count: MultiBandCompressionMath.bandCount)
        envelopesR.initialize(repeating: 0.0, count: MultiBandCompressionMath.bandCount)

        updateCoefficients(for: sampleRate)
        updateSettings(.bypassed)
    }

    deinit {
        crossoverAlphas.deinitialize(count: MultiBandCompressionMath.crossoverCount)
        thresholds.deinitialize(count: MultiBandCompressionMath.bandCount)
        ratios.deinitialize(count: MultiBandCompressionMath.bandCount)
        makeupGains.deinitialize(count: MultiBandCompressionMath.bandCount)
        statesL.deinitialize(count: MultiBandCompressionMath.crossoverCount)
        statesR.deinitialize(count: MultiBandCompressionMath.crossoverCount)
        envelopesL.deinitialize(count: MultiBandCompressionMath.bandCount)
        envelopesR.deinitialize(count: MultiBandCompressionMath.bandCount)
        crossoverAlphas.deallocate()
        thresholds.deallocate()
        ratios.deallocate()
        makeupGains.deallocate()
        statesL.deallocate()
        statesR.deallocate()
        envelopesL.deallocate()
        envelopesR.deallocate()
    }

    func updateSettings(_ settings: CompressorSettings) {
        dispatchPrecondition(condition: .onQueue(.main))
        _currentSettings = settings
        let shouldEnable = settings.isEnabled && settings.clampedAmount > 0

        if !shouldEnable {
            _isEnabled = false
            OSMemoryBarrier()
        }

        let parameters = MultiBandCompressionMath.bandParameters(for: settings.clampedAmount)
        for index in 0..<MultiBandCompressionMath.bandCount {
            thresholds[index] = parameters[index].threshold
            ratios[index] = parameters[index].ratio
            makeupGains[index] = parameters[index].makeupGain
        }
        OSMemoryBarrier()
        _isEnabled = shouldEnable
    }

    func updateSampleRate(_ newRate: Double) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard newRate != sampleRate else { return }
        sampleRate = newRate

        let enabled = _isEnabled
        _isEnabled = false
        OSMemoryBarrier()
        updateCoefficients(for: newRate)
        resetState()
        _isEnabled = enabled
        OSMemoryBarrier()
    }

    func processStereoFrame(left: inout Float, right: inout Float) {
        guard let state = processingState() else { return }
        processStereoFrame(left: &left, right: &right, state: state)
    }

    @inline(__always)
    func processingState() -> ProcessingState? {
        guard _isEnabled else { return nil }
        OSMemoryBarrier()
        return ProcessingState(
            crossoverAlphas: crossoverAlphas,
            thresholds: thresholds,
            ratios: ratios,
            makeupGains: makeupGains,
            attackCoefficient: _attackCoefficient,
            releaseCoefficient: _releaseCoefficient
        )
    }

    @inline(__always)
    func processStereoFrame(left: inout Float, right: inout Float, state: ProcessingState) {
        left = processSample(
            left,
            state: state,
            states: statesL,
            envelopes: envelopesL
        )

        right = processSample(
            right,
            state: state,
            states: statesR,
            envelopes: envelopesR
        )

        if !left.isFinite || !right.isFinite {
            resetState()
            left = 0.0
            right = 0.0
        }
    }

    private func processSample(
        _ sample: Float,
        state: ProcessingState,
        states: UnsafeMutablePointer<Float>,
        envelopes: UnsafeMutablePointer<Float>
    ) -> Float {
        var output: Float = 0.0
        var previousLowpass: Float = 0.0

        for index in 0..<MultiBandCompressionMath.crossoverCount {
            states[index] += state.crossoverAlphas[index] * (sample - states[index])
            let lowpass = states[index]
            let bandSample = lowpass - previousLowpass
            output += compressBand(
                bandSample,
                threshold: state.thresholds[index],
                ratio: state.ratios[index],
                makeupGain: state.makeupGains[index],
                attackCoefficient: state.attackCoefficient,
                releaseCoefficient: state.releaseCoefficient,
                envelope: &envelopes[index]
            )
            previousLowpass = lowpass
        }

        output += compressBand(
            sample - previousLowpass,
            threshold: state.thresholds[MultiBandCompressionMath.bandCount - 1],
            ratio: state.ratios[MultiBandCompressionMath.bandCount - 1],
            makeupGain: state.makeupGains[MultiBandCompressionMath.bandCount - 1],
            attackCoefficient: state.attackCoefficient,
            releaseCoefficient: state.releaseCoefficient,
            envelope: &envelopes[MultiBandCompressionMath.bandCount - 1]
        )

        return output
    }

    private func compressBand(
        _ sample: Float,
        threshold: Float,
        ratio: Float,
        makeupGain: Float,
        attackCoefficient: Float,
        releaseCoefficient: Float,
        envelope: inout Float
    ) -> Float {
        let magnitude = abs(sample)
        let coefficient = magnitude > envelope ? attackCoefficient : releaseCoefficient
        envelope = coefficient * envelope + (1.0 - coefficient) * magnitude

        let gain = MultiBandCompressionMath.compressedGain(
            envelope: envelope,
            threshold: threshold,
            ratio: ratio
        )
        return sample * gain * makeupGain
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

    private func resetState() {
        memset(statesL, 0, MultiBandCompressionMath.crossoverCount * MemoryLayout<Float>.size)
        memset(statesR, 0, MultiBandCompressionMath.crossoverCount * MemoryLayout<Float>.size)
        memset(envelopesL, 0, MultiBandCompressionMath.bandCount * MemoryLayout<Float>.size)
        memset(envelopesR, 0, MultiBandCompressionMath.bandCount * MemoryLayout<Float>.size)
    }
}
