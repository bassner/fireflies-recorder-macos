//
//  AudioPostProcessor.swift
//  FirefliesRecorder
//
//  Post-processes stereo recordings (L=mic, R=system) by normalizing
//  each channel independently and merging to mono.
//
//  Memory-efficient streaming design: processes in chunks to handle
//  long recordings without excessive memory usage.
//

import Foundation
import AVFoundation

final class AudioPostProcessor {

    /// Target peak level in dB (e.g., -3 dB)
    private let targetPeakDB: Float = -3.0

    /// Minimum peak level to consider a channel "active" (in dB)
    /// Channels below this are considered silent and won't be boosted
    private let silenceThresholdDB: Float = -50.0

    /// Chunk size for streaming processing (1 second at 48kHz)
    private let chunkSize: AVAudioFrameCount = 48000

    /// Process a stereo file (L=mic, R=system) into a normalized mono file
    /// Uses streaming to minimize memory usage for long recordings
    /// - Parameters:
    ///   - inputURL: URL to stereo M4A file
    ///   - outputURL: URL for output mono M4A file (if nil, replaces input)
    /// - Returns: URL to the processed mono file
    func processToNormalizedMono(inputURL: URL, outputURL: URL? = nil) async throws -> URL {
        let finalOutputURL = outputURL ?? inputURL.deletingLastPathComponent()
            .appendingPathComponent(inputURL.deletingPathExtension().lastPathComponent + "_processed.m4a")

        print("AudioPostProcessor: Processing \(inputURL.lastPathComponent)")

        // Open input file
        let inputFile = try AVAudioFile(forReading: inputURL)
        let format = inputFile.processingFormat
        let totalFrames = AVAudioFrameCount(inputFile.length)

        guard format.channelCount == 2 else {
            print("AudioPostProcessor: Input is not stereo, copying as-is")
            if inputURL != finalOutputURL {
                try FileManager.default.copyItem(at: inputURL, to: finalOutputURL)
            }
            return finalOutputURL
        }

        let durationSeconds = Double(totalFrames) / format.sampleRate
        print("AudioPostProcessor: Processing \(totalFrames) frames (\(String(format: "%.1f", durationSeconds)) seconds) at \(format.sampleRate) Hz")

        // PASS 1: Scan for peak levels (streaming, no storage)
        print("AudioPostProcessor: Pass 1 - Scanning for peak levels...")
        var leftPeak: Float = 0
        var rightPeak: Float = 0

        inputFile.framePosition = 0
        var framesProcessed: AVAudioFrameCount = 0

        while framesProcessed < totalFrames {
            let framesToRead = min(chunkSize, totalFrames - framesProcessed)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
                throw PostProcessorError.bufferCreationFailed
            }

            try inputFile.read(into: buffer, frameCount: framesToRead)

            if let channelData = buffer.floatChannelData {
                // Scan left channel
                for i in 0..<Int(buffer.frameLength) {
                    let absVal = abs(channelData[0][i])
                    if absVal > leftPeak { leftPeak = absVal }
                }
                // Scan right channel
                for i in 0..<Int(buffer.frameLength) {
                    let absVal = abs(channelData[1][i])
                    if absVal > rightPeak { rightPeak = absVal }
                }
            }

            framesProcessed += buffer.frameLength
        }

        let leftPeakDB = linearToDecibels(leftPeak)
        let rightPeakDB = linearToDecibels(rightPeak)

        print("AudioPostProcessor: Left (mic) peak: \(String(format: "%.1f", leftPeakDB)) dB")
        print("AudioPostProcessor: Right (system) peak: \(String(format: "%.1f", rightPeakDB)) dB")

        // Calculate gain for each channel
        let leftGain = calculateGain(peakDB: leftPeakDB)
        let rightGain = calculateGain(peakDB: rightPeakDB)
        let leftActive = leftPeakDB > silenceThresholdDB
        let rightActive = rightPeakDB > silenceThresholdDB

        print("AudioPostProcessor: Left gain: \(String(format: "%.2f", leftGain))x, Right gain: \(String(format: "%.2f", rightGain))x")

        // PASS 2: Normalize and mix to mono (streaming)
        print("AudioPostProcessor: Pass 2 - Normalizing and mixing to mono...")

