//
//  RecordingState.swift
//  FirefliesRecorder
//
//  Observable state for recording status
//

import Foundation
import Combine

@MainActor
final class RecordingState: ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var duration: TimeInterval = 0
    @Published var micLevel: Float = 0
    @Published var systemLevel: Float = 0
    @Published var currentRecordingURL: URL?
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0
    @Published var lastError: RecordingError?

    private var timer: Timer?
    private var startTime: Date?

    enum RecordingError: LocalizedError {
        case microphonePermissionDenied
        case screenRecordingPermissionDenied
        case audioEngineFailure(String)
        case fileWriteFailure(String)
        case uploadFailure(String)

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone access denied. Please enable in System Settings > Privacy & Security > Microphone."
            case .screenRecordingPermissionDenied:
                return "Screen recording permission required for system audio. Please enable in System Settings > Privacy & Security > Screen Recording."
            case .audioEngineFailure(let msg):
                return "Audio engine error: \(msg)"
            case .fileWriteFailure(let msg):
                return "Failed to write audio file: \(msg)"
            case .uploadFailure(let msg):
                return "Upload failed: \(msg)"
            }
        }
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func startRecording(url: URL) {
        isRecording = true
        isPaused = false
        duration = 0
        currentRecordingURL = url
        startTime = Date()
        lastError = nil

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.startTime, !self.isPaused else { return }
                self.duration = Date().timeIntervalSince(start)
            }
        }
    }

    func stopRecording() {
        timer?.invalidate()
        timer = nil
        isRecording = false
        isPaused = false
        startTime = nil
    }

    func pauseRecording() {
        isPaused = true
    }

    func resumeRecording() {
        isPaused = false
    }

    func updateLevels(mic: Float, system: Float) {
        micLevel = mic
        systemLevel = system
    }

    func setError(_ error: RecordingError) {
        lastError = error
    }

    func clearError() {
        lastError = nil
    }
}
