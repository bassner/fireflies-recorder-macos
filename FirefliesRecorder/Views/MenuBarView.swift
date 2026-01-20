//
//  MenuBarView.swift
//  FirefliesRecorder
//
//  Main menu bar dropdown UI
//

import SwiftUI
import KeyboardShortcuts

struct MenuBarView: View {
    @EnvironmentObject var recordingState: RecordingState
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var audioDeviceManager: AudioDeviceManager

    @StateObject private var audioRecorder = AudioRecorder()

    @State private var currentStatus: RecorderStatus = .idle
    @State private var lastRecordingURL: URL?
    @State private var errorMessage: String?
    @State private var isMicMuted: Bool = false
    @State private var isWindowOpen: Bool = false

    @Environment(\.openSettings) private var openSettingsAction

    enum RecorderStatus: Equatable {
        case idle
        case recording
        case processing
        case uploading
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Permission warnings (only when idle and there are issues)
            if currentStatus == .idle && hasPermissionIssues {
                permissionWarningsView
                Divider()
            }

            // Audio levels (only during active recording)
            if isActivelyRecording {
                audioLevelsView
                Divider()
            }

            // Microphone selector
            microphoneSelectorView

            Divider()

            // Upload toggle
            uploadToggleView

            Divider()

            // Record button
            recordButtonView

            // Error display (inline, not modal)
            if let error = errorMessage {
                Divider()
                errorView(message: error)
            }

            Divider()

            // Footer actions
            footerView
        }
        .frame(width: 280)
        .onAppear {
            isWindowOpen = true
            setupKeyboardShortcut()
            settingsManager.checkPermissions()
            // Reposition any active toast below the window
            ToastWindowController.reposition(belowMenuBar: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Re-check permissions when app becomes active (e.g., after returning from System Settings)
            settingsManager.checkPermissions()
        }
        .onDisappear {
            isWindowOpen = false
            // Reposition any active toast to bottom of screen
            ToastWindowController.reposition(belowMenuBar: false)
        }
        .onChange(of: audioDeviceManager.inputDevices) { _, newDevices in
            // Validate selected microphone still exists when device list changes
            if let selectedID = settingsManager.selectedMicrophoneID,
               !newDevices.contains(where: { $0.uid == selectedID }) {
                // Selected device no longer exists - show warning (only when idle)
                if currentStatus == .idle {
                    showToast(message: "Mic disconnected", style: .error, duration: 3.0)
                }
                // Reset to system default
                settingsManager.selectedMicrophoneID = nil
            }
        }
    }

