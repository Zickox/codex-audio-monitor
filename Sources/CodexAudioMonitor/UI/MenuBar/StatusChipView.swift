import SwiftUI

struct StatusChipView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                color.opacity(0.2),
                in: RoundedRectangle(cornerRadius: DesignTokens.chipCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.chipCornerRadius, style: .continuous)
                    .stroke(color.opacity(0.5), lineWidth: 0.8)
            )
    }
}
