import Foundation

struct NormalizationSettings: Codable, Equatable {
    /// Whether pre-compression loudness normalization is active for this source.
    var isEnabled: Bool

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    }

    static let bypassed = NormalizationSettings()
}
