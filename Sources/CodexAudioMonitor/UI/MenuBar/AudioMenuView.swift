import AppKit
import SwiftUI

#if canImport(CodexAudioCore)
import CodexAudioCore
#endif

struct AudioMenuView: View {
    @Bindable var monitor: AudioProcessMonitor
    @Bindable var codex: CodexRuntimeController
    @State private var expandedSessionID: String?
    @State private var selectedTab: MenuTab = .audio

    var body: some View {
        Group {
            if #available(macOS 26, *) {
                GlassEffectContainer(spacing: DesignTokens.spacingM) {
                    menuContent
                }
            } else {
                menuContent
            }
        }
        .padding(.horizontal, DesignTokens.spacingL)
        .padding(.vertical, DesignTokens.spacingM)
        .frame(width: DesignTokens.menuWidth)
        .background(menuBackground)
        .onAppear {
            selectedTab = .audio
            monitor.start()
            monitor.refresh()
            codex.start()
        }
        .onChange(of: monitor.sessions.map(\.id)) {
            collapseExpandedIfFilteredOut()
        }
        .animation(.easeInOut(duration: 0.22), value: monitor.sessions.count)
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
            headerView
            tabSelector
            tabContent
            footerView

            if let errorMessage = monitor.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: DesignTokens.spacingS) {
            Image(systemName: hasLiveAudio ? "waveform" : "speaker.slash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isAnyMuted ? .orange : DesignTokens.brand)
                .frame(width: 14, height: 14)

            Text("Codex Audio Monitor")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            Text(activeSessionsLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .monospacedDigit()

            AudioLevelAnimationView(
                isActive: hasLiveAudio,
                intensity: animationIntensity
            )
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
    }

    private var tabSelector: some View {
        HStack(spacing: 4) {
            tabButton(.audio, title: "Audio", icon: "music.note.list")
            tabButton(.chat, title: "Chat", icon: "bubble.left.and.bubble.right")
            tabButton(.settings, title: "Settings", icon: "gearshape")
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .audio:
            audioTabView
        case .chat:
            CodexStatusCardView(codex: codex, monitor: monitor)
        case .settings:
            ScrollView {
                SettingsView(monitor: monitor, codex: codex)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(height: settingsTabHeight, alignment: .top)
            .scrollIndicators(.hidden)
        }
    }

    private var audioTabView: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
            volumeControlView
            sessionsView
        }
    }

    private var volumeControlView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "speaker.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Slider(value: outputVolumeBinding, in: 0...1)
                    .disabled(!monitor.canControlOutputVolume)
                    .padding(.vertical, 5)

                Text("\(Int(monitor.outputVolume * 100))%")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text(monitor.outputDeviceName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 2)
    }

    private var sessionsView: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
            HStack(alignment: .center, spacing: DesignTokens.spacingS) {
                Text("Sessions")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                if !monitor.sessions.isEmpty {
                    Button(areAllSessionsMuted ? "Unmute All" : "Mute All") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            monitor.setAllMuted(!areAllSessionsMuted)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .glassSecondaryButtonStyle()
                }
            }
            .padding(.bottom, 2)

            if monitor.sessions.isEmpty {
                Text("No active audio right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignTokens.spacingS) {
                        ForEach(monitor.sessions) { session in
                            SessionRowView(
                                session: session,
                                isExpanded: expandedSessionID == session.id,
                                onToggleExpanded: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedSessionID = expandedSessionID == session.id ? nil : session.id
                                    }
                                }
                            ) { sessionID in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    monitor.toggleMute(sessionID: sessionID)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: sessionsListHeight)
                .scrollIndicators(.automatic)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, DesignTokens.cardPadding)
        .padding(.bottom, DesignTokens.cardPadding)
        .glassPanel(cornerRadius: DesignTokens.rowCornerRadius)
    }

    private var footerView: some View {
        HStack(spacing: DesignTokens.spacingS) {
            Spacer()

            Button {
                monitor.stop()
                codex.stop()
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "xmark.circle")
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: DesignTokens.utilityButtonMinWidth)
            }
            .glassUtilityButtonStyle()
        }
        .padding(.horizontal, 4)
    }

    private var menuBackground: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.18), .black.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [DesignTokens.brand.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 8,
                endRadius: 220
            )
            .blendMode(.screen)
        }
    }

    private func tabButton(_ tab: MenuTab, title: String, icon: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .glassTabCapsule(selected: selectedTab == tab)
        }
        .buttonStyle(.plain)
    }

    private var isAnyMuted: Bool {
        monitor.sessions.contains(where: { $0.isMuted })
    }

    private var hasLiveAudio: Bool {
        monitor.sessions.contains(where: { !$0.isMuted })
    }

    private var animationIntensity: CGFloat {
        let sessionFactor = min(1.0, CGFloat(monitor.sessions.count) / 4.0 + 0.25)
        let volumeFactor = max(0.2, CGFloat(monitor.outputVolume))
        return min(1.0, sessionFactor * volumeFactor)
    }

    private var activeSessionsLabel: String {
        let totalCount = monitor.sessions.count
        if totalCount == 1 {
            return "1 live"
        }
        return "\(totalCount) live"
    }

    private var areAllSessionsMuted: Bool {
        !monitor.sessions.isEmpty && monitor.sessions.allSatisfy(\.isMuted)
    }

    private var sessionsListHeight: CGFloat {
        let rowEstimate: CGFloat = 68
        let base = max(1, monitor.sessions.count)
        let expandedBonus: CGFloat = expandedSessionID == nil ? 0 : 52
        let dynamicHeight = CGFloat(base) * rowEstimate + expandedBonus
        return min(420, max(150, dynamicHeight))
    }

    private var settingsTabHeight: CGFloat {
        if monitor.isPerAppGainEnabled {
            return 316
        }
        return 252
    }

    private func collapseExpandedIfFilteredOut() {
        guard let expandedSessionID else { return }
        let stillVisible = monitor.sessions.contains { $0.id == expandedSessionID }
        if !stillVisible {
            self.expandedSessionID = nil
        }
    }

    private var outputVolumeBinding: Binding<Double> {
        Binding(
            get: { Double(monitor.outputVolume) },
            set: { monitor.setOutputVolume(Float($0)) }
        )
    }
}

private enum MenuTab: String, CaseIterable, Identifiable {
    case audio
    case chat
    case settings

    var id: String { rawValue }
}
