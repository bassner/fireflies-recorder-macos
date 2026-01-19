//
//  AudioPostProcessor.swift
//  FirefliesRecorder
//
//  Post-processes stereo recordings (L=mic, R=system) by normalizing
//  each channel independently and merging to mono.
//

import Foundation
import AVFoundation

final class AudioPostProcessor {

    /// Target peak level in dB (e.g., -3 dB)
    private let targetPeakDB: Float = -3.0

    /// Minimum peak level to consider a channel "active" (in dB)
    /// Channels below this are considered silent and won't be boosted
    private let silenceThresholdDB: Float = -50.0

    /// Process a stereo file (L=mic, R=system) into a normalized mono file
    /// - Parameters:
    ///   - inputURL: URL to stereo M4A file
    ///   - outputURL: URL for output mono M4A file (if nil, replaces input)
    /// - Returns: URL to the processed mono file
    func processToNormalizedMono(inputURL: URL, outputURL: URL? = nil) async throws -> URL {
        let finalOutputURL = outputURL ?? inputURL.deletingLastPathComponent()
            .appendingPathComponent(inputURL.deletingPathExtension().lastPathComponent + "_processed.m4a")

        print("AudioPostProcessor: Processing \(inputURL.lastPathComponent)")

        // Read the stereo file
        let inputFile = try AVAudioFile(forReading: inputURL)
        let format = inputFile.processingFormat
        let frameCount = AVAudioFrameCount(inputFile.length)

        guard format.channelCount == 2 else {
            print("AudioPostProcessor: Input is not stereo, copying as-is")
            if inputURL != finalOutputURL {
                try FileManager.default.copyItem(at: inputURL, to: finalOutputURL)
            }
            return finalOutputURL
        }

        print("AudioPostProcessor: Reading \(frameCount) frames at \(format.sampleRate) Hz")

        // Read entire file into buffer
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw PostProcessorError.bufferCreationFailed
        }

        try inputFile.read(into: buffer)
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData else {
            throw PostProcessorError.noAudioData
        }

        let leftChannel = channelData[0]   // Mic
        let rightChannel = channelData[1]  // System

        // Analyze each channel
        let leftPeak = findPeakLevel(leftChannel, frameCount: Int(frameCount))
        let rightPeak = findPeakLevel(rightChannel, frameCount: Int(frameCount))

        let leftPeakDB = linearToDecibels(leftPeak)
        let rightPeakDB = linearToDecibels(rightPeak)

        print("AudioPostProcessor: Left (mic) peak: \(String(format: "%.1f", leftPeakDB)) dB")
        print("AudioPostProcessor: Right (system) peak: \(String(format: "%.1f", rightPeakDB)) dB")

        // Calculate gain for each channel
        let leftGain = calculateGain(peakDB: leftPeakDB)
        let rightGain = calculateGain(peakDB: rightPeakDB)

        print("AudioPostProcessor: Left gain: \(String(format: "%.2f", leftGain))x (\(String(format: "%.1f", linearToDecibels(leftGain))) dB)")
        print("AudioPostProcessor: Right gain: \(String(format: "%.2f", rightGain))x (\(String(format: "%.1f", linearToDecibels(rightGain))) dB)")

        // Create mono output buffer
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
        guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameCount) else {
            throw PostProcessorError.bufferCreationFailed
        }
        monoBuffer.frameLength = frameCount

        guard let monoData = monoBuffer.floatChannelData?[0] else {
            throw PostProcessorError.noAudioData
        }

        // Mix normalized channels to mono
        let leftActive = leftPeakDB > silenceThresholdDB
        let rightActive = rightPeakDB > silenceThresholdDB

        for frame in 0..<Int(frameCount) {
            var sample: Float = 0

            if leftActive && rightActive {
                // Both channels active - mix with equal weight after normalization
                let normalizedLeft = leftChannel[frame] * leftGain
                let normalizedRight = rightChannel[frame] * rightGain
                sample = (normalizedLeft + normalizedRight) * 0.5
            } else if leftActive {
                // Only left (mic) active
                sample = leftChannel[frame] * leftGain
            } else if rightActive {
                // Only right (system) active
                sample = rightChannel[frame] * rightGain
            }
            // else: both silent, sample stays 0

            // Soft clip to prevent any overs
            monoData[frame] = softClip(sample)
        }

        // Write output file
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000
        ]

        // Remove existing output file if it exists
        try? FileManager.default.removeItem(at: finalOutputURL)

        let outputFile = try AVAudioFile(
            forWriting: finalOutputURL,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        try outputFile.write(from: monoBuffer)

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
