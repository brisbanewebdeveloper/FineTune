// FineTune/Views/Rows/AppRow.swift
import SwiftUI

/// A row displaying an app with volume controls and VU meter
/// Used in the Apps section
struct AppRow: View {
    let app: AudioApp
    let volume: Float  // Linear gain 0-1 (boost applied separately)
    let audioLevel: Float
    let realtimeBandLevels: RealtimeBandLevels
    let performanceDiagnostics: AudioPerformanceDiagnostics
    let showsPerformanceDiagnostics: Bool
    let showsRealtimeBandLevels: Bool
    let devices: [AudioDevice]
    let selectedDeviceUID: String  // For single mode
    let selectedDeviceUIDs: Set<String>  // For multi mode
    let isFollowingDefault: Bool
    let defaultDeviceUID: String?
    let deviceSelectionMode: DeviceSelectionMode
    let isMutedExternal: Bool  // Mute state from AudioEngine
    let boost: BoostLevel
    let onBoostChange: (BoostLevel) -> Void
    let onVolumeChange: (Float) -> Void
    let onMuteChange: (Bool) -> Void
    let onDeviceSelected: (String) -> Void  // Single mode
    let onDevicesSelected: (Set<String>) -> Void  // Multi mode
    let onDeviceModeChange: (DeviceSelectionMode) -> Void
    let onSelectFollowDefault: () -> Void
    let normalizationSettings: NormalizationSettings
    let compressorSettings: CompressorSettings
    let onNormalizationChange: (NormalizationSettings) -> Void
    let onCompressionChange: (CompressorSettings) -> Void
    let syncLagMilliseconds: Float
    let effectiveSyncLagMilliseconds: Float
    let onSyncLagChange: (Float) -> Void
    let onAppActivate: () -> Void
    let eqSettings: EQSettings
    let userPresets: [UserEQPreset]
    let onEQChange: (EQSettings) -> Void
    let bandMeterAggregationMode: BandMeterAggregationMode
    let onUserPresetSelected: (UserEQPreset) -> Void
    let onSavePreset: (String, EQSettings) -> Void
    let onDeleteUserPreset: (UUID) -> Void
    let onRenameUserPreset: (UUID, String) -> Void
    let isEQExpanded: Bool
    let onEQToggle: () -> Void

    @State private var isIconHovered = false
    @State private var localEQSettings: EQSettings

    init(
        app: AudioApp,
        volume: Float,
        audioLevel: Float = 0,
        realtimeBandLevels: RealtimeBandLevels = .zero,
        performanceDiagnostics: AudioPerformanceDiagnostics = .zero,
        showsPerformanceDiagnostics: Bool = true,
        showsRealtimeBandLevels: Bool = true,
        devices: [AudioDevice],
        selectedDeviceUID: String,
        selectedDeviceUIDs: Set<String> = [],
        isFollowingDefault: Bool = true,
        defaultDeviceUID: String? = nil,
        deviceSelectionMode: DeviceSelectionMode = .single,
        isMuted: Bool = false,
        boost: BoostLevel = .x1,
        onBoostChange: @escaping (BoostLevel) -> Void = { _ in },
        onVolumeChange: @escaping (Float) -> Void,
        onMuteChange: @escaping (Bool) -> Void,
        onDeviceSelected: @escaping (String) -> Void,
        onDevicesSelected: @escaping (Set<String>) -> Void = { _ in },
        onDeviceModeChange: @escaping (DeviceSelectionMode) -> Void = { _ in },
        onSelectFollowDefault: @escaping () -> Void = {},
        normalizationSettings: NormalizationSettings = .bypassed,
        compressorSettings: CompressorSettings = .bypassed,
        onNormalizationChange: @escaping (NormalizationSettings) -> Void = { _ in },
        onCompressionChange: @escaping (CompressorSettings) -> Void = { _ in },
        syncLagMilliseconds: Float = 0,
        effectiveSyncLagMilliseconds: Float = 0,
        onSyncLagChange: @escaping (Float) -> Void = { _ in },
        onAppActivate: @escaping () -> Void = {},
        eqSettings: EQSettings = EQSettings(),
        userPresets: [UserEQPreset] = [],
        onEQChange: @escaping (EQSettings) -> Void = { _ in },
        bandMeterAggregationMode: BandMeterAggregationMode = .average,
        onUserPresetSelected: @escaping (UserEQPreset) -> Void = { _ in },
        onSavePreset: @escaping (String, EQSettings) -> Void = { _, _ in },
        onDeleteUserPreset: @escaping (UUID) -> Void = { _ in },
        onRenameUserPreset: @escaping (UUID, String) -> Void = { _, _ in },
        isEQExpanded: Bool = false,
        onEQToggle: @escaping () -> Void = {}
    ) {
        self.app = app
        self.volume = volume
        self.audioLevel = audioLevel
        self.realtimeBandLevels = realtimeBandLevels
        self.performanceDiagnostics = performanceDiagnostics
        self.showsPerformanceDiagnostics = showsPerformanceDiagnostics
        self.showsRealtimeBandLevels = showsRealtimeBandLevels
        self.devices = devices
        self.selectedDeviceUID = selectedDeviceUID
        self.selectedDeviceUIDs = selectedDeviceUIDs
        self.isFollowingDefault = isFollowingDefault
        self.defaultDeviceUID = defaultDeviceUID
        self.deviceSelectionMode = deviceSelectionMode
        self.isMutedExternal = isMuted
        self.boost = boost
        self.onBoostChange = onBoostChange
        self.onVolumeChange = onVolumeChange
        self.onMuteChange = onMuteChange
        self.onDeviceSelected = onDeviceSelected
        self.onDevicesSelected = onDevicesSelected
        self.onDeviceModeChange = onDeviceModeChange
        self.onSelectFollowDefault = onSelectFollowDefault
        self.normalizationSettings = normalizationSettings
        self.compressorSettings = compressorSettings
        self.onNormalizationChange = onNormalizationChange
        self.onCompressionChange = onCompressionChange
        self.syncLagMilliseconds = syncLagMilliseconds
        self.effectiveSyncLagMilliseconds = effectiveSyncLagMilliseconds
        self.onSyncLagChange = onSyncLagChange
        self.onAppActivate = onAppActivate
        self.eqSettings = eqSettings
        self.userPresets = userPresets
        self.onEQChange = onEQChange
        self.bandMeterAggregationMode = bandMeterAggregationMode
        self.onUserPresetSelected = onUserPresetSelected
        self.onSavePreset = onSavePreset
        self.onDeleteUserPreset = onDeleteUserPreset
        self.onRenameUserPreset = onRenameUserPreset
        self.isEQExpanded = isEQExpanded
        self.onEQToggle = onEQToggle
        // Initialize local EQ state for reactive UI updates
        self._localEQSettings = State(initialValue: eqSettings)
    }

