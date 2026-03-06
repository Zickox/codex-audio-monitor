import SwiftUI

#if canImport(CodexAudioCore)
import CodexAudioCore
#endif

struct SessionRowView: View {
    let session: AudioSession
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onToggleMute: (String) -> Void

    init(
        session: AudioSession,
        isExpanded: Bool,
        onToggleExpanded: @escaping () -> Void,
        onToggleMute: @escaping (String) -> Void
    ) {
        self.session = session
        self.isExpanded = isExpanded
        self.onToggleExpanded = onToggleExpanded
        self.onToggleMute = onToggleMute
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: DesignTokens.spacingS) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [DesignTokens.brand.opacity(0.95), DesignTokens.brandMuted.opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(String(session.displayName.prefix(1)).uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.black.opacity(0.85))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        StatusChipView(
                            text: session.isMuted ? "Muted" : "Active",
                            color: session.isMuted ? .orange : DesignTokens.brandMuted,
                            appearance: session.isMuted ? .emphasis : .subtle
                        )
                    }
                    .padding(.leading, 1)
                }

                Spacer(minLength: 6)

                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            onToggleExpanded()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary.opacity(0.85))

                    Button {
                        onToggleMute(session.id)
                    } label: {
                        Label(session.isMuted ? "Unmute" : "Mute", systemImage: session.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.semibold))
                            .frame(width: DesignTokens.sessionPrimaryButtonWidth)
                    }
                    .glassPrimaryButtonStyle()
                }
                .frame(width: DesignTokens.sessionActionColumnWidth, alignment: .trailing)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if let bundleID = session.bundleID {
                        Text(bundleID)
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.9))
                            .lineLimit(1)
                    }

                    Text("PIDs: \(session.pids.map(String.init).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("Last seen: \(session.lastSeenAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.black.opacity(0.12))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(DesignTokens.cardPadding)
        .glassPanel(cornerRadius: DesignTokens.rowCornerRadius)
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }
}
