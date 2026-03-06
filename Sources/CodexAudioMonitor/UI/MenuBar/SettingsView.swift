import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var monitor: AudioProcessMonitor
    @Bindable var codex: CodexRuntimeController

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
            advancedAudioCard
            codexCard
        }
        .padding(.vertical, 2)
    }

    private var perAppGainBinding: Binding<Bool> {
        Binding(
            get: { monitor.isPerAppGainEnabled },
            set: { monitor.setPerAppGainEnabled($0) }
        )
    }

    private var perAppControlsStatusTitle: String {
        if monitor.perAppControlsState == .active {
            return "Active"
        }

        switch monitor.audioCaptureAccessState {
        case .denied:
            return "Permission"
        case .granted:
            return "Inactive"
        case .unknown:
            return "Not enabled"
        }
    }

    private var perAppControlsStatusColor: Color {
        switch perAppControlsStatusTitle {
        case "Active":
            return .green
        case "Permission":
            return .orange
        default:
            return .secondary
        }
    }

    private var perAppControlsStatusMessage: String {
        switch (monitor.perAppControlsState, monitor.audioCaptureAccessState) {
        case (.active, _):
            return "App Gain is active for this session."
        case (.inactive, .denied):
            return "App Gain permission was denied. Use System Settings to allow audio capture."
        case (.inactive, .granted):
            return "App Gain is available but inactive in this session."
        case (.inactive, .unknown):
            return "Request permission explicitly to enable App Gain."
        }
    }

    private var perAppControlsButtonTitle: String {
        switch monitor.audioCaptureAccessState {
        case .denied:
            return "Retry Permission"
        case .granted where monitor.perAppControlsState == .active:
            return "App Gain Active"
        default:
            return "Request Permission"
        }
    }

    private var codexStatusColor: Color {
        switch codex.connectionStatusLabel {
        case "Connected":
            return .green
        case "Auth required":
            return .orange
        case "Checking":
            return .secondary
        default:
            return .red
        }
    }

    private var advancedAudioCard: some View {
        settingsCard(
            title: "App Gain",
            subtitle: "Per-app mute works on-demand. App Gain needs explicit activation."
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
                HStack(spacing: 8) {
                    StatusChipView(
                        text: perAppControlsStatusTitle,
                        color: perAppControlsStatusColor
                    )

                    Text(perAppControlsStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    permissionButton
                    systemSettingsButton
                }

                if monitor.sessions.isEmpty {
                    Text("Start audio in another app first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Enable App Gain", isOn: perAppGainBinding)
                    .font(.subheadline.weight(.medium))

                if monitor.isPerAppGainEnabled {
                    Divider()

                    if monitor.perAppControlsState != .active {
                        Text("Saved values are not applied until per-app controls are enabled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if monitor.sessions.isEmpty {
                        Text("No active audio sessions right now.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(monitor.sessions) { session in
                                    advancedGainRow(session)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: advancedGainListHeight)
                        .scrollIndicators(.hidden)
                    }
                }
            }
        }
    }

    private var codexCard: some View {
        settingsCard(
            title: "Codex",
            subtitle: "Auth and runtime status for the Chat tab."
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
                HStack(spacing: 8) {
                    StatusChipView(
                        text: codex.connectionStatusLabel,
                        color: codexStatusColor
                    )

                    Text(codex.authState.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    refreshAuthButton
                    loginButton
                }

                Text("The Chat tab uses real Codex via `codex exec`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let message = codex.lastMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
    }

    private var permissionButton: some View {
        Button(perAppControlsButtonTitle) {
            monitor.requestPerAppControlsActivation()
        }
        .font(.caption.weight(.semibold))
        .glassSecondaryButtonStyle()
        .disabled(monitor.perAppControlsState == .active || monitor.sessions.isEmpty)
    }

    private var systemSettingsButton: some View {
        Button("Open System Settings") {
            openAudioCaptureSettings()
        }
        .font(.caption.weight(.semibold))
        .glassUtilityButtonStyle()
    }

    private var refreshAuthButton: some View {
        Button("Refresh Auth") {
            Task { await codex.refreshAuth() }
        }
        .font(.caption.weight(.semibold))
        .glassSecondaryButtonStyle()
    }

    private var loginButton: some View {
        Button("Login") {
            Task { await codex.connectCodex() }
        }
        .font(.caption.weight(.semibold))
        .glassPrimaryButtonStyle()
        .disabled(codex.isBusy)
    }

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .padding(DesignTokens.cardPadding)
        .glassPanel(cornerRadius: DesignTokens.rowCornerRadius)
    }

    private var advancedGainListHeight: CGFloat {
        let rowHeight: CGFloat = 52
        let contentHeight = CGFloat(max(1, monitor.sessions.count)) * rowHeight
        return min(180, max(64, contentHeight))
    }

    @ViewBuilder
    private func advancedGainRow(_ session: AudioSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(session.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(Int(session.appGain * 100))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { Double(session.appGain) },
                        set: { monitor.setSessionGain(sessionID: session.id, gain: Float($0)) }
                    ),
                    in: 0...1
                )
                .disabled(!session.isAppGainAvailable || monitor.perAppControlsState != .active)

                Button("Reset") {
                    monitor.setSessionGain(sessionID: session.id, gain: 1)
                }
                .font(.caption.weight(.semibold))
                .glassUtilityButtonStyle()
                .disabled(!session.isAppGainAvailable || monitor.perAppControlsState != .active)
            }
        }
        .padding(.vertical, 2)
    }

    private func openAudioCaptureSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
