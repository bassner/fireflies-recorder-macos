//
//  ToastView.swift
//  FirefliesRecorder
//
//  Floating notification overlay
//

import SwiftUI

struct ToastView: View {
    let message: String
    let isRecording: Bool
    let onDismiss: (() -> Void)?

    init(message: String, isRecording: Bool, onDismiss: (() -> Void)? = nil) {
        self.message = message
        self.isRecording = isRecording
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: 12) {
            // Recording indicator
            Circle()
                .fill(isRecording ? Color.red : Color.secondary)
                .frame(width: 12, height: 12)
                .overlay {
                    if isRecording {
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0.5)
                    }
                }

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)

            Spacer()

            if onDismiss != nil {
                Button(action: { onDismiss?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let isRecording: Bool
    let duration: TimeInterval

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    ToastView(message: message, isRecording: isRecording)
                        .padding(.bottom, 80)
                        .padding(.horizontal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                                withAnimation {
                                    isPresented = false
                                }
                            }
                        }
                }
            }
            .animation(.spring(response: 0.3), value: isPresented)
    }
}

extension View {
    func toast(isPresented: Binding<Bool>, message: String, isRecording: Bool, duration: TimeInterval = 3) -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message, isRecording: isRecording, duration: duration))
    }
}

#Preview {
    VStack {
        ToastView(message: "Recording started", isRecording: true, onDismiss: {})
            .frame(width: 280)

        ToastView(message: "Recording stopped", isRecording: false, onDismiss: {})
            .frame(width: 280)
    }
    .padding()
}
