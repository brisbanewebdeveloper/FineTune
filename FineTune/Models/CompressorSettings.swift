import Foundation

struct CompressorSettings: Codable, Equatable {
    static let minAmount: Float = 0.0
    static let maxAmount: Float = 1.0

    /// Whether per-source multiband compression is active.
    var isEnabled: Bool

    /// Compression intensity from 0.0 (bypass) to 1.0 (full preset curve).
    var amount: Float

    init(isEnabled: Bool = false, amount: Float = 1.0) {
        self.isEnabled = isEnabled
        self.amount = Self.normalizeAmount(amount)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        let decodedAmount = try container.decodeIfPresent(Float.self, forKey: .amount) ?? 1.0
        self.amount = Self.normalizeAmount(decodedAmount)
    }

    var clampedAmount: Float { Self.normalizeAmount(amount) }

    private static func normalizeAmount(_ amount: Float) -> Float {
        guard amount.isFinite else { return 1.0 }
        return max(minAmount, min(maxAmount, amount))
    }

    static let bypassed = CompressorSettings()
}
