//
//  ToastManager.swift
//  FirefliesRecorder
//
//  Manages floating toast notifications
//

import Foundation
import AppKit
import SwiftUI

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

    private static let toastSize = NSSize(width: 280, height: 70)

    /// Reposition the current toast when window state changes
    static func reposition(belowMenuBar: Bool) {
        guard let controller = shared, let window = controller.window else { return }
        currentBelowMenuBar = belowMenuBar

        if belowMenuBar, let menuWindow = findMenuBarWindow() {
            let origin = NSPoint(
                x: menuWindow.frame.minX,
                y: menuWindow.frame.minY - toastSize.height - 8
            )
            window.setFrame(NSRect(origin: origin, size: toastSize), display: true)
        } else if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let origin = NSPoint(
                x: screenFrame.midX - toastSize.width / 2,
                y: screenFrame.minY + 80
            )
            window.setFrame(NSRect(origin: origin, size: toastSize), display: true)
        }
    }

    /// Find the menu bar popover window for positioning
    private static func findMenuBarWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.title.isEmpty &&
            window.frame.width >= 250 && window.frame.width <= 350 &&
            window.frame.height >= 200
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

            if belowMenuBar, let menuWindow = findMenuBarWindow() {
                // Position below menu bar window
                let origin = NSPoint(
                    x: menuWindow.frame.minX,
                    y: menuWindow.frame.minY - toastSize.height - 8
                )
                window.setFrame(NSRect(origin: origin, size: toastSize), display: true)
            } else if let screen = NSScreen.main {
                // Position at bottom center of main screen
                let screenFrame = screen.visibleFrame
                let origin = NSPoint(
                    x: screenFrame.midX - toastSize.width / 2,
                    y: screenFrame.minY + 80
                )
                window.setFrame(NSRect(origin: origin, size: toastSize), display: true)
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

// MARK: - Toast Content View

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
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: .infinity)
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
