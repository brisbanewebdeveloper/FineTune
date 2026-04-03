import Foundation

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
}
