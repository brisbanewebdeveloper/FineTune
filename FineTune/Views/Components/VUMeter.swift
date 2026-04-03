// FineTune/Views/Components/VUMeter.swift
import SwiftUI

/// A vertical VU meter visualization for audio levels
/// Shows 8 bars that light up based on audio level with peak hold
struct VUMeter: View {
    enum Profile: Sendable {
        case standard
        case band

        fileprivate var thresholds: [Float] {
            switch self {
            case .standard:
                return Self.decibelThresholds([-40, -30, -20, -14, -10, -6, -3, 0])
            case .band:
                // The band analyzer emits lower, steadier values than the main app meter.
                // Use a more sensitive response curve so live movement remains visible.
                return Self.decibelThresholds([-50, -42, -35, -28, -22, -17, -13, -9])
            }
        }

        private static func decibelThresholds(_ decibels: [Float]) -> [Float] {
            decibels.map { powf(10, $0 / 20) }
        }
    }

    let level: Float
    var isMuted: Bool = false
    var width: CGFloat = 10
    var height: CGFloat = DesignTokens.Dimensions.rowContentHeight - 4
    var profile: Profile = .standard

    @State private var peakLevel: Float = 0
    @State private var decayTask: Task<Void, Never>?

    private let barCount = DesignTokens.Dimensions.vuMeterBarCount

    var body: some View {
        VStack(spacing: 1) {
            ForEach((0..<barCount).reversed(), id: \.self) { index in
                VUMeterBar(
                    index: index,
                    level: level,
                    peakLevel: peakLevel,
                    barCount: barCount,
                    isMuted: isMuted,
                    profile: profile
                )
            }
        }
        .frame(width: width, height: height)
        .onChange(of: level) { _, newLevel in
            if newLevel > peakLevel {
                peakLevel = newLevel
                scheduleDecay()
            } else if peakLevel > newLevel && decayTask == nil {
                scheduleDecay()
            }
        }
        .onDisappear {
            stopDecay()
        }
    }

    /// Hold peak briefly, then decay at 30fps until peak reaches current level
    private func scheduleDecay() {
        stopDecay()
        decayTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(DesignTokens.Timing.vuMeterPeakHold))
            guard !Task.isCancelled else { return }

            // Decay ~24dB over 2.8 seconds (BBC PPM standard)
            // At 30fps: ~84 frames, decay rate ≈ 0.012 per frame
            let decayRate: Float = 0.012
            while !Task.isCancelled, peakLevel > level {
                try? await Task.sleep(for: .seconds(1.0 / 30.0))
                guard !Task.isCancelled else { return }
                withAnimation(DesignTokens.Animation.vuMeterLevel) {
                    peakLevel = max(level, peakLevel - decayRate)
                }
            }
        }
    }

    private func stopDecay() {
        decayTask?.cancel()
        decayTask = nil
    }

    static func threshold(forBar index: Int, profile: Profile) -> Float {
        let thresholds = profile.thresholds
        return thresholds[min(max(index, 0), thresholds.count - 1)]
    }

    static func peakBarIndex(for level: Float, profile: Profile) -> Int {
        let thresholds = profile.thresholds
        var result = 0
        for (index, threshold) in thresholds.enumerated() {
            if level >= threshold {
                result = index
            }
        }
        return result
    }

    static func litBarCount(for level: Float, profile: Profile) -> Int {
        profile.thresholds.filter { level >= $0 }.count
    }
}

/// Individual bar in the VU meter
private struct VUMeterBar: View {
    let index: Int
    let level: Float
    let peakLevel: Float
    let barCount: Int
    var isMuted: Bool = false
    let profile: VUMeter.Profile

    /// Threshold for this bar (0-1) using dB scale
    private var threshold: Float {
        VUMeter.threshold(forBar: index, profile: profile)
    }

    /// Whether this bar should be lit based on current level
    private var isLit: Bool {
        level >= threshold
    }

    /// Whether this bar is the peak indicator
    private var isPeakIndicator: Bool {
        index == VUMeter.peakBarIndex(for: peakLevel, profile: profile) && peakLevel > level
    }

    /// Color for this bar based on its position and mute state
    /// Split: 4 green (0-3), 2 yellow (4-5), 1 orange (6), 1 red (7)
    private var barColor: Color {
        // When muted, show gray to indicate "app is active but muted"
        if isMuted {
            return DesignTokens.Colors.vuMuted
        }
        if index < 4 {
            return DesignTokens.Colors.vuGreen
        } else if index < 6 {
            return DesignTokens.Colors.vuYellow
        } else if index < 7 {
            return DesignTokens.Colors.vuOrange
        } else {
            return DesignTokens.Colors.vuRed
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(isLit || isPeakIndicator ? barColor : DesignTokens.Colors.vuUnlit)
            .animation(DesignTokens.Animation.vuMeterLevel, value: isLit)
    }
}

// MARK: - Previews

#Preview("VU Meter - Vertical") {
    ComponentPreviewContainer {
        VStack(spacing: DesignTokens.Spacing.md) {
            HStack {
                Text("0%")
                    .font(.caption)
                VUMeter(level: 0)
            }

            HStack {
                Text("25%")
                    .font(.caption)
                VUMeter(level: 0.25)
            }

            HStack {
                Text("50%")
                    .font(.caption)
                VUMeter(level: 0.5)
            }

            HStack {
                Text("75%")
                    .font(.caption)
                VUMeter(level: 0.75)
            }

            HStack {
                Text("100%")
                    .font(.caption)
                VUMeter(level: 1.0)
            }
        }
    }
}

#Preview("VU Meter - Animated") {
    struct AnimatedPreview: View {
        @State private var level: Float = 0

        var body: some View {
            ComponentPreviewContainer {
                VStack(spacing: DesignTokens.Spacing.lg) {
                    VUMeter(level: level)

                    Slider(value: Binding(
                        get: { Double(level) },
                        set: { level = Float($0) }
                    ))
                }
            }
        }
    }
    return AnimatedPreview()
}
