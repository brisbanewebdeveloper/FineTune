import Foundation
import Darwin.C

/// RT-safe 3-band compressor for per-source dynamic range control.
///
/// The signal is split into low / mid / high bands with two one-pole crossovers.
/// Each band uses independent envelope tracking, downward compression, and
/// fixed makeup gain so quieter content is lifted while louder peaks are reduced.
final class MultiBandCompressorProcessor: @unchecked Sendable {
    private(set) var sampleRate: Double
    private var _currentSettings: CompressorSettings?

    var currentSettings: CompressorSettings? { _currentSettings }
    var isEnabled: Bool { _isEnabled }

    private nonisolated(unsafe) var _isEnabled = false
    private nonisolated(unsafe) var _lowAlpha: Float = 0.0
    private nonisolated(unsafe) var _highAlpha: Float = 0.0
    private nonisolated(unsafe) var _attackCoefficient: Float = 0.0
    private nonisolated(unsafe) var _releaseCoefficient: Float = 0.0

    private nonisolated(unsafe) var _lowThreshold: Float = 1.0
    private nonisolated(unsafe) var _lowRatio: Float = 1.0
    private nonisolated(unsafe) var _lowMakeupGain: Float = 1.0
    private nonisolated(unsafe) var _midThreshold: Float = 1.0
    private nonisolated(unsafe) var _midRatio: Float = 1.0
    private nonisolated(unsafe) var _midMakeupGain: Float = 1.0
    private nonisolated(unsafe) var _highThreshold: Float = 1.0
    private nonisolated(unsafe) var _highRatio: Float = 1.0
    private nonisolated(unsafe) var _highMakeupGain: Float = 1.0

    private var lowStateL: Float = 0.0
    private var lowStateR: Float = 0.0
    private var highStateL: Float = 0.0
    private var highStateR: Float = 0.0
    private var lowEnvelopeL: Float = 0.0
    private var lowEnvelopeR: Float = 0.0
    private var midEnvelopeL: Float = 0.0
    private var midEnvelopeR: Float = 0.0
    private var highEnvelopeL: Float = 0.0
    private var highEnvelopeR: Float = 0.0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        updateCoefficients(for: sampleRate)
        updateSettings(.bypassed)
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
        _lowThreshold = parameters.low.threshold
        _lowRatio = parameters.low.ratio
        _lowMakeupGain = parameters.low.makeupGain
        _midThreshold = parameters.mid.threshold
        _midRatio = parameters.mid.ratio
        _midMakeupGain = parameters.mid.makeupGain
        _highThreshold = parameters.high.threshold
        _highRatio = parameters.high.ratio
        _highMakeupGain = parameters.high.makeupGain
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
        guard _isEnabled else { return }
        OSMemoryBarrier()

        let lowAlpha = _lowAlpha
        let highAlpha = _highAlpha
        let attackCoefficient = _attackCoefficient
        let releaseCoefficient = _releaseCoefficient

        left = processSample(
            left,
            lowAlpha: lowAlpha,
            highAlpha: highAlpha,
            attackCoefficient: attackCoefficient,
            releaseCoefficient: releaseCoefficient,
            lowState: &lowStateL,
            highState: &highStateL,
            lowEnvelope: &lowEnvelopeL,
            midEnvelope: &midEnvelopeL,
            highEnvelope: &highEnvelopeL
        )

        right = processSample(
            right,
            lowAlpha: lowAlpha,
            highAlpha: highAlpha,
            attackCoefficient: attackCoefficient,
            releaseCoefficient: releaseCoefficient,
            lowState: &lowStateR,
            highState: &highStateR,
            lowEnvelope: &lowEnvelopeR,
            midEnvelope: &midEnvelopeR,
            highEnvelope: &highEnvelopeR
        )

        if !left.isFinite || !right.isFinite {
            resetState()
            left = 0.0
            right = 0.0
        }
    }

    private func processSample(
        _ sample: Float,
        lowAlpha: Float,
        highAlpha: Float,
        attackCoefficient: Float,
        releaseCoefficient: Float,
        lowState: inout Float,
        highState: inout Float,
        lowEnvelope: inout Float,
        midEnvelope: inout Float,
        highEnvelope: inout Float
    ) -> Float {
        lowState += lowAlpha * (sample - lowState)
        highState += highAlpha * (sample - highState)

        let lowBand = lowState
        let midLowpass = highState
        let midBand = midLowpass - lowBand
        let highBand = sample - midLowpass

        return compressBand(
            lowBand,
            threshold: _lowThreshold,
            ratio: _lowRatio,
            makeupGain: _lowMakeupGain,
            attackCoefficient: attackCoefficient,
            releaseCoefficient: releaseCoefficient,
            envelope: &lowEnvelope
        ) + compressBand(
            midBand,
            threshold: _midThreshold,
            ratio: _midRatio,
            makeupGain: _midMakeupGain,
            attackCoefficient: attackCoefficient,
            releaseCoefficient: releaseCoefficient,
            envelope: &midEnvelope
        ) + compressBand(
            highBand,
            threshold: _highThreshold,
            ratio: _highRatio,
            makeupGain: _highMakeupGain,
            attackCoefficient: attackCoefficient,
            releaseCoefficient: releaseCoefficient,
            envelope: &highEnvelope
        )
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
        _lowAlpha = MultiBandCompressionMath.onePoleAlpha(
            cutoff: MultiBandCompressionMath.lowCrossoverFrequency,
            sampleRate: sampleRate
        )
        _highAlpha = MultiBandCompressionMath.onePoleAlpha(
            cutoff: MultiBandCompressionMath.highCrossoverFrequency,
            sampleRate: sampleRate
        )
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
        lowStateL = 0.0
        lowStateR = 0.0
        highStateL = 0.0
        highStateR = 0.0
        lowEnvelopeL = 0.0
        lowEnvelopeR = 0.0
        midEnvelopeL = 0.0
        midEnvelopeR = 0.0
        highEnvelopeL = 0.0
        highEnvelopeR = 0.0
    }
}
