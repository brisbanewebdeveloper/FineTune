// FineTune/Views/Rows/AppRowWithLevelPolling.swift
import SwiftUI

/// App row that polls audio levels at regular intervals
struct AppRowWithLevelPolling: View {
    let app: AudioApp
    let volume: Float
    let isMuted: Bool
    let devices: [AudioDevice]
    let selectedDeviceUID: String
    let selectedDeviceUIDs: Set<String>
    let isFollowingDefault: Bool
    let defaultDeviceUID: String?
    let deviceSelectionMode: DeviceSelectionMode
    let boost: BoostLevel
    let onBoostChange: (BoostLevel) -> Void
    let getAudioLevel: () -> Float
    let getCompressorBandLevels: () -> [Float]
    let setBandMeteringEnabled: (Bool) -> Void
    let isPopupVisible: Bool
    let onVolumeChange: (Float) -> Void
    let onMuteChange: (Bool) -> Void
    let onDeviceSelected: (String) -> Void
    let onDevicesSelected: (Set<String>) -> Void
    let onDeviceModeChange: (DeviceSelectionMode) -> Void
    let onSelectFollowDefault: () -> Void
    let compressorSettings: CompressorSettings
    let onCompressionChange: (CompressorSettings) -> Void
    let onAppActivate: () -> Void
    let eqSettings: EQSettings
    let onEQChange: (EQSettings) -> Void
    let isEQExpanded: Bool
    let onEQToggle: () -> Void

    @State private var displayLevel: Float = 0
    @State private var displayBandLevels = Array(repeating: Float.zero, count: EQSettings.bandCount)
    @State private var levelTimer: Timer?

    init(
        app: AudioApp,
        volume: Float,
        isMuted: Bool,
        devices: [AudioDevice],
        selectedDeviceUID: String,
        selectedDeviceUIDs: Set<String> = [],
        isFollowingDefault: Bool = true,
        defaultDeviceUID: String? = nil,
        deviceSelectionMode: DeviceSelectionMode = .single,
        boost: BoostLevel = .x1,
        onBoostChange: @escaping (BoostLevel) -> Void = { _ in },
        getAudioLevel: @escaping () -> Float,
        getCompressorBandLevels: @escaping () -> [Float] = { Array(repeating: Float.zero, count: EQSettings.bandCount) },
        setBandMeteringEnabled: @escaping (Bool) -> Void = { _ in },
        isPopupVisible: Bool = true,
        onVolumeChange: @escaping (Float) -> Void,
        onMuteChange: @escaping (Bool) -> Void,
        onDeviceSelected: @escaping (String) -> Void,
        onDevicesSelected: @escaping (Set<String>) -> Void = { _ in },
        onDeviceModeChange: @escaping (DeviceSelectionMode) -> Void = { _ in },
        onSelectFollowDefault: @escaping () -> Void = {},
        compressorSettings: CompressorSettings = .bypassed,
        onCompressionChange: @escaping (CompressorSettings) -> Void = { _ in },
        onAppActivate: @escaping () -> Void = {},
        eqSettings: EQSettings = EQSettings(),
        onEQChange: @escaping (EQSettings) -> Void = { _ in },
        isEQExpanded: Bool = false,
        onEQToggle: @escaping () -> Void = {}
    ) {
        self.app = app
        self.volume = volume
        self.isMuted = isMuted
        self.devices = devices
        self.selectedDeviceUID = selectedDeviceUID
        self.selectedDeviceUIDs = selectedDeviceUIDs
        self.isFollowingDefault = isFollowingDefault
        self.defaultDeviceUID = defaultDeviceUID
        self.deviceSelectionMode = deviceSelectionMode
        self.boost = boost
        self.onBoostChange = onBoostChange
        self.getAudioLevel = getAudioLevel
        self.getCompressorBandLevels = getCompressorBandLevels
        self.setBandMeteringEnabled = setBandMeteringEnabled
        self.isPopupVisible = isPopupVisible
        self.onVolumeChange = onVolumeChange
        self.onMuteChange = onMuteChange
        self.onDeviceSelected = onDeviceSelected
        self.onDevicesSelected = onDevicesSelected
        self.onDeviceModeChange = onDeviceModeChange
        self.onSelectFollowDefault = onSelectFollowDefault
        self.compressorSettings = compressorSettings
        self.onCompressionChange = onCompressionChange
        self.onAppActivate = onAppActivate
        self.eqSettings = eqSettings
        self.onEQChange = onEQChange
        self.isEQExpanded = isEQExpanded
        self.onEQToggle = onEQToggle
    }

