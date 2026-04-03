import SwiftUI

struct MultiBandLevelMeter: View {
    let levels: RealtimeBandLevels
    let isRealtimeAvailable: Bool

    private struct MeterRowData: Identifiable {
        let id: String
        let label: String
        let values: [Float]
    }

    private var statusText: String {
        guard isRealtimeAvailable else { return "Active apps show live band energy here" }
        return "Hover a band meter to identify the processing stage"
    }

    private var meterRows: [MeterRowData] {
        let normalized = levels.normalized()
        return [
            MeterRowData(id: "original", label: "Original", values: normalized.original),
            MeterRowData(id: "compressor", label: "After Compressor", values: normalized.afterCompressor),
            MeterRowData(id: "eq", label: "After EQ", values: normalized.afterEQ)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text("Realtime Bands")
                    .font(DesignTokens.Typography.pickerText)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                Spacer()

                Text(statusText)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                ForEach(meterRows) { row in
                    HStack(spacing: DesignTokens.Dimensions.eqColumnSpacing) {
                        ForEach(0..<EQSettings.bandCount, id: \.self) { index in
                            MultiBandLevelColumn(
                                level: row.values[index],
                                isRealtimeAvailable: isRealtimeAvailable
                            )
                            .frame(
                                width: DesignTokens.Dimensions.eqColumnWidth,
                                height: DesignTokens.Dimensions.eqMeterHeight
                            )
                            .help(row.label)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }
}

private struct MultiBandLevelColumn: View {
    let level: Float
    let isRealtimeAvailable: Bool

    private let meterGradient = LinearGradient(
        colors: [
            DesignTokens.Colors.vuGreen,
            DesignTokens.Colors.vuYellow,
            DesignTokens.Colors.vuOrange,
            DesignTokens.Colors.vuRed,
        ],
        startPoint: .bottom,
        endPoint: .top
    )

    private var clampedLevel: CGFloat {
        CGFloat(min(max(level, 0.0), 1.0))
    }

    private var displayedLevel: CGFloat {
        guard clampedLevel > 0 else { return 0 }
        // A mild perceptual curve keeps quieter band activity visibly moving.
        return pow(clampedLevel, 0.6)
    }

    private var fillStyle: AnyShapeStyle {
        isRealtimeAvailable
            ? AnyShapeStyle(meterGradient)
            : AnyShapeStyle(DesignTokens.Colors.vuMuted)
    }

    var body: some View {
        GeometryReader { geometry in
            let fillHeight = geometry.size.height * displayedLevel
            let trackWidth = DesignTokens.Dimensions.eqTrackWidth

            ZStack(alignment: .bottom) {
                Capsule(style: .continuous)
                    .fill(DesignTokens.Colors.sliderTrack.opacity(0.55))
                    .frame(width: trackWidth)

                Rectangle()
                    .fill(DesignTokens.Colors.unityMarker.opacity(0.35))
                    .frame(width: trackWidth + 4, height: 1)
                    .offset(y: geometry.size.height * 0.18)

                Capsule(style: .continuous)
                    .fill(fillStyle)
                    .frame(width: trackWidth, height: max(fillHeight, isRealtimeAvailable && displayedLevel > 0 ? 1 : 0))
                    .opacity(isRealtimeAvailable ? 1.0 : 0.35)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(DesignTokens.Animation.vuMeterLevel, value: displayedLevel)
        }
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
            isRealtimeAvailable: true
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
