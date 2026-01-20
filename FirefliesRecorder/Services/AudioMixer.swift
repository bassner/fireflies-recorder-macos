//
//  AudioMixer.swift
//  FirefliesRecorder
//
//  Records microphone and system audio to separate stereo channels (L=mic, R=system)
//  Post-processing normalizes and merges to mono
//
//  Memory-efficient design: uses fixed-size ring buffers with bounded capacity
//  to prevent unbounded memory growth during long recordings.
//

import Foundation
import AVFoundation

final class AudioMixer {
    private let outputURL: URL
    private var audioFile: AVAudioFile?
    private var isWriting = false

    private let writeQueue = DispatchQueue(label: "dev.bassner.ffrecorder.mixer", qos: .userInteractive)

    // Standard format: 48kHz stereo (L=mic, R=system)
    private let sampleRate: Double = 48000
    private let channels: AVAudioChannelCount = 2

    private lazy var outputFormat: AVAudioFormat = {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
    }()

    // Mono format for input conversion
    private lazy var monoFormat: AVAudioFormat = {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }()

    // Converters for each source (created on first buffer)
    private var micConverter: AVAudioConverter?
    private var systemConverter: AVAudioConverter?

    // MARK: - Ring Buffer Implementation
    // Fixed-capacity ring buffers to prevent unbounded memory growth
    // Max ~0.5 seconds of buffered audio per source (24000 samples at 48kHz)
    private let maxBufferCapacity: AVAudioFrameCount = 24000
    private let chunkSize: AVAudioFrameCount = 4800  // 0.1s chunks for writing

    // Ring buffer storage - pre-allocated to avoid repeated allocations
    private var micRingBuffer: [Float]
    private var systemRingBuffer: [Float]
    private var micWriteIndex: Int = 0
    private var micReadIndex: Int = 0
    private var micAvailableFrames: Int = 0
    private var systemWriteIndex: Int = 0
    private var systemReadIndex: Int = 0
    private var systemAvailableFrames: Int = 0
    private let bufferLock = NSLock()

    // Track which sources are active
    var hasMicSource = false
    var hasSystemSource = false

    init(outputURL: URL) {
        self.outputURL = outputURL
        // Pre-allocate ring buffers
        self.micRingBuffer = [Float](repeating: 0, count: Int(maxBufferCapacity))
        self.systemRingBuffer = [Float](repeating: 0, count: Int(maxBufferCapacity))
    }

    func startWriting() throws {
        try? FileManager.default.removeItem(at: outputURL)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 128000
        ]

        audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // Reset ring buffers
        micWriteIndex = 0
        micReadIndex = 0
        micAvailableFrames = 0
        systemWriteIndex = 0
        systemReadIndex = 0
        systemAvailableFrames = 0

