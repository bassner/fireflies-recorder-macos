//
//  SettingsView.swift
//  FirefliesRecorder
//
//  Settings window for API key and preferences
//

import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .environmentObject(settingsManager)

            APISettingsView()
                .tabItem {
                    Label("API", systemImage: "key")
                }
                .environmentObject(settingsManager)

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 450, height: 250)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        Form {
            Section {
                Toggle("Record Microphone", isOn: $settingsManager.recordMicrophone)
                Toggle("Record System Audio", isOn: $settingsManager.recordSystemAudio)
            } header: {
                Text("Audio Sources")
            }

            Section {
                Toggle("Auto-upload to Fireflies", isOn: $settingsManager.autoUpload)

                if settingsManager.autoUpload {
                    Picker("Minimum Duration", selection: $settingsManager.minimumUploadDuration) {
                        Text("15 seconds").tag(TimeInterval(15))
                        Text("1 minute").tag(TimeInterval(60))
                        Text("3 minutes").tag(TimeInterval(180))
                        Text("5 minutes").tag(TimeInterval(300))
                        Text("10 minutes").tag(TimeInterval(600))
                    }
                    .pickerStyle(.menu)
                }

            } header: {
                Text("Upload")
            }

            Section {
                Toggle("Delete recordings on launch", isOn: $settingsManager.deleteRecordingsOnLaunch)
            } header: {
                Text("Storage")
            } footer: {
                Text("Automatically delete old recordings when the app starts.")
            }

            Section {
                Toggle("Launch at login", isOn: $settingsManager.launchAtLogin)
            } header: {
                Text("Startup")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct APISettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var apiKeyInput: String = ""
    @State private var showAPIKey = false

    var body: some View {
        Form {
            Section {
                HStack {
                    if showAPIKey {
                        TextField("API Key", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(action: { showAPIKey.toggle() }) {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                Button("Save API Key") {
                    settingsManager.firefliesAPIKey = apiKeyInput.isEmpty ? nil : apiKeyInput
                }
                .disabled(apiKeyInput.isEmpty && !settingsManager.hasAPIKey)

                if settingsManager.hasAPIKey {
                    Label("API key is configured", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            } header: {
                Text("Fireflies API")
            } footer: {
                Text("Get your API key from [Fireflies.ai Settings](https://app.fireflies.ai/integrations/custom/fireflies)")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            apiKeyInput = settingsManager.firefliesAPIKey ?? ""
        }
    }
}

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle Recording:", name: .toggleRecording)
                KeyboardShortcuts.Recorder("Toggle Mic Mute:", name: .toggleMicMute)
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Use these shortcuts to control recording from anywhere.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager())
}
