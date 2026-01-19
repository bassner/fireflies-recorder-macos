//
//  AudioLevelMeter.swift
//  FirefliesRecorder
//
//  Horizontal audio level visualization
//

import SwiftUI

struct AudioLevelMeter: View {
    let level: Float
    let label: String
    var color: Color = .green

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))

                    // Level indicator
                    RoundedRectangle(cornerRadius: 3)
                        .fill(levelGradient)
                        .frame(width: max(0, geometry.size.width * CGFloat(level)))
                        .animation(.easeOut(duration: 0.1), value: level)
                }
            }
            .frame(height: 8)
        }
    }

    private var levelGradient: LinearGradient {
        LinearGradient(
            colors: [color, color.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct DualAudioLevelMeter: View {
    let micLevel: Float
    let systemLevel: Float

    var body: some View {
        VStack(spacing: 8) {
            AudioLevelMeter(level: micLevel, label: "Microphone", color: .blue)
            AudioLevelMeter(level: systemLevel, label: "System Audio", color: .orange)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        AudioLevelMeter(level: 0.3, label: "Microphone", color: .blue)
        AudioLevelMeter(level: 0.7, label: "System Audio", color: .orange)
        DualAudioLevelMeter(micLevel: 0.5, systemLevel: 0.3)
    }
    .padding()
    .frame(width: 280)
}
