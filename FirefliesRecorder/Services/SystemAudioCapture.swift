//
//  SystemAudioCapture.swift
//  FirefliesRecorder
//
//  Captures system audio using ScreenCaptureKit (macOS 14.2+)
//

import Foundation
import AVFoundation
import ScreenCaptureKit

@available(macOS 14.2, *)
final class SystemAudioCapture: NSObject, AudioCapture {
    var onBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onError: ((Error) -> Void)?

    private var stream: SCStream?
    private var audioOutput: AudioStreamOutput?
    private var videoOutput: VideoStreamOutput?
    private(set) var isCapturing = false

    private let levelUpdateInterval: TimeInterval = 0.05
    private var lastLevelUpdate: Date = .distantPast
    private var hasLoggedFormat = false

    override init() {
        super.init()
    }

    func startCapturing() throws {
        guard !isCapturing else { return }

        // Don't call CGRequestScreenCaptureAccess() - it shows a prompt every time
        // Just try to capture and handle failure gracefully
        // User must manually enable in System Settings > Privacy & Security > Screen Recording

        Task {
            do {
                try await setupAndStartCapture()
            } catch {
                print("System audio capture failed: \(error)")
                // Don't call onError - this is expected if permission not granted
                // The app will continue with mic-only recording
            }
        }
    }

    private func setupAndStartCapture() async throws {
        // Get available content
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        // Get the main display
        guard let display = availableContent.displays.first else {
            throw SystemAudioCaptureError.noDisplayFound
        }

        // Create filter to capture all audio
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        // Configure stream for audio only
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48000
        configuration.channelCount = 2

        // Minimal video config (required but we don't use it)
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false

        // Create stream
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream

        // Create and add video output (required even if we only want audio)
        let videoOutput = VideoStreamOutput()
        self.videoOutput = videoOutput
        try stream.addStreamOutput(videoOutput, type: .screen, sampleHandlerQueue: .global(qos: .background))

        // Create and add audio output
        let audioOutput = AudioStreamOutput { [weak self] sampleBuffer in
            self?.handleAudioBuffer(sampleBuffer)
        }
        self.audioOutput = audioOutput
        try stream.addStreamOutput(audioOutput, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

        // Start capturing
        try await stream.startCapture()

        await MainActor.run {
            self.isCapturing = true
            print("System audio capture started")
        }
    }

    func stopCapturing() {
        guard isCapturing else { return }

        Task {
            try? await stream?.stopCapture()
            await MainActor.run {
                self.stream = nil
                self.audioOutput = nil
                self.videoOutput = nil
                self.isCapturing = false
                print("System audio capture stopped")
            }
        }
    }

    private func handleAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = sampleBuffer.formatDescription,
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        let asbd = asbdPointer.pointee

        // Get frame count from sample buffer
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }

        // Debug: print source format once
        if !hasLoggedFormat {
            hasLoggedFormat = true
            print("System audio ASBD - channels: \(asbd.mChannelsPerFrame), rate: \(asbd.mSampleRate), bytesPerFrame: \(asbd.mBytesPerFrame), bitsPerChannel: \(asbd.mBitsPerChannel), interleaved: \((asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0)")
        }

        // Get the raw data from the sample buffer
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }

        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let dataStatus = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

        guard dataStatus == kCMBlockBufferNoErr, let data = dataPointer, totalLength > 0 else {
            return
        }

        // Our output format: 48kHz stereo non-interleaved Float32
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 2,
            interleaved: false
        ) else { return }

        // Create output buffer
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }
        outputBuffer.frameLength = AVAudioFrameCount(frameCount)

        // Copy data based on source format
        guard let floatChannelData = outputBuffer.floatChannelData else { return }

        let channelCount = Int(asbd.mChannelsPerFrame)
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0

        if isFloat && isNonInterleaved && channelCount == 2 {
            // Source is already Float32 non-interleaved stereo - copy directly
            // For non-interleaved, each channel's data is contiguous
            let floatData = UnsafeRawPointer(data).assumingMemoryBound(to: Float.self)
            let framesPerChannel = frameCount

            // Channel 0
            memcpy(floatChannelData[0], floatData, framesPerChannel * MemoryLayout<Float>.size)
            // Channel 1
            memcpy(floatChannelData[1], floatData.advanced(by: framesPerChannel), framesPerChannel * MemoryLayout<Float>.size)

        } else if isFloat && !isNonInterleaved && channelCount == 2 {
            // Source is Float32 interleaved stereo - deinterleave
            let floatData = UnsafeRawPointer(data).assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                floatChannelData[0][frame] = floatData[frame * 2]
                floatChannelData[1][frame] = floatData[frame * 2 + 1]
            }

        } else if isFloat && channelCount == 1 {
            // Mono - duplicate to stereo
            let floatData = UnsafeRawPointer(data).assumingMemoryBound(to: Float.self)
            memcpy(floatChannelData[0], floatData, frameCount * MemoryLayout<Float>.size)
            memcpy(floatChannelData[1], floatData, frameCount * MemoryLayout<Float>.size)

        } else {
            // Unknown format - log and skip
            print("System audio: Unhandled format - channels: \(channelCount), interleaved: \(!isNonInterleaved), float: \(isFloat)")
            return
        }

        // Send to callback
        onBuffer?(outputBuffer, AVAudioTime(sampleTime: 0, atRate: 48000))
        updateLevel(buffer: outputBuffer)
    }

    private func updateLevel(buffer: AVAudioPCMBuffer) {
        let now = Date()
        if now.timeIntervalSince(lastLevelUpdate) >= levelUpdateInterval {
            lastLevelUpdate = now
            let level = calculateLevel(buffer: buffer)
            onLevel?(level)
        }
    }

    private func calculateLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        guard frameLength > 0 else { return 0 }

        var sum: Float = 0

        for channel in 0..<channelCount {
            let data = channelData[channel]
            for frame in 0..<frameLength {
                let sample = data[frame]
                sum += sample * sample
            }
        }

        let rms = sqrt(sum / Float(frameLength * channelCount))
        let db = 20 * log10(max(rms, 0.000001))
        let normalized = (db + 60) / 60
        return max(0, min(1, normalized))
    }

    enum SystemAudioCaptureError: LocalizedError {
        case permissionDenied
        case noDisplayFound
        case streamConfigurationFailed
        case captureStartFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Screen recording permission required for system audio capture"
            case .noDisplayFound:
                return "No display found for capture"
            case .streamConfigurationFailed:
                return "Failed to configure audio stream"
            case .captureStartFailed:
                return "Failed to start audio capture"
            }
        }
    }
}

@available(macOS 14.2, *)
extension SystemAudioCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error)
        Task { @MainActor in
            self.isCapturing = false
        }
    }
}

@available(macOS 14.2, *)
private class AudioStreamOutput: NSObject, SCStreamOutput {
    private let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        handler(sampleBuffer)
    }
}

@available(macOS 14.2, *)
private class VideoStreamOutput: NSObject, SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Ignore video frames - we only need audio
    }
}
