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
        switch monitor.audioCaptureAccessState {
        case .unknown:
            return monitor.isPerAppGainEnabled ? "Pending" : "Not enabled"
        case .granted:
            return monitor.perAppControlsState == .active ? "Active" : "Ready"
        case .denied:
            return "Permission denied"
        }
    }

    private var perAppControlsStatusColor: Color {
        switch monitor.audioCaptureAccessState {
        case .unknown:
            return .secondary
        case .granted:
            return .green
        case .denied:
            return .orange
        }
    }

    private var perAppControlsStatusMessage: String {
        switch monitor.audioCaptureAccessState {
        case .unknown:
            if monitor.isPerAppGainEnabled {
                return "Waiting for permission. Start audio in another app and try again."
            }
            return "Enable App Gain to control per-app volume from this tab."
        case .granted:
            if monitor.perAppControlsState == .active {
                return "Per-app controls are active for this session."
            }
            return "Permission granted. Activate controls to apply saved gains."
        case .denied:
            return "Permission was denied. Open System Settings and retry."
        }
    }

    private var showGainEditor: Bool {
        monitor.isPerAppGainEnabled && monitor.perAppControlsState == .active
    }

    private var canRetryPermission: Bool {
        monitor.audioCaptureAccessState != .denied && !monitor.sessions.isEmpty
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
            subtitle: "Optional per-app volume control. Mute/Unmute in Audio tab remains independent."
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
                HStack(spacing: 8) {
                    StatusChipView(
                        text: perAppControlsStatusTitle,
                        color: perAppControlsStatusColor,
                        appearance: monitor.audioCaptureAccessState == .granted ? .emphasis : .subtle
                    )

                    Text(perAppControlsStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Enable App Gain", isOn: perAppGainBinding)
                    .font(.subheadline.weight(.medium))
                    .disabled(monitor.audioCaptureAccessState == .denied)

                if monitor.audioCaptureAccessState == .denied {
                    HStack(spacing: 8) {
                        Button("Open System Settings") {
                            openSystemSettings()
                        }
                        .font(.caption.weight(.semibold))
                        .glassSecondaryButtonStyle()

                        Button("Retry Permission") {
                            monitor.clearDeniedAppGainState()
                            monitor.setPerAppGainEnabled(true)
                        }
                        .font(.caption.weight(.semibold))
                        .glassPrimaryButtonStyle()
                    }
                } else if monitor.isPerAppGainEnabled && monitor.perAppControlsState != .active {
                    Button("Request Permission") {
                        monitor.requestPerAppControlsActivation()
                    }
                    .font(.caption.weight(.semibold))
                    .glassPrimaryButtonStyle()
                    .disabled(!canRetryPermission)
                }

                if showGainEditor {
                    gainEditor
                } else if monitor.isPerAppGainEnabled {
                    Text("Saved values are not applied until per-app controls are active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var gainEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if monitor.sessions.isEmpty {
                Text("Start audio in another app first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(monitor.sessions) { session in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(session.displayName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(Int(session.appGain * 100))%")
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { gainForSession(session.id) },
                                    set: { monitor.setSessionGain(sessionID: session.id, gain: $0) }
                                ),
                                in: 0...1
                            )
                            .disabled(!session.isAppGainAvailable)

                            Button("Reset") {
                                monitor.setSessionGain(sessionID: session.id, gain: 1)
                            }
                            .font(.caption2.weight(.semibold))
                            .glassUtilityButtonStyle()
                            .disabled(!session.isAppGainAvailable)
                        }

                        if !session.isAppGainAvailable {
                            Text("Gain unavailable for this session/output format.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
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

    private func gainForSession(_ sessionID: String) -> Float {
        if let gain = monitor.sessions.first(where: { $0.id == sessionID })?.appGain {
            return gain
        }
        return 1
    }

    private func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        for rawURL in urls {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