    var body: some View {
        AppRow(
            app: app,
            volume: volume,
            audioLevel: displayLevel,
            realtimeBandLevels: displayBandLevels,
            showsRealtimeBandLevels: true,
            devices: devices,
            selectedDeviceUID: selectedDeviceUID,
            selectedDeviceUIDs: selectedDeviceUIDs,
            isFollowingDefault: isFollowingDefault,
            defaultDeviceUID: defaultDeviceUID,
            deviceSelectionMode: deviceSelectionMode,
            isMuted: isMuted,
            boost: boost,
            onBoostChange: onBoostChange,
            onVolumeChange: onVolumeChange,
            onMuteChange: onMuteChange,
            onDeviceSelected: onDeviceSelected,
            onDevicesSelected: onDevicesSelected,
            onDeviceModeChange: onDeviceModeChange,
            onSelectFollowDefault: onSelectFollowDefault,
            compressorSettings: compressorSettings,
            onCompressionChange: onCompressionChange,
            onAppActivate: onAppActivate,
            eqSettings: eqSettings,
            onEQChange: onEQChange,
            isEQExpanded: isEQExpanded,
            onEQToggle: onEQToggle
        )
        .onAppear {
            if isPopupVisible {
                startLevelPolling()
            }
            syncBandMeteringState()
        }
        .onDisappear {
            stopLevelPolling()
            setBandMeteringEnabled(false)
            displayBandLevels = Array(repeating: Float.zero, count: EQSettings.bandCount)
        }
        .onChange(of: isPopupVisible) { _, visible in
            if visible {
                startLevelPolling()
                refreshLevels()
            } else {
                stopLevelPolling()
                displayLevel = 0  // Reset meter when hidden
            }
            syncBandMeteringState()
        }
        .onChange(of: isEQExpanded) { _, _ in
            syncBandMeteringState()
        }
    }

    private func startLevelPolling() {
        // Guard against duplicate timers
        guard levelTimer == nil else { return }

        refreshLevels()

        levelTimer = Timer.scheduledTimer(
            withTimeInterval: DesignTokens.Timing.vuMeterUpdateInterval,
            repeats: true
        ) { _ in
            refreshLevels()
        }
    }

    private func stopLevelPolling() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func refreshLevels() {
        displayLevel = getAudioLevel()
        displayBandLevels = isBandMeteringActive
            ? normalizedBandLevels(getCompressorBandLevels())
            : Array(repeating: Float.zero, count: EQSettings.bandCount)
    }

    private func syncBandMeteringState() {
        setBandMeteringEnabled(isBandMeteringActive)
        if isBandMeteringActive {
            refreshLevels()
        } else {
            displayBandLevels = Array(repeating: Float.zero, count: EQSettings.bandCount)
        }
    }

    private var isBandMeteringActive: Bool {
        isPopupVisible && isEQExpanded
    }

    private func normalizedBandLevels(_ levels: [Float]) -> [Float] {
        let padded = Array(levels.prefix(EQSettings.bandCount))
        let normalized = padded + Array(repeating: Float.zero, count: max(0, EQSettings.bandCount - padded.count))
        return normalized.map { level in
            guard level.isFinite else { return 0.0 }
            return min(max(level, 0.0), 1.0)
        }
    }
}
