import Foundation

struct ConsolidatedRealtimeBandLevels: Equatable, Sendable {
    let afterCompressor: Float
    let eqGap: Float

    static let zero = ConsolidatedRealtimeBandLevels(afterCompressor: 0.0, eqGap: 0.0)
}

struct RealtimeBandLevels: Equatable, Sendable {
    let original: [Float]
    let afterCompressor: [Float]
    let afterEQ: [Float]

    static let zero = RealtimeBandLevels(
        original: Array(repeating: Float.zero, count: EQSettings.bandCount),
        afterCompressor: Array(repeating: Float.zero, count: EQSettings.bandCount),
        afterEQ: Array(repeating: Float.zero, count: EQSettings.bandCount)
    )

    func normalized() -> RealtimeBandLevels {
        RealtimeBandLevels(
            original: Self.normalizedRow(original),
            afterCompressor: Self.normalizedRow(afterCompressor),
            afterEQ: Self.normalizedRow(afterEQ)
        )
    }

    func maxMerged(with other: RealtimeBandLevels) -> RealtimeBandLevels {
        RealtimeBandLevels(
            original: Self.maxMergedRow(original, other.original),
            afterCompressor: Self.maxMergedRow(afterCompressor, other.afterCompressor),
            afterEQ: Self.maxMergedRow(afterEQ, other.afterEQ)
        )
    }

    func consolidated(using aggregationMode: BandMeterAggregationMode) -> ConsolidatedRealtimeBandLevels {
        let normalizedLevels = normalized()
        let eqGapLevels = zip(normalizedLevels.afterCompressor, normalizedLevels.afterEQ).map { compressor, eq in
            abs(eq - compressor)
        }

        return ConsolidatedRealtimeBandLevels(
            afterCompressor: Self.aggregatedLevel(normalizedLevels.afterCompressor, using: aggregationMode),
            eqGap: Self.aggregatedLevel(eqGapLevels, using: aggregationMode)
        )
    }

    private static func normalizedRow(_ levels: [Float]) -> [Float] {
        let padded = Array(levels.prefix(EQSettings.bandCount))
        let normalized = padded + Array(repeating: Float.zero, count: max(0, EQSettings.bandCount - padded.count))
        return normalized.map { level in
            guard level.isFinite else { return 0.0 }
            return min(max(level, 0.0), 1.0)
        }
    }

    private static func maxMergedRow(_ lhs: [Float], _ rhs: [Float]) -> [Float] {
        let left = normalizedRow(lhs)
        let right = normalizedRow(rhs)
        return zip(left, right).map(max)
    }

    private static func aggregatedLevel(_ levels: [Float], using aggregationMode: BandMeterAggregationMode) -> Float {
        guard !levels.isEmpty else { return 0.0 }

        switch aggregationMode {
        case .average:
            return levels.reduce(0.0, +) / Float(levels.count)
        case .peak:
            return levels.max() ?? 0.0
        }
    }
}
