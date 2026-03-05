import SwiftUI

enum GlassStylingStrategy: String {
    case fallback15
    case native26

    static var current: GlassStylingStrategy {
        if #available(macOS 26, *) {
            return .native26
        }
        return .fallback15
    }
}

extension View {
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = DesignTokens.panelCornerRadius) -> some View {
        switch GlassStylingStrategy.current {
        case .fallback15:
            self
                .background(
                    LinearGradient(
                        colors: [.white.opacity(0.08), .white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 7)
        case .native26:
            if #available(macOS 26, *) {
                self
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                self
                    .background(
                        LinearGradient(
                            colors: [.white.opacity(0.08), .white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 7)
            }
        }
    }

    @ViewBuilder
    func glassActionButtonStyle() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}
