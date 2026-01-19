//
//  AudioRecorder.swift
//  FirefliesRecorder
//
//  Orchestrates recording from microphone and system audio
//

import Foundation
import AVFoundation

@MainActor
final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var micLevel: Float = 0
    @Published private(set) var systemLevel: Float = 0
    @Published private(set) var error: Error?

    private var micCapture: MicrophoneCapture?
    private var systemCapture: (any AudioCapture)?
    private var mixer: AudioMixer?

    private var currentRecordingURL: URL?

    var recordMicrophone: Bool = true
    var recordSystemAudio: Bool = true
    var isMicMuted: Bool = false {
        didSet {
            micCapture?.isMuted = isMicMuted
        }
    }

    init() {}

    func startRecording(micDeviceUID: String? = nil) async throws -> URL {
        guard !isRecording else {
            throw RecorderError.alreadyRecording
        }

        error = nil

        // Create output URL
        let outputURL = createOutputURL()
        currentRecordingURL = outputURL

        // Initialize mixer
        mixer = AudioMixer(outputURL: outputURL)
        mixer?.hasMicSource = recordMicrophone
        mixer?.hasSystemSource = recordSystemAudio
        try mixer?.startWriting()

        // Start microphone capture
        if recordMicrophone {
            let mic = MicrophoneCapture(deviceUID: micDeviceUID)
            mic.onBuffer = { [weak self] buffer, time in
                self?.mixer?.appendMicBuffer(buffer, at: time)
            }
            mic.onLevel = { [weak self] level in
                Task { @MainActor [weak self] in
                    self?.micLevel = level
                }
            }
            micCapture = mic
            try mic.startCapturing()
        }

        // Start system audio capture (non-fatal if it fails)
        if recordSystemAudio {
            if #available(macOS 14.2, *) {
                do {
                    let systemCap = SystemAudioCapture()
                    systemCap.onBuffer = { [weak self] buffer, time in
                        self?.mixer?.appendSystemBuffer(buffer, at: time)
                    }
                    systemCap.onLevel = { [weak self] level in
                        Task { @MainActor [weak self] in
                            self?.systemLevel = level
                        }
                    }
                    systemCap.onError = { error in
                        print("System audio error: \(error.localizedDescription)")
                    }
                    systemCapture = systemCap
                    try systemCap.startCapturing()
                } catch {
                    // Don't fail the whole recording - just continue without system audio
                    print("System audio capture unavailable: \(error.localizedDescription)")
                    print("Continuing with microphone only...")
                }
            } else {
                print("System audio capture requires macOS 14.2+")
            }
        }

        isRecording = true
        return outputURL
    }

    func stopRecording() async throws -> URL {
        guard isRecording else {
            throw RecorderError.notRecording
        }

        // Stop captures
        micCapture?.stopCapturing()
        micCapture = nil

        systemCapture?.stopCapturing()
        systemCapture = nil

        // Finish writing stereo file
        guard let mixer = mixer else {
            throw RecorderError.noMixer
        }

        let stereoURL = try await mixer.stopWriting()
        self.mixer = nil

        isRecording = false
        micLevel = 0
        systemLevel = 0

        // Post-process: normalize each channel and merge to mono
        print("AudioRecorder: Starting post-processing...")
        let postProcessor = AudioPostProcessor()
        let finalURL = try await postProcessor.processToNormalizedMono(inputURL: stereoURL)
        print("AudioRecorder: Post-processing complete")

        return finalURL
    }

    func cancelRecording() {
        micCapture?.stopCapturing()
        micCapture = nil

        systemCapture?.stopCapturing()
        systemCapture = nil

        // Delete partial file
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        mixer = nil
        isRecording = false
        micLevel = 0
        systemLevel = 0
    }

    private func createOutputURL() -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let filename = "Recording_\(timestamp).m4a"

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsDir = documentsURL.appendingPathComponent("Fireflies Recordings", isDirectory: true)

        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        return recordingsDir.appendingPathComponent(filename)
    }

    enum RecorderError: LocalizedError {
        case alreadyRecording
        case notRecording
        case noMixer
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .alreadyRecording:
                return "Recording is already in progress"
            case .notRecording:
                return "No recording in progress"
            case .noMixer:
                return "Audio mixer not initialized"
            case .permissionDenied:
                return "Required permissions not granted"
            }
        }
    }
}