    var body: some View {
        ExpandableGlassRow(isExpanded: isEQExpanded) {
            // Header: Main row content (always visible)
            HStack(spacing: DesignTokens.Spacing.sm) {
                // VU Meter
                VUMeter(level: audioLevel, isMuted: isMutedExternal || volume == 0)

                // App icon - clickable to activate app
                Button(action: onAppActivate) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: DesignTokens.Dimensions.rowContentHeight - 4, height: DesignTokens.Dimensions.rowContentHeight - 4)
                        .opacity(isIconHovered ? 0.7 : 1.0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(app.name)")
                .onHover { hovering in
                    isIconHovered = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

                // App name - expands to fill available space
                Text(app.name)
                    .font(DesignTokens.Typography.rowName)
                    .lineLimit(1)
                    .help(app.name)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Shared controls section
                AppRowControls(
                    volume: volume,
                    isMuted: isMutedExternal,
                    devices: devices,
                    selectedDeviceUID: selectedDeviceUID,
                    selectedDeviceUIDs: selectedDeviceUIDs,
                    isFollowingDefault: isFollowingDefault,
                    defaultDeviceUID: defaultDeviceUID,
                    deviceSelectionMode: deviceSelectionMode,
                    boost: boost,
                    normalizationSettings: normalizationSettings,
                    compressorSettings: compressorSettings,
                    syncLagMilliseconds: syncLagMilliseconds,
                    isEQExpanded: isEQExpanded,
                    onVolumeChange: onVolumeChange,
                    onMuteChange: onMuteChange,
                    onBoostChange: onBoostChange,
                    onNormalizationChange: onNormalizationChange,
                    onCompressionChange: onCompressionChange,
                    onSyncLagChange: onSyncLagChange,
                    onDeviceSelected: onDeviceSelected,
                    onDevicesSelected: onDevicesSelected,
                    onDeviceModeChange: onDeviceModeChange,
                    onSelectFollowDefault: onSelectFollowDefault,
                    onEQToggle: onEQToggle
                )
            }
            .frame(minHeight: DesignTokens.Dimensions.rowContentHeight + 18)
        } expandedContent: {
            // EQ panel - shown when expanded
            // SwiftUI calculates natural height via conditional rendering
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                EQPanelView(
                    settings: $localEQSettings,
                    compressorSettings: compressorSettings,
                    realtimeBandLevels: realtimeBandLevels,
                    showsRealtimeBandLevels: showsRealtimeBandLevels,
                    bandMeterAggregationMode: bandMeterAggregationMode,
                    userPresets: userPresets,
                    onPresetSelected: { preset in
                        localEQSettings = preset.settings
                        onEQChange(preset.settings)
                    },
                    onUserPresetSelected: { userPreset in
                        localEQSettings = userPreset.settings
                        onUserPresetSelected(userPreset)
                    },
                    onSettingsChanged: { settings in
                        onEQChange(settings)
                    },
                    onSavePreset: onSavePreset,
                    onDeleteUserPreset: onDeleteUserPreset,
                    onRenameUserPreset: onRenameUserPreset
                )

                if showsPerformanceDiagnostics {
                    AudioPerformanceDiagnosticsView(
                        diagnostics: performanceDiagnostics,
                        effectiveSyncLagMilliseconds: effectiveSyncLagMilliseconds
                    )
                }
            }
            .padding(.top, DesignTokens.Spacing.sm)
        }
        .onChange(of: eqSettings) { _, newValue in
            // Sync from parent when external EQ settings change
            localEQSettings = newValue
        }
    }
}

