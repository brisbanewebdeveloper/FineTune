import AudioToolbox
import Foundation

/// RT-safe fixed-delay processor for already-rendered output samples.
///
/// Storage is preallocated on the main thread and only pointer arithmetic occurs on the
/// HAL callback. Delay changes reset the internal history so timing changes are audible as
/// silence padding rather than stale buffered audio.
final class AudioSyncDelayProcessor {
    private struct BufferState {
        let storage: UnsafeMutablePointer<Float>
        let capacity: Int
        var delaySamples: Int
        var writeIndex: Int

        init(storage: UnsafeMutablePointer<Float>, capacity: Int, delaySamples: Int = 0, writeIndex: Int = 0) {
            self.storage = storage
            self.capacity = capacity
            self.delaySamples = delaySamples
            self.writeIndex = writeIndex
        }
    }

    private var sampleRate: Double
    private var channelCounts: [UInt32]
    private var bufferStates: [BufferState]

    init(sampleRate: Double, channelCounts: [UInt32], lagMilliseconds: Float = 0) {
        self.sampleRate = sampleRate
        self.channelCounts = channelCounts
        self.bufferStates = channelCounts.map { channelCount in
            let capacity = AudioSyncDelayProcessor.capacitySamples(sampleRate: sampleRate, channelCount: Int(channelCount))
            let storage = UnsafeMutablePointer<Float>.allocate(capacity: max(capacity, 1))
            storage.initialize(repeating: 0, count: max(capacity, 1))
            return BufferState(storage: storage, capacity: max(capacity, 1))
        }
        update(lagMilliseconds: lagMilliseconds)
    }

    deinit {
        for state in bufferStates {
            state.storage.deinitialize(count: state.capacity)
            state.storage.deallocate()
        }
    }

    func update(sampleRate: Double? = nil, channelCounts: [UInt32]? = nil, lagMilliseconds: Float) {
        let resolvedSampleRate = sampleRate ?? self.sampleRate
        let resolvedChannelCounts = channelCounts ?? self.channelCounts

        if self.sampleRate != resolvedSampleRate || self.channelCounts != resolvedChannelCounts {
            reconfigure(sampleRate: resolvedSampleRate, channelCounts: resolvedChannelCounts)
        }

        let normalized = AudioSyncLagRange.clamp(lagMilliseconds)
        for index in bufferStates.indices {
            let channelCount = Int(channelCounts?[index] ?? self.channelCounts[index])
            bufferStates[index].delaySamples = delaySampleCount(for: normalized, channelCount: channelCount, sampleRate: self.sampleRate)
            bufferStates[index].writeIndex = 0
            memset(bufferStates[index].storage, 0, bufferStates[index].capacity * MemoryLayout<Float>.size)
        }
    }

    func process(_ outputBuffers: UnsafeMutableAudioBufferListPointer) {
        let bufferCount = min(outputBuffers.count, bufferStates.count)
        guard bufferCount > 0 else { return }

        for index in 0..<bufferCount {
            let outputBuffer = outputBuffers[index]
            guard let outputData = outputBuffer.mData else { continue }

            let sampleCount = Int(outputBuffer.mDataByteSize) / MemoryLayout<Float>.size
            guard sampleCount > 0 else { continue }

            var state = bufferStates[index]
            let delaySamples = state.delaySamples
            guard delaySamples > 0 else { continue }

            let samples = outputData.assumingMemoryBound(to: Float.self)
            let capacity = state.capacity
            var writeIndex = state.writeIndex

            for sampleIndex in 0..<sampleCount {
                let delayedReadIndex = writeIndex >= delaySamples
                    ? writeIndex - delaySamples
                    : capacity - (delaySamples - writeIndex)
                let delayedSample = state.storage[delayedReadIndex]
                state.storage[writeIndex] = samples[sampleIndex]
                samples[sampleIndex] = delayedSample

                writeIndex += 1
                if writeIndex == capacity {
                    writeIndex = 0
                }
            }

            state.writeIndex = writeIndex
            bufferStates[index] = state
        }
    }

    private func reconfigure(sampleRate: Double, channelCounts: [UInt32]) {
        for state in bufferStates {
            state.storage.deinitialize(count: state.capacity)
            state.storage.deallocate()
        }

        self.sampleRate = sampleRate
        self.channelCounts = channelCounts
        self.bufferStates = channelCounts.map { channelCount in
            let capacity = AudioSyncDelayProcessor.capacitySamples(sampleRate: sampleRate, channelCount: Int(channelCount))
            let storage = UnsafeMutablePointer<Float>.allocate(capacity: max(capacity, 1))
            storage.initialize(repeating: 0, count: max(capacity, 1))
            return BufferState(storage: storage, capacity: max(capacity, 1))
        }
    }

    private func delaySampleCount(for lagMilliseconds: Float, channelCount: Int, sampleRate: Double) -> Int {
        let delayFrames = Int(round(Double(lagMilliseconds) * sampleRate / 1000.0))
        return min(delayFrames * max(channelCount, 1), AudioSyncDelayProcessor.capacitySamples(sampleRate: sampleRate, channelCount: channelCount))
    }

    private static func capacitySamples(sampleRate: Double, channelCount: Int) -> Int {
        let maxDelayFrames = Int(ceil(Double(AudioSyncLagRange.maxMilliseconds) * sampleRate / 1000.0))
        return max(maxDelayFrames * max(channelCount, 1), 1)
    }
}
