import Foundation

enum MultiBandCompressionMath {
    struct BandParameters: Equatable {
        let threshold: Float
        let ratio: Float
        let makeupGain: Float
    }

    static let bandCount = EQSettings.bandCount
    static let crossoverCount = bandCount - 1
    static let attackTime: Float = 0.008
    static let releaseTime: Float = 0.120

    /// Compression ranges align with the EQ's 10 center frequencies.
    /// Each crossover sits at the geometric midpoint between adjacent EQ bands.
    static let crossoverFrequencies: [Float] = zip(EQSettings.frequencies, EQSettings.frequencies.dropFirst()).map {
        Float(sqrt($0 * $1))
    }

    static func bandParameters(for amount: Float) -> [BandParameters] {
        let clampedAmount = max(CompressorSettings.minAmount, min(CompressorSettings.maxAmount, amount.isFinite ? amount : 1.0))

        func interpolate(_ start: Float, _ end: Float) -> Float {
            start + (end - start) * clampedAmount
        }

        let targets: [(threshold: Float, ratio: Float, makeupGain: Float)] = [
            (0.42, 2.3, 1.14),
            (0.42, 2.3, 1.14),
            (0.42, 2.3, 1.14),
            (0.28, 3.2, 1.32),
            (0.28, 3.2, 1.32),
            (0.28, 3.2, 1.32),
            (0.28, 3.2, 1.32),
            (0.24, 2.0, 1.18),
            (0.24, 2.0, 1.18),
            (0.24, 2.0, 1.18)
        ]

        return targets.map { target in
            BandParameters(
                threshold: interpolate(1.0, target.threshold),
                ratio: interpolate(1.0, target.ratio),
                makeupGain: interpolate(1.0, target.makeupGain)
            )
        }
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