private struct AudioPerformanceDiagnosticsView: View {
    let diagnostics: AudioPerformanceDiagnostics
    let effectiveSyncLagMilliseconds: Float

    private var callbackSummary: String {
        guard diagnostics.hasCallbackData else {
            return "Callback timing: waiting for audio"
        }

        guard diagnostics.hasCallbackBudget else {
            return "Callback timing: \(Self.format(diagnostics.callbackAverageMilliseconds)) ms avg, \(Self.format(diagnostics.callbackPeakMilliseconds)) ms peak"
        }

        let overBudgetSuffix = diagnostics.callbackPeakExceedsBudget ? " (peak over budget)" : ""
        return "Callback timing: \(Self.format(diagnostics.callbackAverageMilliseconds)) ms avg, \(Self.format(diagnostics.callbackPeakMilliseconds)) ms peak vs \(Self.format(diagnostics.callbackBudgetMilliseconds)) ms budget\(overBudgetSuffix)"
    }

    private var callbackFormatSummary: String {
        guard diagnostics.hasCallbackFormat else {
            return "Callback format: waiting for audio"
        }

        return "Callback format: \(diagnostics.callbackFramesPerBuffer) frames @ \(Self.formatKilohertz(diagnostics.callbackSampleRateHz)) kHz"
    }

    private var appliedSyncLagSummary: String {
        "Applied sync lag: \(Self.format(Double(effectiveSyncLagMilliseconds))) ms"
    }

    private var routeSwitchSummary: String {
        guard diagnostics.hasRouteSwitchData else {
            return "Route switch timing: no switch recorded yet"
        }

        let route = diagnostics.routeSwitch
        let hasBreakdown = route.tapCreationMilliseconds > 0 || route.warmupMilliseconds > 0 || route.crossfadeMilliseconds > 0 || route.promotionMilliseconds > 0

        guard hasBreakdown else {
            return "Route switch timing: \(Self.format(route.totalMilliseconds)) ms total"
        }

        return "Route switch timing: \(Self.format(route.totalMilliseconds)) ms total (prep \(Self.format(route.tapCreationMilliseconds)), warmup \(Self.format(route.warmupMilliseconds)), fade \(Self.format(route.crossfadeMilliseconds)), promote \(Self.format(route.promotionMilliseconds)))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text("Diagnostics")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text(callbackSummary)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text(callbackFormatSummary)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text(appliedSyncLagSummary)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text(routeSwitchSummary)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func format(_ milliseconds: Double) -> String {
        String(format: "%.1f", milliseconds)
    }

    private static func formatKilohertz(_ sampleRateHz: Double) -> String {
        String(format: "%.1f", sampleRateHz / 1000.0)
    }
}

// MARK: - Previews

#Preview("App Row") {
    PreviewContainer {
        VStack(spacing: 4) {
            AppRow(
                app: MockData.sampleApps[0],
                volume: 1.0,
                audioLevel: 0.65,
                devices: MockData.sampleDevices,
                selectedDeviceUID: MockData.sampleDevices[0].uid,
                onVolumeChange: { _ in },
                onMuteChange: { _ in },
                onDeviceSelected: { _ in }
            )

            AppRow(
                app: MockData.sampleApps[1],
                volume: 0.5,
                audioLevel: 0.25,
                devices: MockData.sampleDevices,
                selectedDeviceUID: MockData.sampleDevices[1].uid,
                onVolumeChange: { _ in },
                onMuteChange: { _ in },
                onDeviceSelected: { _ in }
            )

            AppRow(
                app: MockData.sampleApps[2],
                volume: 1.5,
                audioLevel: 0.85,
                devices: MockData.sampleDevices,
                selectedDeviceUID: MockData.sampleDevices[2].uid,
                onVolumeChange: { _ in },
                onMuteChange: { _ in },
                onDeviceSelected: { _ in }
            )
        }
    }
}

#Preview("App Row - Multiple Apps") {
    PreviewContainer {
        VStack(spacing: 4) {
            ForEach(MockData.sampleApps) { app in
                AppRow(
                    app: app,
                    volume: Float.random(in: 0.5...1.5),
                    audioLevel: Float.random(in: 0...0.8),
                    devices: MockData.sampleDevices,
                    selectedDeviceUID: MockData.sampleDevices.randomElement()!.uid,
                    onVolumeChange: { _ in },
                    onMuteChange: { _ in },
                    onDeviceSelected: { _ in }
                )
            }
        }
    }
}
