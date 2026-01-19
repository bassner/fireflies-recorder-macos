//
//  KeyboardShortcutManager.swift
//  FirefliesRecorder
//
//  Manages global keyboard shortcuts for recording control
//

import Foundation
import KeyboardShortcuts
import AppKit

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording")
    static let toggleMicMute = Self("toggleMicMute")
}

@MainActor
final class KeyboardShortcutManager: ObservableObject {
    static let shared = KeyboardShortcutManager()

    private var onToggleRecording: (() -> Void)?
    private var onToggleMicMute: (() -> Void)?

    private init() {
        setupDefaultShortcuts()
        setupHandlers()
    }

    private func setupDefaultShortcuts() {
        // Set default shortcut: Cmd+Option+R (avoiding Cmd+Shift+R which is browser force reload)
        if KeyboardShortcuts.getShortcut(for: .toggleRecording) == nil {
            KeyboardShortcuts.setShortcut(.init(.r, modifiers: [.command, .option]), for: .toggleRecording)
        }
        // Set default shortcut: Cmd+Option+M for mute
        if KeyboardShortcuts.getShortcut(for: .toggleMicMute) == nil {
            KeyboardShortcuts.setShortcut(.init(.m, modifiers: [.command, .option]), for: .toggleMicMute)
        }
    }

    private func setupHandlers() {
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            Task { @MainActor [weak self] in
                self?.onToggleRecording?()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleMicMute) { [weak self] in
            Task { @MainActor [weak self] in
                self?.onToggleMicMute?()
            }
        }
    }

    func setToggleRecordingHandler(_ handler: @escaping () -> Void) {
        onToggleRecording = handler
    }

    func setToggleMicMuteHandler(_ handler: @escaping () -> Void) {
        onToggleMicMute = handler
    }
}

// MARK: - Toast Styles

enum ToastStyle {
    case recording      // Red - recording started
    case stopped        // Gray - recording stopped
    case processing     // Blue - processing audio
    case uploading      // Orange - uploading to Fireflies
    case success        // Green - upload complete
    case error          // Red - something went wrong
    case info           // Blue - general info

    var icon: String {
        switch self {
        case .recording: return "record.circle.fill"
        case .stopped: return "stop.circle.fill"
        case .processing: return "waveform"
        case .uploading: return "arrow.up.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .recording: return .red
        case .stopped: return .secondary
        case .processing: return .blue
        case .uploading: return .orange
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        }
    }

    var showPulse: Bool {
        switch self {
        case .recording, .processing, .uploading: return true
        default: return false
        }
    }
}

// MARK: - Toast Window Controller

final class ToastWindowController: NSWindowController {
    private static var shared: ToastWindowController?
    private var dismissTask: Task<Void, Never>?
    private static var currentBelowMenuBar: Bool = false

    /// Legacy method for backward compatibility
    static func show(message: String, isRecording: Bool) {
        show(message: message, style: isRecording ? .recording : .stopped)
    }

    /// Reposition the current toast when window state changes
    static func reposition(belowMenuBar: Bool) {
        guard let controller = shared, let window = controller.window else { return }
        currentBelowMenuBar = belowMenuBar

        if belowMenuBar {
            let menuBarWindow = NSApp.windows.first { $0.title.isEmpty && $0.frame.width == 280 }
            let menuBarWidth: CGFloat = 280

            if let menuWindow = menuBarWindow {
                let windowSize = NSSize(width: menuBarWidth, height: 50)
                let origin = NSPoint(
                    x: menuWindow.frame.minX,
                    y: menuWindow.frame.minY - windowSize.height - 8
                )
                window.setFrame(NSRect(origin: origin, size: windowSize), display: true)
            }
        } else if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = NSSize(width: 300, height: 60)
            let origin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.minY + 80
            )
            window.setFrame(NSRect(origin: origin, size: windowSize), display: true)
        }
    }

    static func show(message: String, style: ToastStyle, duration: TimeInterval = 3.0, belowMenuBar: Bool = false) {
        Task { @MainActor in
            // Dismiss existing toast
            shared?.close()

            let contentView = ToastContentView(message: message, style: style)
            let hostingController = NSHostingController(rootView: contentView)

            let window = NSWindow(contentViewController: hostingController)
            window.styleMask = [.borderless]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.level = .floating
            window.hasShadow = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]

            if belowMenuBar {
                // Position below menu bar window (same width: 280)
                // Find the menu bar window to position below it
                let menuBarWindow = NSApp.windows.first { $0.title.isEmpty && $0.frame.width == 280 }
                let menuBarWidth: CGFloat = 280

                if let menuWindow = menuBarWindow {
                    let windowSize = NSSize(width: menuBarWidth, height: 50)
                    let origin = NSPoint(
                        x: menuWindow.frame.minX,
                        y: menuWindow.frame.minY - windowSize.height - 8
                    )
                    window.setFrame(NSRect(origin: origin, size: windowSize), display: true)
                } else if let screen = NSScreen.main {
                    // Fallback: position at top center
                    let screenFrame = screen.visibleFrame
                    let windowSize = NSSize(width: menuBarWidth, height: 50)
                    let origin = NSPoint(
                        x: screenFrame.midX - windowSize.width / 2,
                        y: screenFrame.maxY - windowSize.height - 80
                    )
                    window.setFrame(NSRect(origin: origin, size: windowSize), display: true)
                }
            } else {
                // Position at bottom center of main screen
                if let screen = NSScreen.main {
                    let screenFrame = screen.visibleFrame
                    let windowSize = NSSize(width: 300, height: 60)
                    let origin = NSPoint(
                        x: screenFrame.midX - windowSize.width / 2,
                        y: screenFrame.minY + 80
                    )
                    window.setFrame(NSRect(origin: origin, size: windowSize), display: true)
                }
            }

            let controller = ToastWindowController(window: window)
            controller.showWindow(nil)
            shared = controller

            // Auto-dismiss after duration
            controller.dismissTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                await MainActor.run {
                    controller.close()
                    if shared === controller {
                        shared = nil
                    }
                }
            }
        }
    }

    override func close() {
        dismissTask?.cancel()
        super.close()
    }
}

import SwiftUI

private struct ToastContentView: View {
    let message: String
    let style: ToastStyle

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                // Pulse effect for ongoing operations
                if style.showPulse {
                    Circle()
                        .fill(style.color.opacity(0.3))
                        .frame(width: 24, height: 24)
                        .scaleEffect(isPulsing ? 1.3 : 1.0)
                        .opacity(isPulsing ? 0 : 0.5)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false), value: isPulsing)
                }

                Image(systemName: style.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(style.color)
            }
            .frame(width: 28, height: 28)

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style.color.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            if style.showPulse {
                isPulsing = true
            }
        }
    }
}
