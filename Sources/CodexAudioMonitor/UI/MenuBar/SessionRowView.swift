import AppKit
import SwiftUI

#if canImport(CodexAudioCore)
import CodexAudioCore
#endif

struct SessionRowView: View {
    let session: AudioSession
    let isExpanded: Bool
    let audioCapturePermissionRequired: Bool
    let onToggleExpanded: () -> Void
    let onToggleMute: (String) -> Void
    let onSolo: (String) -> Void
    let onMuteOthers: (String) -> Void
    let onResetGain: (String) -> Void
    let onSetGain: (String, Float) -> Void
    @State private var draftGain: Double
    @State private var isEditingGain = false
    @State private var gainCommitTask: Task<Void, Never>?

    init(
        session: AudioSession,
        isExpanded: Bool,
        audioCapturePermissionRequired: Bool,
        onToggleExpanded: @escaping () -> Void,
        onToggleMute: @escaping (String) -> Void,
        onSolo: @escaping (String) -> Void,
        onMuteOthers: @escaping (String) -> Void,
        onResetGain: @escaping (String) -> Void,
        onSetGain: @escaping (String, Float) -> Void
    ) {
        self.session = session
        self.isExpanded = isExpanded
        self.audioCapturePermissionRequired = audioCapturePermissionRequired
        self.onToggleExpanded = onToggleExpanded
        self.onToggleMute = onToggleMute
        self.onSolo = onSolo
        self.onMuteOthers = onMuteOthers
        self.onResetGain = onResetGain
        self.onSetGain = onSetGain
        _draftGain = State(initialValue: Double(session.appGain))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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
                        if session.appGain < 0.999, session.isAppGainAvailable {
                            StatusChipView(
                                text: "Gain \(Int(session.appGain * 100))%",
                                color: .white.opacity(0.85)
                            )
                        }
                        if !session.isAppGainAvailable {
                            StatusChipView(
                                text: audioCapturePermissionRequired ? "Permission" : "Gain unavailable",
                                color: audioCapturePermissionRequired ? .orange : .secondary
                            )
                        }
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

                HStack(spacing: 6) {
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

                    HStack(spacing: 6) {
                        quickActionButton(title: "Solo", systemImage: "scope") {
                            onSolo(session.id)
                        }

                        quickActionButton(title: "Mute Others", systemImage: "speaker.slash.circle") {
                            onMuteOthers(session.id)
                        }

                        quickActionButton(title: "Reset Gain", systemImage: "arrow.uturn.backward.circle") {
                            draftGain = 1
                            gainCommitTask?.cancel()
                            onResetGain(session.id)
                        }
                    }

                    Text("App Gain")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)

                    if session.isAppGainAvailable {
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            gainSlider

                            Text("\(displayedGainPercent)%")
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(isEditingGain ? .primary : .secondary)

                            Button("Reset") {
                                draftGain = 1
                                gainCommitTask?.cancel()
                                onResetGain(session.id)
                            }
                            .controlSize(.mini)
                        }
                    } else if audioCapturePermissionRequired {
                        HStack(spacing: 8) {
                            Text("Allow audio capture in System Settings to use App Gain.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Button("Open Settings") {
                                openAudioCaptureSettings()
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
        .animation(isEditingGain ? .none : .easeInOut(duration: 0.18), value: isExpanded)
        .onChange(of: session.appGain) {
            guard !isEditingGain else { return }
            draftGain = Double(session.appGain)
        }
        .onDisappear {
            gainCommitTask?.cancel()
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
                scheduleGainCommit($0)
            }
        )
    }

    private var displayedGainPercent: Int {
        Int((isEditingGain ? draftGain : Double(session.appGain)) * 100)
    }

    private var gainSlider: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Slider(value: appGainBinding, in: 0...1, onEditingChanged: { editing in
                    isEditingGain = editing
                    if !editing {
                        commitGainImmediately()
                    }
                })
                .padding(.vertical, 6)

                if isEditingGain {
                    gainBubble(width: geometry.size.width)
                }
            }
        }
        .frame(height: 30)
    }

    private func gainBubble(width: CGFloat) -> some View {
        let clampedWidth = max(36, width - 18)
        let xOffset = min(
            max(0, CGFloat(draftGain) * clampedWidth),
            clampedWidth
        )

        return Text("\(displayedGainPercent)%")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.white.opacity(0.14), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
            .offset(x: xOffset, y: -20)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .allowsHitTesting(false)
    }

    private func quickActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        }
        .font(.caption2.weight(.semibold))
        .controlSize(.mini)
    }

    private func scheduleGainCommit(_ value: Double) {
        gainCommitTask?.cancel()
        let sessionID = session.id
        gainCommitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            onSetGain(sessionID, Float(value))
        }
    }

    private func commitGainImmediately() {
        gainCommitTask?.cancel()
        onSetGain(session.id, Float(draftGain))
    }

    private func openAudioCaptureSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
