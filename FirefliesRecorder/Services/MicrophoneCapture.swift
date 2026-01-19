//
//  MicrophoneCapture.swift
//  FirefliesRecorder
//
//  Captures microphone audio using AVAudioEngine
//

import Foundation
import AVFoundation

protocol AudioCapture: AnyObject {
    var isCapturing: Bool { get }
    func startCapturing() throws
    func stopCapturing()
}

final class MicrophoneCapture: AudioCapture {
    var onBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onError: ((Error) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var selectedDeviceUID: String?
    private(set) var isCapturing = false

    private let levelUpdateInterval: TimeInterval = 0.05
    private var lastLevelUpdate: Date = .distantPast

    /// When muted, sends silence instead of actual audio
    var isMuted: Bool = false

    var outputFormat: AVAudioFormat? {
        audioEngine.inputNode.outputFormat(forBus: 0)
    }

    init(deviceUID: String? = nil) {
        self.selectedDeviceUID = deviceUID
    }

    func setDevice(uid: String?) {
        let wasCapturing = isCapturing
        if wasCapturing {
            stopCapturing()
        }

        selectedDeviceUID = uid

        if wasCapturing {
            try? startCapturing()
        }
    }

    func startCapturing() throws {
        guard !isCapturing else { return }

        // Request microphone permission
        guard checkMicrophonePermission() else {
            throw MicrophoneCaptureError.permissionDenied
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MicrophoneCaptureError.invalidFormat
        }

        print("Mic format: \(format)")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            self?.processBuffer(buffer, at: time)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isCapturing = true
        print("Microphone capture started")
    }

    func stopCapturing() {
        guard isCapturing else { return }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isCapturing = false
        print("Microphone capture stopped")
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        if isMuted {
            // Send silence when muted
            if let silentBuffer = createSilentBuffer(like: buffer) {
                onBuffer?(silentBuffer, time)
            }
            onLevel?(0)
        } else {
            // Send buffer to callback
            onBuffer?(buffer, time)

            // Update level periodically
            let now = Date()
            if now.timeIntervalSince(lastLevelUpdate) >= levelUpdateInterval {
                lastLevelUpdate = now
                let level = calculateLevel(buffer: buffer)
                onLevel?(level)
            }
        }
    }

    private func createSilentBuffer(like buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let silentBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        silentBuffer.frameLength = buffer.frameLength

        // Zero out the buffer
        if let channelData = silentBuffer.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                memset(channelData[channel], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        }

        return silentBuffer
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
        // Convert to decibels and normalize to 0-1 range
        let db = 20 * log10(max(rms, 0.000001))
        let normalized = (db + 60) / 60 // Assuming -60dB to 0dB range
        return max(0, min(1, normalized))
    }

    private func checkMicrophonePermission() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            var granted = false
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { result in
                granted = result
                semaphore.signal()
            }
            semaphore.wait()
            return granted
        default:
            return false
        }
    }

    enum MicrophoneCaptureError: LocalizedError {
        case permissionDenied
        case invalidFormat
        case deviceNotFound
        case engineStartFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone access denied"
            case .invalidFormat:
                return "Invalid audio format"
            case .deviceNotFound:
                return "Audio device not found"
            case .engineStartFailed:
                return "Failed to start audio engine"
            }
        }
    }
}