        // Prepare output file
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000
        ]

        try? FileManager.default.removeItem(at: finalOutputURL)
        let outputFile = try AVAudioFile(
            forWriting: finalOutputURL,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // Reset input file position
        inputFile.framePosition = 0
        framesProcessed = 0

        while framesProcessed < totalFrames {
            let framesToRead = min(chunkSize, totalFrames - framesProcessed)

            // Read stereo chunk
            guard let stereoBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
                throw PostProcessorError.bufferCreationFailed
            }
            try inputFile.read(into: stereoBuffer, frameCount: framesToRead)

            // Create mono output chunk
            guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: stereoBuffer.frameLength) else {
                throw PostProcessorError.bufferCreationFailed
            }
            monoBuffer.frameLength = stereoBuffer.frameLength

            guard let stereoData = stereoBuffer.floatChannelData,
                  let monoData = monoBuffer.floatChannelData?[0] else {
                throw PostProcessorError.noAudioData
            }

            // Mix normalized channels to mono
            for frame in 0..<Int(stereoBuffer.frameLength) {
                var sample: Float = 0

                if leftActive && rightActive {
                    let normalizedLeft = stereoData[0][frame] * leftGain
                    let normalizedRight = stereoData[1][frame] * rightGain
                    sample = (normalizedLeft + normalizedRight) * 0.5
                } else if leftActive {
                    sample = stereoData[0][frame] * leftGain
                } else if rightActive {
                    sample = stereoData[1][frame] * rightGain
                }

                monoData[frame] = softClip(sample)
            }

            // Write mono chunk
            try outputFile.write(from: monoBuffer)

            framesProcessed += stereoBuffer.frameLength

            // Progress logging every 10%
            let progress = Float(framesProcessed) / Float(totalFrames) * 100
            if Int(progress) % 10 == 0 && Int(progress) != Int(Float(framesProcessed - stereoBuffer.frameLength) / Float(totalFrames) * 100) {
                print("AudioPostProcessor: \(Int(progress))% complete")
            }
        }

        print("AudioPostProcessor: Wrote normalized mono file to \(finalOutputURL.lastPathComponent)")

        // If we're replacing the input, delete it and rename
        if outputURL == nil && inputURL != finalOutputURL {
            let tempURL = finalOutputURL
            let targetURL = inputURL

            try FileManager.default.removeItem(at: targetURL)
            try FileManager.default.moveItem(at: tempURL, to: targetURL)

            print("AudioPostProcessor: Replaced original file")
            return targetURL
        }

        return finalOutputURL
    }

    // MARK: - Analysis

    /// Find the peak absolute sample value
    private func findPeakLevel(_ samples: UnsafeMutablePointer<Float>, frameCount: Int) -> Float {
        var peak: Float = 0
        for i in 0..<frameCount {
            let absValue = abs(samples[i])
            if absValue > peak {
                peak = absValue
            }
        }
        return peak
    }

    /// Calculate RMS level (alternative to peak, not currently used)
    private func calculateRMS(_ samples: UnsafeMutablePointer<Float>, frameCount: Int) -> Float {
        var sum: Float = 0
        for i in 0..<frameCount {
            sum += samples[i] * samples[i]
        }
        return sqrt(sum / Float(frameCount))
    }

    // MARK: - Gain Calculation

    /// Calculate gain needed to bring peak to target level
    private func calculateGain(peakDB: Float) -> Float {
        // If below silence threshold, don't amplify (would just boost noise)
        guard peakDB > silenceThresholdDB else {
            return 1.0
        }

        // Calculate gain needed
        let gainDB = targetPeakDB - peakDB

        // Limit maximum gain to prevent excessive amplification of quiet signals
        let maxGainDB: Float = 24.0  // Max +24 dB boost
        let clampedGainDB = min(gainDB, maxGainDB)

        return decibelsToLinear(clampedGainDB)
    }

    // MARK: - Utilities

    private func linearToDecibels(_ linear: Float) -> Float {
        guard linear > 0 else { return -Float.infinity }
        return 20.0 * log10(linear)
    }

    private func decibelsToLinear(_ db: Float) -> Float {
        return pow(10.0, db / 20.0)
    }

    /// Soft clip to prevent harsh digital clipping
    private func softClip(_ sample: Float) -> Float {
        // Tanh-based soft clipper
        if abs(sample) < 0.9 {
            return sample
        }
        return tanh(sample)
    }

    // MARK: - Errors

    enum PostProcessorError: LocalizedError {
        case bufferCreationFailed
        case noAudioData
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .bufferCreationFailed:
                return "Failed to create audio buffer"
            case .noAudioData:
                return "No audio data in file"
            case .writeFailed:
                return "Failed to write output file"
            }
        }
    }
}
