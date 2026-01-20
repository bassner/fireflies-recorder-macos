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
