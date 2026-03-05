import AppKit
import SwiftUI

#if canImport(CodexAudioCore)
import CodexAudioCore
#endif

struct AudioMenuView: View {
    @Bindable var monitor: AudioProcessMonitor
    @Bindable var codex: CodexRuntimeController
    @State private var expandedSessionID: String?
    @State private var selectedFilter: SessionFilter = .all
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
            monitor.start()
            monitor.refresh()
            codex.start()
        }
        .onChange(of: selectedFilter) {
            collapseExpandedIfFilteredOut()
        }
        .onChange(of: monitor.sessions.map(\.id)) {
            collapseExpandedIfFilteredOut()
        }
        .animation(.easeInOut(duration: 0.22), value: monitor.sessions.count)
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isAnyMuted ? .orange : DesignTokens.brand)
                .frame(width: 14, height: 14)

            Text("Codex Audio Monitor")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            Text(activeSessionsLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            AudioLevelAnimationView(
                isActive: hasLiveAudio,
                intensity: animationIntensity
            )
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    private var tabSelector: some View {
        HStack(spacing: 6) {
            tabButton(.audio, title: "Audio", icon: "music.note.list")
            tabButton(.chat, title: "Chat", icon: "bubble.left.and.bubble.right")
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            switch selectedTab {
            case .audio:
                audioTabView
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .chat:
                CodexStatusCardView(codex: codex, monitor: monitor)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    private var audioTabView: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
            volumeControlView
            sessionsView
        }
    }

    private var volumeControlView: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Slider(value: outputVolumeBinding, in: 0...1)
                .disabled(!monitor.canControlOutputVolume)

            Text("\(Int(monitor.outputVolume * 100))%")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
    }

    private var sessionsView: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
            HStack(alignment: .firstTextBaseline) {
                Text("Audio Sessions")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(lastRefreshLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            sessionFiltersBar

            if !monitor.sessions.isEmpty {
                HStack {
                    Text("\(filteredSessions.count) visible")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(areAllSessionsMuted ? "Unmute All" : "Mute All") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            monitor.setAllMuted(!areAllSessionsMuted)
                        }
                    }
                    .controlSize(.small)
                    .glassActionButtonStyle()
                }
            }

            if monitor.sessions.isEmpty {
                Text("No active audio sessions right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            } else if filteredSessions.isEmpty {
                Text(filteredEmptyStateLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignTokens.spacingS) {
                        ForEach(filteredSessions) { session in
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
                            } onSetGain: { sessionID, gain in
                                monitor.setSessionGain(sessionID: sessionID, gain: gain)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: sessionsListHeight)
                .scrollIndicators(.automatic)
            }
        }
        .padding(DesignTokens.cardPadding)
        .glassPanel(cornerRadius: DesignTokens.rowCornerRadius)
    }

    private var sessionFiltersBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(SessionFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        HStack(spacing: 6) {
                            if filter != .all {
                                Circle()
                                    .fill(filter.color)
                                    .frame(width: 7, height: 7)
                            }
                            Text(filter.title)
                                .font(.system(size: 11, weight: .medium))
                            Text("\(sessionCount(for: filter))")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(selectedFilter == filter ? filter.color.opacity(0.2) : Color.secondary.opacity(0.16))
                        )
                        .overlay(
                            Capsule()
                                .stroke(selectedFilter == filter ? filter.color.opacity(0.7) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var footerView: some View {
        HStack(spacing: DesignTokens.spacingS) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    monitor.refresh()
                }
                Task { await codex.refreshAuth() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .controlSize(.small)
            .glassActionButtonStyle()

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .controlSize(.small)

            Spacer()

            Button {
                monitor.stop()
                codex.stop()
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "xmark.circle")
            }
            .controlSize(.small)
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
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(selectedTab == tab ? DesignTokens.brand.opacity(0.26) : Color.secondary.opacity(0.14))
                )
                .overlay(
                    Capsule()
                        .stroke(selectedTab == tab ? DesignTokens.brand.opacity(0.55) : Color.clear, lineWidth: 1)
                )
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
        let mutedCount = monitor.sessions.filter(\.isMuted).count
        if mutedCount == 0 {
            return "\(totalCount) live"
        }
        return "\(totalCount) live • \(mutedCount) muted"
    }

    private var lastRefreshLabel: String {
        guard monitor.lastRefresh > .distantPast else {
            return "Never refreshed"
        }
        return "Updated \(monitor.lastRefresh.formatted(date: .omitted, time: .shortened))"
    }

    private var filteredSessions: [AudioSession] {
        switch selectedFilter {
        case .all:
            return monitor.sessions
        case .active:
            return monitor.sessions.filter { !$0.isMuted }
        case .muted:
            return monitor.sessions.filter(\.isMuted)
        }
    }

    private var filteredEmptyStateLabel: String {
        switch selectedFilter {
        case .all:
            return "No active audio sessions right now."
        case .active:
            return "No active (unmuted) sessions right now."
        case .muted:
            return "No muted sessions right now."
        }
    }

    private var areAllSessionsMuted: Bool {
        !monitor.sessions.isEmpty && monitor.sessions.allSatisfy(\.isMuted)
    }

    private var sessionsListHeight: CGFloat {
        let rowEstimate: CGFloat = 72
        let base = max(1, filteredSessions.count)
        let expandedBonus: CGFloat = expandedSessionID == nil ? 0 : 104
        let dynamicHeight = CGFloat(base) * rowEstimate + expandedBonus
        return min(470, max(140, dynamicHeight))
    }

    private var outputVolumeBinding: Binding<Double> {
        Binding(
            get: { Double(monitor.outputVolume) },
            set: { monitor.setOutputVolume(Float($0)) }
        )
    }

    private func sessionCount(for filter: SessionFilter) -> Int {
        switch filter {
        case .all:
            return monitor.sessions.count
        case .active:
            return monitor.sessions.filter { !$0.isMuted }.count
        case .muted:
            return monitor.sessions.filter(\.isMuted).count
        }
    }

    private func collapseExpandedIfFilteredOut() {
        guard let expandedSessionID else { return }
        let stillVisible = filteredSessions.contains { $0.id == expandedSessionID }
        if !stillVisible {
            self.expandedSessionID = nil
        }
    }
}

private enum MenuTab: String, CaseIterable, Identifiable {
    case audio
    case chat

    var id: String { rawValue }
}

private enum SessionFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case muted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .active:
            return "Active"
        case .muted:
            return "Muted"
        }
    }

    var color: Color {
        switch self {
        case .all:
            return .white
        case .active:
            return DesignTokens.brand
        case .muted:
            return .orange
        }
    }
}
