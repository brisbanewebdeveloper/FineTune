import Foundation

enum MultiBandCompressionMath {
    struct BandParameters: Equatable {
        let threshold: Float
        let ratio: Float
        let makeupGain: Float
    }

    static let lowCrossoverFrequency: Float = 200.0
    static let highCrossoverFrequency: Float = 4_000.0
    static let attackTime: Float = 0.008
    static let releaseTime: Float = 0.120

    static func bandParameters(for amount: Float) -> (low: BandParameters, mid: BandParameters, high: BandParameters) {
        let clampedAmount = max(CompressorSettings.minAmount, min(CompressorSettings.maxAmount, amount.isFinite ? amount : 1.0))

        func interpolate(_ start: Float, _ end: Float) -> Float {
            start + (end - start) * clampedAmount
        }

        return (
            low: BandParameters(
                threshold: interpolate(1.0, 0.42),
                ratio: interpolate(1.0, 2.3),
                makeupGain: interpolate(1.0, 1.14)
            ),
            mid: BandParameters(
                threshold: interpolate(1.0, 0.28),
                ratio: interpolate(1.0, 3.2),
                makeupGain: interpolate(1.0, 1.32)
            ),
            high: BandParameters(
                threshold: interpolate(1.0, 0.24),
                ratio: interpolate(1.0, 2.0),
                makeupGain: interpolate(1.0, 1.18)
            )
        )
    }

    static func compressedGain(envelope: Float, threshold: Float, ratio: Float) -> Float {
        guard envelope.isFinite, threshold.isFinite, ratio.isFinite,
              envelope > threshold, threshold > 0, ratio > 1 else {
            return 1.0
        }

        let normalized = max(envelope / threshold, 1.0)
        return powf(normalized, (1.0 / ratio) - 1.0)
    }

    static func smoothingCoefficient(time: Float, sampleRate: Double) -> Float {
        guard time.isFinite, time > 0, sampleRate.isFinite, sampleRate > 0 else { return 0.0 }
        return expf(-1.0 / (Float(sampleRate) * time))
    }

    static func onePoleAlpha(cutoff: Float, sampleRate: Double) -> Float {
        guard cutoff.isFinite, cutoff > 0, sampleRate.isFinite, sampleRate > 0 else { return 0.0 }
        let alpha = 1.0 - expf(-2.0 * .pi * cutoff / Float(sampleRate))
        return min(max(alpha, 0.0), 1.0)
    }
}
