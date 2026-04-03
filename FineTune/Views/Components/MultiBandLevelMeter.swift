import SwiftUI

struct MultiBandLevelMeter: View {
    let levels: [Float]
    let isRealtimeAvailable: Bool
    let isCompressionEnabled: Bool

    private var normalizedLevels: [Float] {
        let padded = Array(levels.prefix(EQSettings.bandCount))
        let normalized = padded + Array(repeating: Float.zero, count: max(0, EQSettings.bandCount - padded.count))
        return normalized.map { level in
            guard level.isFinite else { return 0.0 }
            return min(max(level, 0.0), 1.0)
        }
    }

    private var statusText: String {
        guard isRealtimeAvailable else { return "Active apps show live band energy here" }
        return isCompressionEnabled ? "Live post-compression band energy" : "Live band energy"
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

            HStack(spacing: 22) {
                ForEach(0..<EQSettings.bandCount, id: \.self) { index in
                    MultiBandLevelColumn(
                        level: normalizedLevels[index],
                        isRealtimeAvailable: isRealtimeAvailable
                    )
                    .frame(width: 26, height: 34)
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

    var body: some View {
        GeometryReader { geometry in
            let clampedLevel = CGFloat(min(max(level, 0.0), 1.0))
            let fillHeight = geometry.size.height * clampedLevel

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DesignTokens.Colors.vuUnlit)

                Rectangle()
                    .fill(DesignTokens.Colors.unityMarker.opacity(0.35))
                    .frame(height: 1)
                    .offset(y: geometry.size.height * 0.2)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(meterGradient)
                    .frame(height: fillHeight)
                    .opacity(isRealtimeAvailable ? 1.0 : 0.35)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(DesignTokens.Colors.glassBorder, lineWidth: 0.5)
            }
            .animation(DesignTokens.Animation.vuMeterLevel, value: level)
        }
    }
}

#Preview {
    VStack {
        MultiBandLevelMeter(
            levels: [0.95, 0.82, 0.68, 0.42, 0.36, 0.28, 0.22, 0.18, 0.10, 0.05],
            isRealtimeAvailable: true,
            isCompressionEnabled: true
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
