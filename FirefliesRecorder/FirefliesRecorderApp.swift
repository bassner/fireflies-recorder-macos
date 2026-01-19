//
//  FirefliesRecorderApp.swift
//  FirefliesRecorder
//
//  A macOS menu bar app for recording meetings and uploading to Fireflies.ai
//

import SwiftUI

@main
struct FirefliesRecorderApp: App {
    @StateObject private var recordingState = RecordingState()
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var audioDeviceManager = AudioDeviceManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(recordingState)
                .environmentObject(settingsManager)
                .environmentObject(audioDeviceManager)
        } label: {
            Image(systemName: recordingState.isRecording ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(settingsManager)
        }
    }
}

