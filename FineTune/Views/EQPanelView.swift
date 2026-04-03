// FineTune/Views/EQPanelView.swift
import SwiftUI

struct EQPanelView: View {
    @Binding var settings: EQSettings
    let compressorSettings: CompressorSettings
    let realtimeBandLevels: [Float]
    let showsRealtimeBandLevels: Bool
    let onPresetSelected: (EQPreset) -> Void
    let onSettingsChanged: (EQSettings) -> Void

    private let frequencyLabels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    private var currentPreset: EQPreset? {
        EQPreset.allCases.first { preset in
            preset.settings.bandGains == settings.bandGains
        }
    }

    private var normalizedBandLevels: [Float] {
        let padded = Array(realtimeBandLevels.prefix(EQSettings.bandCount))
        let normalized = padded + Array(repeating: Float.zero, count: max(0, EQSettings.bandCount - padded.count))
        return normalized.map { level in
            guard level.isFinite else { return 0.0 }
            return min(max(level, 0.0), 1.0)
        }
    }

    var body: some View {
        // Entire EQ panel content inside recessed background
        VStack(spacing: 12) {
            // Header: Toggle left, Preset right
            HStack {
                // EQ toggle on left
                HStack(spacing: 6) {
                    Toggle("", isOn: $settings.isEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(0.7)
                        .labelsHidden()
                        .onChange(of: settings.isEnabled) { _, _ in
                            onSettingsChanged(settings)
                        }
                    Text("EQ")
                        .font(DesignTokens.Typography.pickerText)
                        .foregroundStyle(.primary)
                }

                Spacer()

                // Preset picker on right
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("Preset")
                        .font(DesignTokens.Typography.pickerText)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)

                    EQPresetPicker(
                        selectedPreset: currentPreset,
                        onPresetSelected: onPresetSelected
                    )
                }
            }
            .zIndex(1)  // Ensure dropdown renders above sliders

            MultiBandLevelMeter(
                levels: normalizedBandLevels,
                isRealtimeAvailable: showsRealtimeBandLevels,
                isCompressionEnabled: compressorSettings.isEnabled
            )

            // 10-band sliders
            HStack(spacing: 22) {
                ForEach(0..<10, id: \.self) { index in
                    EQSliderView(
                        frequency: frequencyLabels[index],
                        gain: Binding(
                            get: { settings.bandGains[index] },
                            set: { newValue in
                                settings.bandGains[index] = newValue
                                onSettingsChanged(settings)
                            }
                        )
                    )
                    .frame(width: 26, height: 100)
                }
            }
            .opacity(settings.isEnabled ? 1.0 : 0.3)
            .allowsHitTesting(settings.isEnabled)
            .animation(.easeInOut(duration: 0.2), value: settings.isEnabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(DesignTokens.Colors.recessedBackground)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        // No outer background - parent ExpandableGlassRow provides the glass container
    }
}

#Preview {
    // Simulating how it appears inside ExpandableGlassRow
    VStack {
        EQPanelView(
            settings: .constant(EQSettings()),
            compressorSettings: .bypassed,
            realtimeBandLevels: Array(repeating: Float.zero, count: EQSettings.bandCount),
            showsRealtimeBandLevels: true,
            onPresetSelected: { _ in },
            onSettingsChanged: { _ in }
        )
    }
    .padding(.horizontal, DesignTokens.Spacing.sm)
    .padding(.vertical, DesignTokens.Spacing.xs)
    .background {
        RoundedRectangle(cornerRadius: DesignTokens.Dimensions.rowRadius)
            .fill(DesignTokens.Colors.recessedBackground)
    }
    .frame(width: 550)
    .padding()
    .background(Color.black)
}
