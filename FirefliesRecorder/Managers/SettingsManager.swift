//
//  SettingsManager.swift
//  FirefliesRecorder
//
//  Manages user preferences and API credentials
//

import Foundation
import Security
import AVFoundation
import AppKit
import ServiceManagement

enum PermissionStatus {
    case granted
    case denied
    case unknown
}

@MainActor
final class SettingsManager: ObservableObject {
    @Published var selectedMicrophoneID: String? {
        didSet {
            UserDefaults.standard.set(selectedMicrophoneID, forKey: Keys.selectedMicrophone)
        }
    }

    @Published var autoUpload: Bool {
        didSet {
            UserDefaults.standard.set(autoUpload, forKey: Keys.autoUpload)
        }
    }

    @Published var minimumUploadDuration: TimeInterval {
        didSet {
            UserDefaults.standard.set(minimumUploadDuration, forKey: Keys.minimumUploadDuration)
        }
    }

    @Published var recordSystemAudio: Bool {
        didSet {
            UserDefaults.standard.set(recordSystemAudio, forKey: Keys.recordSystemAudio)
        }
    }

    @Published var recordMicrophone: Bool {
        didSet {
            UserDefaults.standard.set(recordMicrophone, forKey: Keys.recordMicrophone)
        }
    }

    @Published var deleteRecordingsOnLaunch: Bool {
        didSet {
            UserDefaults.standard.set(deleteRecordingsOnLaunch, forKey: Keys.deleteRecordingsOnLaunch)
        }
    }

    @Published var meetingLanguage: String {
        didSet {
            UserDefaults.standard.set(meetingLanguage, forKey: Keys.meetingLanguage)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("SettingsManager: Failed to \(launchAtLogin ? "enable" : "disable") launch at login: \(error)")
                // Revert on failure
                Task { @MainActor in
                    self.launchAtLogin = !launchAtLogin
                }
            }
        }
    }

    @Published private(set) var microphonePermission: PermissionStatus = .unknown
    @Published private(set) var screenRecordingPermission: PermissionStatus = .unknown

    private enum Keys {
        static let selectedMicrophone = "selectedMicrophoneID"
        static let autoUpload = "autoUpload"
        static let minimumUploadDuration = "minimumUploadDuration"
        static let recordSystemAudio = "recordSystemAudio"
        static let recordMicrophone = "recordMicrophone"
        static let deleteRecordingsOnLaunch = "deleteRecordingsOnLaunch"
        static let meetingLanguage = "meetingLanguage"
        static let keychainService = "dev.bassner.ffrecorder"
        static let apiKeyAccount = "fireflies-api-key"
    }

    init() {
        self.selectedMicrophoneID = UserDefaults.standard.string(forKey: Keys.selectedMicrophone)
        self.autoUpload = UserDefaults.standard.bool(forKey: Keys.autoUpload)
        self.minimumUploadDuration = UserDefaults.standard.double(forKey: Keys.minimumUploadDuration)
        self.recordSystemAudio = UserDefaults.standard.object(forKey: Keys.recordSystemAudio) as? Bool ?? true
        self.recordMicrophone = UserDefaults.standard.object(forKey: Keys.recordMicrophone) as? Bool ?? true
        self.deleteRecordingsOnLaunch = UserDefaults.standard.object(forKey: Keys.deleteRecordingsOnLaunch) as? Bool ?? true
        self.meetingLanguage = UserDefaults.standard.string(forKey: Keys.meetingLanguage) ?? Self.systemLanguageCode()
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        if minimumUploadDuration == 0 {
            minimumUploadDuration = 180 // Default 3 minutes
        }

        // Check permissions on init
        checkPermissions()

        // Clean up old recordings if enabled
        if deleteRecordingsOnLaunch {
            cleanupOldRecordings()
        }
    }

    // MARK: - Recording Cleanup

    func cleanupOldRecordings() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsDir = documentsURL.appendingPathComponent("Fireflies Recordings", isDirectory: true)

        guard FileManager.default.fileExists(atPath: recordingsDir.path) else { return }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "m4a" {
                try FileManager.default.removeItem(at: file)
            }
            if !files.isEmpty {
                print("SettingsManager: Cleaned up \(files.count) old recording(s)")
            }
        } catch {
            print("SettingsManager: Failed to cleanup recordings: \(error)")
        }
    }

    // MARK: - Permission Checking

    func checkPermissions() {
        checkMicrophonePermission()
        checkScreenRecordingPermission()
    }

    func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermission = .granted
        case .denied, .restricted:
            microphonePermission = .denied
        case .notDetermined:
            microphonePermission = .unknown
        @unknown default:
            microphonePermission = .unknown
        }
    }

    func checkScreenRecordingPermission() {
        // CGPreflightScreenCaptureAccess doesn't prompt - just checks current state
        if CGPreflightScreenCaptureAccess() {
            screenRecordingPermission = .granted
        } else {
            screenRecordingPermission = .denied
        }
    }

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.microphonePermission = granted ? .granted : .denied
            }
        }
    }

    func requestScreenRecordingPermission() {
        // Opens System Settings to Screen Recording pane
        CGRequestScreenCaptureAccess()
    }

    func openSystemSettingsScreenRecording() {
        // First trigger the permission request - this registers the app in the Screen Recording list
        // Without this, the app won't appear in System Settings
        CGRequestScreenCaptureAccess()

        // Then open System Settings to the Screen Recording pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Returns true if all required permissions for the current settings are granted
    var canStartRecording: Bool {
        if recordMicrophone && microphonePermission != .granted {
            return false
        }
        if recordSystemAudio && screenRecordingPermission != .granted {
            return false
        }
        // At least one source must be enabled and permitted
        return (recordMicrophone && microphonePermission == .granted) ||
               (recordSystemAudio && screenRecordingPermission == .granted)
    }

    // MARK: - API Key Management (Keychain)

    var firefliesAPIKey: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Keys.keychainService,
                kSecAttrAccount as String: Keys.apiKeyAccount,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            guard status == errSecSuccess,
                  let data = result as? Data,
                  let key = String(data: data, encoding: .utf8) else {
                return nil
            }

            return key
        }
        set {
            // Delete existing
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Keys.keychainService,
                kSecAttrAccount as String: Keys.apiKeyAccount
            ]
            SecItemDelete(deleteQuery as CFDictionary)

            // Add new if not nil
            guard let newValue = newValue,
                  let data = newValue.data(using: .utf8) else {
                objectWillChange.send()
                return
            }

            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Keys.keychainService,
                kSecAttrAccount as String: Keys.apiKeyAccount,
                kSecValueData as String: data
            ]

            SecItemAdd(addQuery as CFDictionary, nil)
            objectWillChange.send()
        }
    }

    var hasAPIKey: Bool {
        firefliesAPIKey != nil && !firefliesAPIKey!.isEmpty
    }

    // MARK: - System Language Detection

    private static let supportedLanguages = ["en", "es", "fr", "de", "it", "pt", "nl", "ja", "ko", "zh", "ru", "ar", "hi"]

    /// Returns the system language code if supported, otherwise "auto"
    private static func systemLanguageCode() -> String {
        guard let preferredLanguage = Locale.preferredLanguages.first else {
            return "auto"
        }

        // Extract the language code (e.g., "en" from "en-US" or "zh-Hans")
        let langCode = Locale(identifier: preferredLanguage).language.languageCode?.identifier ?? "en"

        // Check if it's in our supported list
        if supportedLanguages.contains(langCode) {
            return langCode
        }

        return "auto"
    }
}