    private var hasPermissionIssues: Bool {
        (settingsManager.recordMicrophone && settingsManager.microphonePermission != .granted) ||
        (settingsManager.recordSystemAudio && settingsManager.screenRecordingPermission != .granted)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(isActivelyRecording ? .red : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Fireflies Recorder")
                    .font(.headline)

                // Status text based on current state
                switch currentStatus {
                case .recording:
                    Text(recordingState.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.red)
                        .monospacedDigit()
                case .processing:
                    Text("Processing audio...")
                        .font(.caption)
                        .foregroundColor(.orange)
                case .uploading:
                    Text("Uploading to Fireflies...")
                        .font(.caption)
                        .foregroundColor(.blue)
                case .idle:
                    if settingsManager.canStartRecording {
                        Text("Ready to record")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Permissions required")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // Recording indicator
            if isActivelyRecording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0.5)
                    }
            }
        }
        .padding()
    }

    // MARK: - Audio Levels (directly from audioRecorder)

    private var audioLevelsView: some View {
        VStack(spacing: 8) {
            if settingsManager.recordMicrophone {
                HStack(spacing: 8) {
                    AudioLevelMeter(
                        level: isMicMuted ? 0 : audioRecorder.micLevel,
                        label: "Microphone",
                        color: isMicMuted ? .secondary : .blue
                    )

                    Button(action: toggleMicMute) {
                        Image(systemName: isMicMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 14))
                            .foregroundColor(isMicMuted ? .red : .blue)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(isMicMuted ? "Unmute microphone (⌘⌥M)" : "Mute microphone (⌘⌥M)")
                }
            }
            if settingsManager.recordSystemAudio {
                HStack(spacing: 8) {
                    AudioLevelMeter(level: audioRecorder.systemLevel, label: "System Audio", color: .orange)
                    // Spacer to align with mic row
                    Color.clear.frame(width: 24, height: 24)
                }
            }
        }
        .padding()
    }

    private func toggleMicMute() {
        isMicMuted.toggle()
        audioRecorder.isMicMuted = isMicMuted

        if isMicMuted {
            showToast(message: "Microphone muted", style: .info)
        } else {
            showToast(message: "Microphone unmuted", style: .info)
        }
    }

    // MARK: - Microphone Selector

    private var microphoneSelectorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Microphone")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $settingsManager.selectedMicrophoneID) {
                    Text("System Default")
                        .tag(nil as String?)

                    ForEach(audioDeviceManager.inputDevices) { device in
                        Text(device.name)
                            .tag(device.uid as String?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(currentStatus != .idle)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Meeting Language")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $settingsManager.meetingLanguage) {
                    Text("Auto-detect").tag("auto")
                    Divider()
                    Text("English").tag("en")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("German").tag("de")
                    Text("Italian").tag("it")
                    Text("Portuguese").tag("pt")
                    Text("Dutch").tag("nl")
                    Text("Japanese").tag("ja")
                    Text("Korean").tag("ko")
                    Text("Chinese").tag("zh")
                    Text("Russian").tag("ru")
                    Text("Arabic").tag("ar")
                    Text("Hindi").tag("hi")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(currentStatus != .idle)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Upload Toggle

    private var uploadToggleView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.up.circle")
                    .foregroundColor(settingsManager.autoUpload ? .orange : .secondary)
                Text("Upload to Fireflies")
                    .font(.body)

                Spacer()

                Toggle("", isOn: $settingsManager.autoUpload)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .disabled(!settingsManager.hasAPIKey)
            .opacity(settingsManager.hasAPIKey ? 1 : 0.5)

            if settingsManager.hasAPIKey {
                Button(action: openFirefliesNotebooks) {
                    Text("Open Fireflies Notebooks")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            } else {
                SettingsLink {
                    Text("Configure API key in Settings...")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Record Button

    /// Whether the record button can be interacted with
    /// Returns true only when we're idle (ready to start) or recording (can stop)
    private var canRecord: Bool {
        switch currentStatus {
        case .idle:
            // Can start a new recording if permissions allow
            return settingsManager.canStartRecording
        case .recording:
            // Can stop the current recording
            return true
        case .processing, .uploading:
            // Cannot interact while processing or uploading
            return false
        }
    }

    /// Whether we're currently recording (for button appearance)
    private var isActivelyRecording: Bool {
        currentStatus == .recording
    }

    /// Text for the record button based on current status
    private var recordButtonText: String {
        switch currentStatus {
        case .idle:
            return "Start Recording"
        case .recording:
            return "Stop Recording"
        case .processing:
            return "Processing..."
        case .uploading:
            return "Uploading..."
        }
    }

    /// Icon for the record button based on current status
    private var recordButtonIcon: String {
        switch currentStatus {
        case .idle:
            return "record.circle"
        case .recording:
            return "stop.circle.fill"
        case .processing:
            return "gear.circle"
        case .uploading:
            return "arrow.up.circle"
        }
    }

    private var recordingShortcutText: String {
        KeyboardShortcuts.getShortcut(for: .toggleRecording)?.description ?? "⌘⌥R"
    }

    private var recordButtonView: some View {
        Button(action: toggleRecording) {
            HStack {
                // Icon with appropriate styling based on status
                Group {
                    if currentStatus == .processing || currentStatus == .uploading {
                        // Show spinning indicator for processing/uploading
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: recordButtonIcon)
                            .font(.title2)
                            .foregroundStyle(isActivelyRecording ? .red : (canRecord ? .primary : .secondary))
                    }
                }

                Text(recordButtonText)
                    .font(.body.weight(.medium))
                    .foregroundStyle(canRecord ? .primary : .secondary)

                Spacer()

                // Only show shortcut when we can actually use it
                if currentStatus == .idle || currentStatus == .recording {
                    Text(recordingShortcutText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canRecord)
        .padding()
    }

    // MARK: - Error View (inline)

    private func errorView(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.caption)

            Text(message)
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(2)

            Spacer()

            Button(action: { errorMessage = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.1))
    }

    // MARK: - Permission Warnings

    private var permissionWarningsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if settingsManager.recordMicrophone && settingsManager.microphonePermission != .granted {
                permissionRow(
                    icon: "mic.slash.fill",
                    text: "Microphone access needed",
                    action: { settingsManager.requestMicrophonePermission() }
                )
            }

            if settingsManager.recordSystemAudio && settingsManager.screenRecordingPermission != .granted {
                permissionRow(
                    icon: "rectangle.dashed.badge.record",
                    text: "Screen Recording needed",
                    action: { settingsManager.openSystemSettingsScreenRecording() }
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    private func permissionRow(icon: String, text: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .font(.caption)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button("Grant") {
                action()
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button(action: openRecordingsFolder) {
                Label("Recordings", systemImage: "folder")
            }
            .buttonStyle(.plain)
            .font(.caption)

            Spacer()

            Button(action: openSettings) {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.plain)
            .font(.caption)

            Spacer()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding()
    }

    private func openFirefliesNotebooks() {
        if let url = URL(string: "https://app.fireflies.ai/notebooks") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openSettings() {
        // Use proper SwiftUI environment action
        openSettingsAction()

        // Bring app to front and position window near mouse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)

            // Find and position the settings window
            if let settingsWindow = NSApp.windows.first(where: { $0.title.contains("Settings") || $0.identifier?.rawValue.contains("settings") == true }) {
                let mouseLocation = NSEvent.mouseLocation
                // Position window so it's near the mouse but fully visible
                if let screen = NSScreen.main {
                    let windowSize = settingsWindow.frame.size
                    var newOrigin = NSPoint(
                        x: mouseLocation.x - windowSize.width / 2,
                        y: mouseLocation.y - windowSize.height - 20
                    )
                    // Keep window on screen
                    let screenFrame = screen.visibleFrame
                    newOrigin.x = max(screenFrame.minX, min(newOrigin.x, screenFrame.maxX - windowSize.width))
                    newOrigin.y = max(screenFrame.minY, min(newOrigin.y, screenFrame.maxY - windowSize.height))
                    settingsWindow.setFrameOrigin(newOrigin)
                }
                settingsWindow.makeKeyAndOrderFront(nil)
            }
        }
    }

    // MARK: - Actions

    private func toggleRecording() {
        // Ignore if we're processing or uploading
        guard canRecord else { return }

        Task {
            if isActivelyRecording {
                await stopRecording()
            } else {
                await startRecording()
            }
        }
    }

    private func startRecording() async {
        // Re-check permissions before attempting to record
        settingsManager.checkPermissions()

        // Verify we can actually record
        guard settingsManager.canStartRecording else {
            showToast(message: "Missing permissions", style: .error)
            return
        }

        // Validate selected microphone exists (if a specific one is selected)
        if settingsManager.recordMicrophone,
           let selectedMicID = settingsManager.selectedMicrophoneID,
           audioDeviceManager.device(withUID: selectedMicID) == nil {
            // Selected microphone no longer exists
            showToast(message: "Mic not found. Select a different one in menu bar.", style: .error, duration: 5.0)
            errorMessage = "Selected mic not found\nChoose different mic"
            return
        }

        // Clear previous state
        errorMessage = nil
        lastRecordingURL = nil
        currentStatus = .recording

        do {
            audioRecorder.recordMicrophone = settingsManager.recordMicrophone
            audioRecorder.recordSystemAudio = settingsManager.recordSystemAudio

            let url = try await audioRecorder.startRecording(micDeviceUID: settingsManager.selectedMicrophoneID)
            recordingState.startRecording(url: url)

            // Show toast
            showToast(message: "Recording started", style: .recording)
        } catch {
            currentStatus = .idle
            showError(error)
        }
    }

    private func stopRecording() async {
        // Stop the timer immediately - don't wait for post-processing
        let duration = recordingState.duration
        recordingState.stopRecording()

        // Show processing status (post-processing happens in stopRecording)
        currentStatus = .processing
        showToast(message: "Processing audio...", style: .processing, duration: 60)

        do {
            let url = try await audioRecorder.stopRecording()
            lastRecordingURL = url
            currentStatus = .idle

            // Reset mute state
            isMicMuted = false
            audioRecorder.isMicMuted = false

            // Show toast
            showToast(message: "Recording saved", style: .success)

            // Auto-upload if enabled and duration meets minimum
            if settingsManager.autoUpload &&
               settingsManager.hasAPIKey &&
               duration >= settingsManager.minimumUploadDuration {
                await uploadRecording(url: url)
            }
        } catch {
            currentStatus = .idle
            showError(error)
        }
    }

    private func uploadRecording(url: URL) async {
        guard let apiKey = settingsManager.firefliesAPIKey else { return }

        currentStatus = .uploading
        showToast(message: "Uploading to Fireflies...", style: .uploading, duration: 60)

        do {
            let api = FirefliesAPI()
            let title = url.deletingPathExtension().lastPathComponent
            let _ = try await api.uploadAudio(
                fileURL: url,
                title: title,
                apiKey: apiKey,
                language: settingsManager.meetingLanguage
            )

            currentStatus = .idle
            lastRecordingURL = nil
            showToast(message: "Uploaded to Fireflies", style: .success)
        } catch {
            currentStatus = .idle
            showError(error)
        }
    }

    private func setupKeyboardShortcut() {
        KeyboardShortcutManager.shared.setToggleRecordingHandler { [self] in
            // Only handle if we can actually record (not processing/uploading)
            if canRecord {
                toggleRecording()
            }
        }
        KeyboardShortcutManager.shared.setToggleMicMuteHandler { [self] in
            // Only allow muting while actively recording
            if isActivelyRecording {
                toggleMicMute()
            }
        }
    }

    private func openRecordingsFolder() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsDir = documentsURL.appendingPathComponent("Fireflies Recordings", isDirectory: true)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        NSWorkspace.shared.open(recordingsDir)
    }

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        // Also show as toast (only if window is closed)
        showToast(message: error.localizedDescription, style: .error)
    }

    /// Shows a toast - positioned below menu bar when window is open, bottom of screen otherwise
    private func showToast(message: String, style: ToastStyle, duration: TimeInterval = 3.0) {
        ToastWindowController.show(message: message, style: style, duration: duration, belowMenuBar: isWindowOpen)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(RecordingState())
        .environmentObject(SettingsManager())
        .environmentObject(AudioDeviceManager())
}
