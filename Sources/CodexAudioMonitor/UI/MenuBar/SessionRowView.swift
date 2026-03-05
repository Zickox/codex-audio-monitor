import SwiftUI

#if canImport(CodexAudioCore)
import CodexAudioCore
#endif

struct SessionRowView: View {
    let session: AudioSession
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onToggleMute: (String) -> Void
    let onSetGain: (String, Float) -> Void
    @State private var draftGain: Double
    @State private var isEditingGain = false

    init(
        session: AudioSession,
        isExpanded: Bool,
        onToggleExpanded: @escaping () -> Void,
        onToggleMute: @escaping (String) -> Void,
        onSetGain: @escaping (String, Float) -> Void
    ) {
        self.session = session
        self.isExpanded = isExpanded
        self.onToggleExpanded = onToggleExpanded
        self.onToggleMute = onToggleMute
        self.onSetGain = onSetGain
        _draftGain = State(initialValue: Double(session.appGain))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
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

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        StatusChipView(
                            text: session.isMuted ? "Muted" : "Active",
                            color: session.isMuted ? .orange : DesignTokens.brand
                        )
                        Text(pidText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        separatorDot
                        Text(lastSeenRelativeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 6)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        onToggleExpanded()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    onToggleMute(session.id)
                } label: {
                    Label(session.isMuted ? "Unmute" : "Mute", systemImage: session.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .labelStyle(.titleAndIcon)
                }
                .font(.caption.weight(.semibold))
                .controlSize(.small)
                .glassActionButtonStyle()
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
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

                    Text("App Gain")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)

                    if session.isAppGainAvailable {
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Slider(value: appGainBinding, in: 0...1, onEditingChanged: { editing in
                                isEditingGain = editing
                            })

                            Text("\(Int(session.appGain * 100))%")
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)

                            Button("Reset") {
                                onSetGain(session.id, 1)
                            }
                            .controlSize(.mini)
                        }
                    } else {
                        Text("Gain unavailable on current output format.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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
        .onChange(of: session.appGain) {
            guard !isEditingGain else { return }
            draftGain = Double(session.appGain)
        }
    }

    private var pidText: String {
        let label = session.pids.count == 1 ? "pid" : "pids"
        return "\(session.pids.count) \(label)"
    }

    private var lastSeenRelativeText: String {
        let elapsed = max(0, Int(Date().timeIntervalSince(session.lastSeenAt)))
        if elapsed < 60 {
            return "\(elapsed)s ago"
        }
        if elapsed < 3_600 {
            return "\(elapsed / 60)m ago"
        }
        if elapsed < 86_400 {
            return "\(elapsed / 3_600)h ago"
        }
        return "\(elapsed / 86_400)d ago"
    }

    private var separatorDot: some View {
        Text("•")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary.opacity(0.7))
    }

    private var appGainBinding: Binding<Double> {
        Binding(
            get: { draftGain },
            set: {
                draftGain = $0
                onSetGain(session.id, Float($0))
            }
        )
    }
}
