import SwiftUI

enum GlassButtonKind {
    case primary
    case secondary
    case utility
}

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

    func glassPrimaryButtonStyle() -> some View {
        buttonStyle(GlassButtonStyle(kind: .primary))
    }

    func glassSecondaryButtonStyle() -> some View {
        buttonStyle(GlassButtonStyle(kind: .secondary))
    }

    func glassUtilityButtonStyle() -> some View {
        buttonStyle(GlassButtonStyle(kind: .utility))
    }

    func subtleGlassChipStyle(color: Color, emphasis: Bool = false) -> some View {
        modifier(GlassChipModifier(color: color, emphasis: emphasis))
    }

    func glassTabCapsule(selected: Bool, tint: Color = DesignTokens.brand) -> some View {
        modifier(GlassTabModifier(selected: selected, tint: tint))
    }
}

private struct GlassButtonStyle: ButtonStyle {
    let kind: GlassButtonKind

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonStyleBody(configuration: configuration, kind: kind)
    }
}

private struct GlassButtonStyleBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: GlassButtonKind
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(.ultraThinMaterial, in: shape)
            .background(backgroundFill, in: shape)
            .overlay(shape.stroke(borderColor, lineWidth: borderWidth))
            .shadow(color: shadowColor, radius: isHovered ? 12 : 8, x: 0, y: isHovered ? 5 : 3)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(isHovered ? 0.02 : 0)
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeInOut(duration: 0.16), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.18), value: isHovered)
            .contentShape(shape)
            .onHover { hovering in
                isHovered = isEnabled && hovering
            }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.buttonCornerRadius, style: .continuous)
    }

    private var horizontalPadding: CGFloat {
        switch kind {
        case .primary:
            return 12
        case .secondary:
            return 11
        case .utility:
            return 10
        }
    }

    private var verticalPadding: CGFloat {
        switch kind {
        case .primary:
            return 7
        case .secondary:
            return 6
        case .utility:
            return 6
        }
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            return .primary.opacity(0.96)
        case .secondary:
            return .primary.opacity(0.92)
        case .utility:
            return .primary.opacity(0.88)
        }
    }

    private var backgroundFill: LinearGradient {
        let opacityBoost = configuration.isPressed ? -0.03 : (isHovered ? 0.03 : 0)
        switch kind {
        case .primary:
            return LinearGradient(
                colors: [
                    DesignTokens.brand.opacity(0.18 + opacityBoost),
                    DesignTokens.brandMuted.opacity(0.12 + opacityBoost)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .secondary:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.08 + opacityBoost),
                    DesignTokens.brand.opacity(0.05 + opacityBoost)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .utility:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.05 + opacityBoost),
                    Color.white.opacity(0.02 + opacityBoost)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return DesignTokens.brand.opacity(isHovered ? 0.55 : 0.34)
        case .secondary:
            return .white.opacity(isHovered ? 0.22 : 0.14)
        case .utility:
            return .white.opacity(isHovered ? 0.18 : 0.1)
        }
    }

    private var borderWidth: CGFloat {
        kind == .primary ? 0.95 : 0.8
    }

    private var shadowColor: Color {
        switch kind {
        case .primary:
            return DesignTokens.brand.opacity(0.12)
        case .secondary:
            return .black.opacity(0.12)
        case .utility:
            return .black.opacity(0.08)
        }
    }
}

private struct GlassChipModifier: ViewModifier {
    let color: Color
    let emphasis: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: emphasis ? 10.5 : 10, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(emphasis ? 0.92 : 0.78))
            .padding(.horizontal, emphasis ? 9 : 10)
            .padding(.vertical, emphasis ? 4 : 3.5)
            .background(
                (emphasis ? color.opacity(0.14) : color.opacity(0.08)),
                in: RoundedRectangle(cornerRadius: DesignTokens.chipCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.chipCornerRadius, style: .continuous)
                    .stroke(color.opacity(emphasis ? 0.26 : 0.16), lineWidth: emphasis ? 0.8 : 0.65)
            )
    }
}

private struct GlassTabModifier: ViewModifier {
    let selected: Bool
    let tint: Color

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .background(
                Capsule()
                    .fill(selected ? tint.opacity(0.16) : Color.white.opacity(0.04))
            )
            .overlay(
                Capsule()
                    .stroke(selected ? tint.opacity(0.4) : .white.opacity(0.08), lineWidth: 0.9)
            )
            .shadow(color: selected ? tint.opacity(0.1) : .clear, radius: 10, x: 0, y: 4)
    }
}
