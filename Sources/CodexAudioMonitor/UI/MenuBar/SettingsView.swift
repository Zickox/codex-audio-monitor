import SwiftUI

struct SettingsView: View {
    @Bindable var codex: CodexRuntimeController

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingM) {
            Text("Codex Audio Monitor")
                .font(.title3.weight(.semibold))

            Text("macOS 15+ glass fallback and native Liquid Glass on macOS 26+.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
                Text("Codex Integration")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Auth source: local Codex credentials")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Auth status: \(codex.authState.label)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("RPC status: \(codex.appServerState.label)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: DesignTokens.spacingS) {
                    Button("Sync Auth") {
                        Task { await codex.refreshAuth() }
                    }

                    Button("Run Login") {
                        Task { await codex.connectCodex() }
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: DesignTokens.spacingS) {
                    Button("Start RPC") {
                        Task { await codex.startServer() }
                    }
                    .disabled(codex.isBusy || codex.appServerState == .running || codex.appServerState == .starting)

                    Button("Stop RPC") {
                        Task { await codex.stopServer() }
                    }
                    .disabled(codex.isBusy || codex.appServerState == .stopped)
                }

                Text("Comandos en el chat: `mutea todo`, `desmutea <app>`, `volumen 40`, `estado`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let message = codex.lastMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .glassPanel(cornerRadius: DesignTokens.rowCornerRadius)

            Spacer(minLength: 0)
        }
        .onAppear {
            codex.start()
        }
    }
}
