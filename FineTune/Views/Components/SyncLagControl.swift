import SwiftUI

struct SyncLagControl: View {
    let lagMilliseconds: Float
    let sliderWidth: CGFloat
    let label: String
    let onLagChange: (Float) -> Void

    @State private var dragOverrideLag: Double?
    @State private var isIconHovered = false

    private var displayLag: Double {
        dragOverrideLag ?? Double(lagMilliseconds)
    }

    private var iconColor: Color {
        if lagMilliseconds > 0 {
            return DesignTokens.Colors.accentPrimary
        }
        if isIconHovered {
            return DesignTokens.Colors.interactiveHover
        }
        return DesignTokens.Colors.interactiveDefault
    }

    private var sliderValue: Double {
        displayLag / Double(AudioSyncLagRange.maxMilliseconds)
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .frame(
                    minWidth: DesignTokens.Dimensions.minTouchTarget,
                    minHeight: DesignTokens.Dimensions.minTouchTarget
                )
                .contentShape(Rectangle())
                .onHover { isIconHovered = $0 }

            LiquidGlassSlider(
                value: Binding(
                    get: { sliderValue },
                    set: { newValue in
                        let bounded = min(max(newValue, 0), 1)
                        let milliseconds = bounded * Double(AudioSyncLagRange.maxMilliseconds)
                        dragOverrideLag = milliseconds
                        onLagChange(Float(milliseconds))
                    }
                ),
                showUnityMarker: false,
                onEditingChanged: { editing in
                    if !editing {
                        dragOverrideLag = nil
                    }
                }
            )
            .frame(width: sliderWidth)

            Text("\(Int(round(displayLag)))ms")
                .font(DesignTokens.Typography.caption.monospacedDigit())
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 44, alignment: .trailing)
        }
        .help("\(label): \(Int(round(displayLag))) ms")
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(round(displayLag))) milliseconds")
        .animation(DesignTokens.Animation.hover, value: isIconHovered)
    }
}
