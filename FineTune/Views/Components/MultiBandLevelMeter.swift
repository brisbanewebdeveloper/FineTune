import SwiftUI

struct MultiBandLevelMeter: View {
    let levels: RealtimeBandLevels
    let isRealtimeAvailable: Bool
    let aggregationMode: BandMeterAggregationMode

    private var statusText: String {
        guard isRealtimeAvailable else { return "Active apps show live compressor changes here" }
        return "Per-band volume level view"
    }

    private var normalizedLevels: RealtimeBandLevels {
        levels.normalized()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Spacer()

                Text(statusText)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            HStack(spacing: DesignTokens.Dimensions.eqColumnSpacing) {
                ForEach(0..<EQSettings.bandCount, id: \.self) { index in
                    MultiBandLevelColumn(
                        level: normalizedLevels.afterCompressor[index],
                        isRealtimeAvailable: isRealtimeAvailable
                    )
                    .frame(
                        width: DesignTokens.Dimensions.eqColumnWidth,
                        height: DesignTokens.Dimensions.eqMeterHeight
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .help("Volume Level")
        }
    }
}

private struct MultiBandLevelColumn: View {
    let level: Float
    let isRealtimeAvailable: Bool

    private var clampedLevel: Float {
        min(max(level, 0.0), 1.0)
    }

    var body: some View {
        VUMeter(
            level: clampedLevel,
            isMuted: !isRealtimeAvailable,
            width: DesignTokens.Dimensions.eqTrackWidth,
            height: DesignTokens.Dimensions.eqMeterHeight,
            profile: .band
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    VStack {
        MultiBandLevelMeter(
            levels: RealtimeBandLevels(
                original: [0.95, 0.82, 0.68, 0.42, 0.36, 0.28, 0.22, 0.18, 0.10, 0.05],
                afterCompressor: [0.88, 0.76, 0.60, 0.40, 0.34, 0.27, 0.21, 0.18, 0.10, 0.05],
                afterEQ: [0.76, 0.70, 0.58, 0.46, 0.38, 0.30, 0.25, 0.20, 0.11, 0.04]
            ),
            isRealtimeAvailable: true,
            aggregationMode: .average
        )
    }
    .padding()
    .frame(width: 540)
    .background {
        RoundedRectangle(cornerRadius: DesignTokens.Dimensions.rowRadius)
            .fill(DesignTokens.Colors.recessedBackground)
    }
    .padding()
    .background(Color.black)
}