        isWriting = true
        print("AudioMixer: Started writing stereo file (L=mic, R=system)")
    }

    func stopWriting() async throws -> URL {
        writeQueue.sync {
            isWriting = false
            flushPendingBuffers()
            audioFile = nil
            micConverter = nil
            systemConverter = nil
        }
        print("AudioMixer: Stopped writing")
        return outputURL
    }

    func appendMicBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard isWriting, buffer.frameLength > 0 else { return }

        writeQueue.async { [weak self] in
            guard let self = self else { return }

            // Convert to mono 48kHz
            guard let monoBuffer = self.convertToMono(buffer, isSystem: false) else { return }

            self.bufferLock.lock()
            self.appendToMicRingBuffer(monoBuffer)
            self.tryWriteChunks()
            self.bufferLock.unlock()
        }
    }

    func appendSystemBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard isWriting, buffer.frameLength > 0 else { return }

        writeQueue.async { [weak self] in
            guard let self = self else { return }

            // Convert to mono 48kHz
            guard let monoBuffer = self.convertToMono(buffer, isSystem: true) else { return }

            self.bufferLock.lock()
            self.appendToSystemRingBuffer(monoBuffer)
            self.tryWriteChunks()
            self.bufferLock.unlock()
        }
    }

    // MARK: - Ring Buffer Operations

    /// Append samples to mic ring buffer, overwriting oldest if full
    private func appendToMicRingBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        let capacity = Int(maxBufferCapacity)

        for i in 0..<frameCount {
            micRingBuffer[micWriteIndex] = data[i]
            micWriteIndex = (micWriteIndex + 1) % capacity

            if micAvailableFrames < capacity {
                micAvailableFrames += 1
            } else {
                // Buffer full - advance read index (drop oldest)
                micReadIndex = (micReadIndex + 1) % capacity
            }
        }
    }

    /// Append samples to system ring buffer, overwriting oldest if full
    private func appendToSystemRingBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        let capacity = Int(maxBufferCapacity)

        for i in 0..<frameCount {
            systemRingBuffer[systemWriteIndex] = data[i]
            systemWriteIndex = (systemWriteIndex + 1) % capacity

            if systemAvailableFrames < capacity {
                systemAvailableFrames += 1
            } else {
                // Buffer full - advance read index (drop oldest)
                systemReadIndex = (systemReadIndex + 1) % capacity
            }
        }
    }

    /// Read samples from mic ring buffer
    private func readFromMicRingBuffer(count: Int) -> [Float] {
        let capacity = Int(maxBufferCapacity)
        let actualCount = min(count, micAvailableFrames)
        var result = [Float](repeating: 0, count: count)

        for i in 0..<actualCount {
            result[i] = micRingBuffer[(micReadIndex + i) % capacity]
        }

        // Advance read index
        micReadIndex = (micReadIndex + actualCount) % capacity
        micAvailableFrames -= actualCount

        return result
    }

    /// Read samples from system ring buffer
    private func readFromSystemRingBuffer(count: Int) -> [Float] {
        let capacity = Int(maxBufferCapacity)
        let actualCount = min(count, systemAvailableFrames)
        var result = [Float](repeating: 0, count: count)

        for i in 0..<actualCount {
            result[i] = systemRingBuffer[(systemReadIndex + i) % capacity]
        }

        // Advance read index
        systemReadIndex = (systemReadIndex + actualCount) % capacity
        systemAvailableFrames -= actualCount

        return result
    }

    /// Write chunks when we have enough data
    /// Key design: write aggressively to prevent buffer accumulation
    /// If one source is behind, pad with silence rather than waiting
    private func tryWriteChunks() {
        let chunk = Int(chunkSize)

        // Determine how many frames we can write
        // Key change: write when EITHER source has a full chunk (not both)
        // This prevents one fast source from causing unbounded accumulation
        let framesToWrite: Int
        if hasMicSource && hasSystemSource {
            // Both sources active - write when either has enough, up to chunk size
            let maxAvailable = max(micAvailableFrames, systemAvailableFrames)
            framesToWrite = min(maxAvailable, chunk)
        } else if hasMicSource {
            framesToWrite = min(micAvailableFrames, chunk)
        } else if hasSystemSource {
            framesToWrite = min(systemAvailableFrames, chunk)
        } else {
            return
        }

        // Write in chunks - but allow partial writes to prevent accumulation
        guard framesToWrite >= chunk else { return }

        // Create stereo buffer
        guard let stereoBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(framesToWrite)) else { return }
        stereoBuffer.frameLength = AVAudioFrameCount(framesToWrite)

        guard let stereoData = stereoBuffer.floatChannelData else { return }

        // Fill left channel (mic) - pad with silence if not enough data
        let micData = hasMicSource ? readFromMicRingBuffer(count: framesToWrite) : [Float](repeating: 0, count: framesToWrite)
        for i in 0..<framesToWrite {
            stereoData[0][i] = micData[i]
        }

        // Fill right channel (system) - pad with silence if not enough data
        let systemData = hasSystemSource ? readFromSystemRingBuffer(count: framesToWrite) : [Float](repeating: 0, count: framesToWrite)
        for i in 0..<framesToWrite {
            stereoData[1][i] = systemData[i]
        }

        // Write to file
        writeToFile(stereoBuffer)
    }

    /// Flush any remaining audio when stopping
    private func flushPendingBuffers() {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        // Write whatever we have left
        let framesToWrite = max(micAvailableFrames, systemAvailableFrames)

        guard framesToWrite > 0 else { return }

        guard let stereoBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(framesToWrite)) else { return }
        stereoBuffer.frameLength = AVAudioFrameCount(framesToWrite)

        guard let stereoData = stereoBuffer.floatChannelData else { return }

        // Fill left channel (mic)
        let micData = readFromMicRingBuffer(count: framesToWrite)
        for i in 0..<framesToWrite {
            stereoData[0][i] = micData[i]
        }

        // Fill right channel (system)
        let systemData = readFromSystemRingBuffer(count: framesToWrite)
        for i in 0..<framesToWrite {
            stereoData[1][i] = systemData[i]
        }

        writeToFile(stereoBuffer)
    }

    // MARK: - Conversion

    /// Convert input buffer to mono 48kHz
    private func convertToMono(_ buffer: AVAudioPCMBuffer, isSystem: Bool) -> AVAudioPCMBuffer? {
        let inputFormat = buffer.format

        // If already mono 48kHz, return as-is
        if inputFormat.sampleRate == sampleRate && inputFormat.channelCount == 1 {
            return buffer
        }

        // If stereo, mix down to mono first
        let monoInput: AVAudioPCMBuffer
        if inputFormat.channelCount > 1 {
            guard let mixed = mixdownToMono(buffer) else { return nil }
            monoInput = mixed
        } else {
            monoInput = buffer
        }

        // If sample rate matches, we're done
        if monoInput.format.sampleRate == sampleRate {
            return monoInput
        }

        // Need sample rate conversion
        let converter: AVAudioConverter
        if isSystem {
            if systemConverter == nil || systemConverter?.inputFormat != monoInput.format {
                guard let newConverter = AVAudioConverter(from: monoInput.format, to: monoFormat) else {
                    print("Failed to create system converter")
                    return nil
                }
                systemConverter = newConverter
            }
            converter = systemConverter!
        } else {
            if micConverter == nil || micConverter?.inputFormat != monoInput.format {
                guard let newConverter = AVAudioConverter(from: monoInput.format, to: monoFormat) else {
                    print("Failed to create mic converter")
                    return nil
                }
                micConverter = newConverter
            }
            converter = micConverter!
        }

        let ratio = sampleRate / monoInput.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(ceil(Double(monoInput.frameLength) * ratio))

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: outputFrameCapacity) else {
            return nil
        }

        var error: NSError?
        var inputConsumed = false

        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return monoInput
        }

        if status == .error {
            print("Conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }

        return outputBuffer.frameLength > 0 ? outputBuffer : nil
    }

    /// Mix stereo buffer down to mono
    private func mixdownToMono(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let inputFormat = buffer.format
        guard inputFormat.channelCount >= 2 else { return buffer }

        let monoFormatAtInputRate = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: 1)!

        guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormatAtInputRate, frameCapacity: buffer.frameLength) else {
            return nil
        }
        monoBuffer.frameLength = buffer.frameLength

        guard let inputData = buffer.floatChannelData,
              let outputData = monoBuffer.floatChannelData?[0] else {
            return nil
        }

        let channelCount = Int(inputFormat.channelCount)
        for frame in 0..<Int(buffer.frameLength) {
            var sum: Float = 0
            for ch in 0..<channelCount {
                sum += inputData[ch][frame]
            }
            outputData[frame] = sum / Float(channelCount)
        }

        return monoBuffer
    }

    // MARK: - File Writing

    private func writeToFile(_ buffer: AVAudioPCMBuffer) {
        guard let audioFile = audioFile else { return }

        do {
            try audioFile.write(from: buffer)
        } catch {
            print("AudioMixer write error: \(error)")
        }
    }
}
