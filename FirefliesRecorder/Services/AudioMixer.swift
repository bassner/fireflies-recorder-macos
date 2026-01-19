//
//  AudioMixer.swift
//  FirefliesRecorder
//
//  Records microphone and system audio to separate stereo channels (L=mic, R=system)
//  Post-processing normalizes and merges to mono
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

    // Pending mono buffers for each source
    private var pendingMicBuffer: AVAudioPCMBuffer?
    private var pendingSystemBuffer: AVAudioPCMBuffer?
    private let bufferLock = NSLock()

    // Track which sources are active
    var hasMicSource = false
    var hasSystemSource = false

    init(outputURL: URL) {
        self.outputURL = outputURL
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
            self.pendingMicBuffer = self.appendToBuffer(self.pendingMicBuffer, monoBuffer)
            self.tryWriteStereoBuffer()
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
            self.pendingSystemBuffer = self.appendToBuffer(self.pendingSystemBuffer, monoBuffer)
            self.tryWriteStereoBuffer()
            self.bufferLock.unlock()
        }
    }

    // MARK: - Buffer Management

    /// Append new buffer to existing pending buffer
    private func appendToBuffer(_ existing: AVAudioPCMBuffer?, _ new: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard let existing = existing else { return new }

        let totalFrames = existing.frameLength + new.frameLength
        guard let combined = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: totalFrames) else {
            return new
        }

        combined.frameLength = totalFrames

        if let existingData = existing.floatChannelData?[0],
           let newData = new.floatChannelData?[0],
           let combinedData = combined.floatChannelData?[0] {
            memcpy(combinedData, existingData, Int(existing.frameLength) * MemoryLayout<Float>.size)
            memcpy(combinedData.advanced(by: Int(existing.frameLength)), newData, Int(new.frameLength) * MemoryLayout<Float>.size)
        }

        return combined
    }

    /// Write stereo buffer with mic on left, system on right
    private func tryWriteStereoBuffer() {
        // Determine how many frames we can write
        let micFrames = pendingMicBuffer?.frameLength ?? 0
        let systemFrames = pendingSystemBuffer?.frameLength ?? 0

        // If only one source is active, write what we have with silence on the other channel
        let framesToWrite: AVAudioFrameCount
        if hasMicSource && hasSystemSource {
            // Both sources - write minimum common length
            framesToWrite = min(micFrames, systemFrames)
        } else if hasMicSource {
            // Only mic - write mic with silence on right
            framesToWrite = micFrames
        } else if hasSystemSource {
            // Only system - write system with silence on left
            framesToWrite = systemFrames
        } else {
            return
        }

        guard framesToWrite > 0 else { return }

        // Create stereo buffer
        guard let stereoBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: framesToWrite) else { return }
        stereoBuffer.frameLength = framesToWrite

        guard let stereoData = stereoBuffer.floatChannelData else { return }
        let leftChannel = stereoData[0]  // Mic
        let rightChannel = stereoData[1] // System

        // Fill left channel (mic)
        if let micBuffer = pendingMicBuffer, let micData = micBuffer.floatChannelData?[0] {
            let framesToCopy = min(framesToWrite, micBuffer.frameLength)
            memcpy(leftChannel, micData, Int(framesToCopy) * MemoryLayout<Float>.size)
            // Fill remainder with silence if needed
            if framesToCopy < framesToWrite {
                memset(leftChannel.advanced(by: Int(framesToCopy)), 0, Int(framesToWrite - framesToCopy) * MemoryLayout<Float>.size)
            }
        } else {
            // No mic data - fill with silence
            memset(leftChannel, 0, Int(framesToWrite) * MemoryLayout<Float>.size)
        }

        // Fill right channel (system)
        if let systemBuffer = pendingSystemBuffer, let systemData = systemBuffer.floatChannelData?[0] {
            let framesToCopy = min(framesToWrite, systemBuffer.frameLength)
            memcpy(rightChannel, systemData, Int(framesToCopy) * MemoryLayout<Float>.size)
            // Fill remainder with silence if needed
            if framesToCopy < framesToWrite {
                memset(rightChannel.advanced(by: Int(framesToCopy)), 0, Int(framesToWrite - framesToCopy) * MemoryLayout<Float>.size)
            }
        } else {
            // No system data - fill with silence
            memset(rightChannel, 0, Int(framesToWrite) * MemoryLayout<Float>.size)
        }

        // Write to file
        writeToFile(stereoBuffer)

        // Trim pending buffers
        pendingMicBuffer = trimBuffer(pendingMicBuffer, removeFrames: framesToWrite)
        pendingSystemBuffer = trimBuffer(pendingSystemBuffer, removeFrames: framesToWrite)
    }

    /// Remove processed frames from the front of a buffer
    private func trimBuffer(_ buffer: AVAudioPCMBuffer?, removeFrames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let buffer = buffer else { return nil }
        let remaining = buffer.frameLength - removeFrames
        guard remaining > 0 else { return nil }

        guard let trimmed = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: remaining) else { return nil }
        trimmed.frameLength = remaining

        if let srcData = buffer.floatChannelData?[0], let dstData = trimmed.floatChannelData?[0] {
            memcpy(dstData, srcData.advanced(by: Int(removeFrames)), Int(remaining) * MemoryLayout<Float>.size)
        }

        return trimmed
    }

    /// Flush any remaining audio when stopping
    private func flushPendingBuffers() {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        // Write whatever we have left
        let micFrames = pendingMicBuffer?.frameLength ?? 0
        let systemFrames = pendingSystemBuffer?.frameLength ?? 0
        let framesToWrite = max(micFrames, systemFrames)

        guard framesToWrite > 0 else { return }

        guard let stereoBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: framesToWrite) else { return }
        stereoBuffer.frameLength = framesToWrite

        guard let stereoData = stereoBuffer.floatChannelData else { return }

        // Fill left channel (mic)
        if let micBuffer = pendingMicBuffer, let micData = micBuffer.floatChannelData?[0] {
            memcpy(stereoData[0], micData, Int(micBuffer.frameLength) * MemoryLayout<Float>.size)
            if micBuffer.frameLength < framesToWrite {
                memset(stereoData[0].advanced(by: Int(micBuffer.frameLength)), 0, Int(framesToWrite - micBuffer.frameLength) * MemoryLayout<Float>.size)
            }
        } else {
            memset(stereoData[0], 0, Int(framesToWrite) * MemoryLayout<Float>.size)
        }

        // Fill right channel (system)
        if let systemBuffer = pendingSystemBuffer, let systemData = systemBuffer.floatChannelData?[0] {
            memcpy(stereoData[1], systemData, Int(systemBuffer.frameLength) * MemoryLayout<Float>.size)
            if systemBuffer.frameLength < framesToWrite {
                memset(stereoData[1].advanced(by: Int(systemBuffer.frameLength)), 0, Int(framesToWrite - systemBuffer.frameLength) * MemoryLayout<Float>.size)
            }
        } else {
            memset(stereoData[1], 0, Int(framesToWrite) * MemoryLayout<Float>.size)
        }

        writeToFile(stereoBuffer)

        pendingMicBuffer = nil
        pendingSystemBuffer = nil
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
