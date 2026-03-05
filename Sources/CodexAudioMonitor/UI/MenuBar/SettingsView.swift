import SwiftUI

struct SettingsView: View {
    @Bindable var codex: CodexRuntimeController

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingL) {
            Text("Codex Audio Monitor")
                .font(.title3.weight(.semibold))

            Text("Menubar app for per-app audio monitoring and mute control.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GroupBox("Codex OAuth") {
                VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
                    Text("Auth source: local Codex credentials")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Auth status: \(codex.authState.label)")
                        .font(.subheadline)

                    HStack(spacing: DesignTokens.spacingS) {
                        Button("Sync Auth") {
                            Task { await codex.refreshAuth() }
                        }

                        Button("Login with OAuth") {
                            Task { await codex.connectCodex() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(codex.isBusy)
                    }

                    Text("El tab Chat usa Codex real (`codex exec`) para interpretar y ejecutar acciones sobre la UI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let message = codex.lastMessage {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .onAppear {
            codex.start()
        }
    }
}
