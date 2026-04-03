// FineTune/Views/Rows/AppRowControls.swift
import SwiftUI

/// Shared controls for app rows: mute button, volume slider, DSP controls, device picker, EQ button.
/// Used by both AppRow (active apps) and InactiveAppRow (pinned inactive apps).
struct AppRowControls: View {
    private static let compressionSliderWidth = DesignTokens.Dimensions.sliderWidth - DesignTokens.Dimensions.minTouchTarget - DesignTokens.Spacing.xs

    let volume: Float
    let isMuted: Bool
    let devices: [AudioDevice]
    let selectedDeviceUID: String
    let selectedDeviceUIDs: Set<String>
    let isFollowingDefault: Bool
    let defaultDeviceUID: String?
    let deviceSelectionMode: DeviceSelectionMode
    let boost: BoostLevel
    let compressorSettings: CompressorSettings
    let isEQExpanded: Bool
    let onVolumeChange: (Float) -> Void
    let onMuteChange: (Bool) -> Void
    let onBoostChange: (BoostLevel) -> Void
    let onCompressionChange: (CompressorSettings) -> Void
    let onDeviceSelected: (String) -> Void
    let onDevicesSelected: (Set<String>) -> Void
    let onDeviceModeChange: (DeviceSelectionMode) -> Void
    let onSelectFollowDefault: () -> Void
    let onEQToggle: () -> Void

    @State private var dragOverrideValue: Double?
    @State private var isEQButtonHovered = false

    private var sliderValue: Double {
        dragOverrideValue ?? VolumeMapping.gainToSlider(volume)
    }

    private var showMutedIcon: Bool { isMuted || sliderValue == 0 }

    private var eqButtonColor: Color {
        if isEQExpanded {
            return DesignTokens.Colors.interactiveActive
        } else if isEQButtonHovered {
            return DesignTokens.Colors.interactiveHover
        } else {
            return DesignTokens.Colors.interactiveDefault
        }
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // Mute button
            MuteButton(isMuted: showMutedIcon) {
                if showMutedIcon {
                    if volume == 0 {
                        onVolumeChange(1.0)
                    }
                    onMuteChange(false)
                } else {
                    onMuteChange(true)
                }
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                // Volume slider
                LiquidGlassSlider(
                    value: Binding(
                        get: { sliderValue },
                        set: { newValue in
                            dragOverrideValue = newValue
                            let gain = VolumeMapping.sliderToGain(newValue)
                            onVolumeChange(gain)
                            if isMuted {
                                onMuteChange(false)
                            }
                        }
                    ),
                    showUnityMarker: false,
                    onEditingChanged: { editing in
                        if !editing {
                            dragOverrideValue = nil
                        }
                    }
                )
                .frame(width: DesignTokens.Dimensions.sliderWidth)
                .opacity(showMutedIcon ? 0.5 : 1.0)

                CompressionControl(
                    settings: compressorSettings,
                    sliderWidth: Self.compressionSliderWidth,
                    onSettingsChange: onCompressionChange
                )
            }

            // Editable volume percentage (shows slider position, not raw gain)
            EditablePercentage(
                percentage: Binding(
                    get: {
                        Int(round(sliderValue * 100))
                    },
                    set: { newPercentage in
                        let sliderPos = Double(newPercentage) / 100.0
                        let gain = VolumeMapping.sliderToGain(sliderPos)
                        onVolumeChange(gain)
                    }
                ),
                range: 0...100
            )

            // Boost chevrons
            BoostChevrons(level: boost, onTap: { onBoostChange(boost.next) })

            // Device picker
            DevicePicker(
                devices: devices,
                selectedDeviceUID: selectedDeviceUID,
                selectedDeviceUIDs: selectedDeviceUIDs,
                isFollowingDefault: isFollowingDefault,
                defaultDeviceUID: defaultDeviceUID,
                mode: deviceSelectionMode,
                onModeChange: onDeviceModeChange,
                onDeviceSelected: onDeviceSelected,
                onDevicesSelected: onDevicesSelected,
                onSelectFollowDefault: onSelectFollowDefault,
                showModeToggle: true,
                triggerWidth: 105
            )

            // EQ button
            Button {
                onEQToggle()
            } label: {
                ZStack {
                    Image(systemName: "slider.vertical.3")
                        .opacity(isEQExpanded ? 0 : 1)
                        .rotationEffect(.degrees(isEQExpanded ? 90 : 0))

                    Image(systemName: "xmark")
                        .opacity(isEQExpanded ? 1 : 0)
                        .rotationEffect(.degrees(isEQExpanded ? 0 : -90))
                }
                .font(.system(size: 12))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(eqButtonColor)
                .frame(
                    minWidth: DesignTokens.Dimensions.minTouchTarget,
                    minHeight: DesignTokens.Dimensions.minTouchTarget
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isEQExpanded ? "Close Equalizer" : "Equalizer")
            .onHover { isEQButtonHovered = $0 }
            .help(isEQExpanded ? "Close Equalizer" : "Equalizer")
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isEQExpanded)
            .animation(DesignTokens.Animation.hover, value: isEQButtonHovered)
        }
        .fixedSize()
    }
}

private struct CompressionControl: View {
    let settings: CompressorSettings
    let sliderWidth: CGFloat
    let onSettingsChange: (CompressorSettings) -> Void

    @State private var dragOverrideAmount: Double?
    @State private var isIconHovered = false

    private var displayAmount: Double {
        dragOverrideAmount ?? Double(settings.clampedAmount)
    }

    private var iconColor: Color {
        if settings.isEnabled {
            return DesignTokens.Colors.accentPrimary
        } else if isIconHovered {
            return DesignTokens.Colors.interactiveHover
        } else {
            return DesignTokens.Colors.interactiveDefault
        }
    }

    private var sliderOpacity: Double {
        settings.isEnabled ? 1.0 : 0.45
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Button {
                onSettingsChange(
                    CompressorSettings(
                        isEnabled: !settings.isEnabled,
                        amount: settings.clampedAmount
                    )
                )
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconColor)
                    .frame(
                        minWidth: DesignTokens.Dimensions.minTouchTarget,
                        minHeight: DesignTokens.Dimensions.minTouchTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isIconHovered = $0 }
            .help(settings.isEnabled ? "Disable multiband compression" : "Enable multiband compression")
            .accessibilityLabel(settings.isEnabled ? "Disable multiband compression" : "Enable multiband compression")
            .animation(DesignTokens.Animation.hover, value: isIconHovered)
            .animation(.snappy(duration: 0.2), value: settings.isEnabled)

            LiquidGlassSlider(
                value: Binding(
                    get: { displayAmount },
                    set: { newValue in
                        dragOverrideAmount = newValue
                        onSettingsChange(
                            CompressorSettings(
                                isEnabled: settings.isEnabled,
                                amount: Float(newValue)
                            )
                        )
                    }
                ),
                showUnityMarker: false,
                onEditingChanged: { editing in
                    if !editing {
                        dragOverrideAmount = nil
                    }
                }
            )
            .frame(width: sliderWidth)
            .opacity(sliderOpacity)
            .help("Compression amount: \(Int(round(displayAmount * 100)))%")
            .accessibilityLabel("Compression amount")
            .accessibilityValue("\(Int(round(displayAmount * 100))) percent")
            .animation(.snappy(duration: 0.2), value: settings.isEnabled)
        }
        .fixedSize()
    }
}
