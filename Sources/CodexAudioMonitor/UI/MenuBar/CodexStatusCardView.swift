import SwiftUI

#if canImport(CodexAudioCore)
import CodexAudioCore
#endif

struct CodexStatusCardView: View {
    @Bindable var codex: CodexRuntimeController
    @Bindable var monitor: AudioProcessMonitor

    @State private var commandText = ""
    @State private var chatMessages: [CodexChatMessage] = [
        CodexChatMessage(role: .assistant, text: "Codex está listo. Prueba: `mutea todo`, `spotify 30%`, `volumen 35`, `estado`.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
            header
            diagnosticsPanel
            chatPanel

            if let lastMessage = codex.lastMessage {
                Text(lastMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .transition(.opacity)
            }
        }
        .onAppear {
            codex.start()
        }
        .padding(DesignTokens.cardPadding)
        .glassPanel(cornerRadius: DesignTokens.rowCornerRadius)
        .animation(.easeInOut(duration: 0.2), value: codex.connectivityReport?.checkedAt)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Chat")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("Auth: \(codex.authState.label)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Login") {
                Task { await codex.connectCodex() }
            }
            .controlSize(.small)
            .disabled(codex.isBusy)
        }
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: diagnosticsIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(diagnosticsColor)

                Text(diagnosticsTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button(codex.isCheckingConnection ? "Checking..." : "Check connection") {
                    Task { await codex.checkConnectivity() }
                }
                .controlSize(.mini)
                .disabled(codex.isCheckingConnection)
            }

            if let report = codex.connectivityReport {
                HStack(spacing: 10) {
                    Text("Ping: \(report.pingOK ? "OK" : "Fail")")
                    Text("Structured: \(report.structuredProbeOK ? "OK" : "Fail")")
                    if let roundTrip = report.roundTripMs {
                        Text("Latency: \(roundTrip) ms")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if let preview = report.assistantPreview, !preview.isEmpty {
                    Text("Preview: \(preview)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text("Checked: \(report.checkedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Ejecuta una verificación para validar conexión, auth y respuesta de Codex.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(diagnosticsColor.opacity(0.25), lineWidth: 1)
        )
    }

    private var chatPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(chatMessages.suffix(12))) { message in
                        chatBubble(message)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: chatPanelHeight)
            .animation(.easeInOut(duration: 0.2), value: chatMessages.count)

            HStack(spacing: 6) {
                TextField("Escribe un comando...", text: $commandText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submitCommand()
                    }

                Button("Send") {
                    submitCommand()
                }
                .controlSize(.small)
                .disabled(commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || codex.isBusy)
            }

            Text("Codex ejecuta acciones reales sobre la interfaz de audio.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func chatBubble(_ message: CodexChatMessage) -> some View {
        HStack {
            if message.role == .assistant {
                Text(message.text)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer(minLength: 20)
            } else {
                Spacer(minLength: 20)
                Text(message.text)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DesignTokens.brand.opacity(0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var diagnosticsIcon: String {
        guard let report = codex.connectivityReport else {
            return "bolt.horizontal.circle"
        }
        if report.isConnected {
            return "checkmark.seal.fill"
        }
        if case .loggedOut = report.authState {
            return "person.crop.circle.badge.exclamationmark"
        }
        return "exclamationmark.triangle.fill"
    }

    private var diagnosticsColor: Color {
        guard let report = codex.connectivityReport else {
            return .secondary
        }
        if report.isConnected {
            return .green
        }
        if case .loggedOut = report.authState {
            return .orange
        }
        return .red
    }

    private var diagnosticsTitle: String {
        if codex.isCheckingConnection {
            return "Checking"
        }

        guard let report = codex.connectivityReport else {
            return "Not checked"
        }

        if report.isConnected {
            return "Connected"
        }
        if case .loggedOut = report.authState {
            return "Auth required"
        }
        return "Error"
    }

    private var chatPanelHeight: CGFloat {
        let estimatedRowHeight: CGFloat = 34
        let dynamic = CGFloat(max(4, chatMessages.count)) * estimatedRowHeight
        return min(300, max(140, dynamic))
    }

    private func submitCommand() {
        let command = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }

        appendMessage(.user, command)
        commandText = ""

        Task {
            let response = await codex.handleChatCommand(command, monitor: monitor)
            appendMessage(.assistant, response)
        }
    }

    private func appendMessage(_ role: CodexChatMessage.Role, _ text: String) {
        chatMessages.append(CodexChatMessage(role: role, text: text))
        if chatMessages.count > 18 {
            chatMessages.removeFirst(chatMessages.count - 18)
        }
    }
}

private struct CodexChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
}
