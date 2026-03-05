import SwiftUI

struct AudioLevelAnimationView: View {
    let isActive: Bool
    let intensity: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !isActive)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(isActive ? DesignTokens.brand : .secondary.opacity(0.45))
                        .frame(width: 3, height: barHeight(at: index, time: time))
                }
            }
            .frame(width: 24, height: 16, alignment: .bottom)
            .opacity(isActive ? 1 : 0.65)
            .animation(.easeInOut(duration: 0.15), value: isActive)
        }
    }

    private func barHeight(at index: Int, time: TimeInterval) -> CGFloat {
        let base = max(0.2, min(1, intensity))
        if !isActive {
            return 4 + CGFloat(index % 2)
        }

        let phase = time * 8 + Double(index) * 0.9
        let wave = (sin(phase) + 1) / 2
        let minHeight: CGFloat = 4
        let maxHeight: CGFloat = 6 + (10 * base)
        return minHeight + CGFloat(wave) * (maxHeight - minHeight)
    }
}
