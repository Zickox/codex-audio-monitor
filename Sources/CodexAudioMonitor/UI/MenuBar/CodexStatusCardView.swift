import SwiftUI

#if canImport(CodexAudioCore)
import CodexAudioCore
#endif

struct CodexStatusCardView: View {
    @Bindable var codex: CodexRuntimeController
    @Bindable var monitor: AudioProcessMonitor

    @State private var commandText = ""
    @State private var chatMessages: [CodexChatMessage] = [
        CodexChatMessage(role: .assistant, text: "Prueba: `mutea todo los sonidos` o `volumen 40`.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Codex Chat")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                StatusChipView(text: codexStateLabel, color: codexStateColor)
            }

            Text("OAuth/RPC settings are now in Settings.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            chatPanel

            if let lastMessage = codex.lastMessage {
                Text(lastMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(DesignTokens.cardPadding)
        .glassPanel(cornerRadius: DesignTokens.rowCornerRadius)
    }

    private var chatPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(chatMessages.suffix(8))) { message in
                        chatBubble(message)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 210)

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

            Text("Comandos: mutea/desmutea, volumen, refresh, estado.")
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
        if chatMessages.count > 12 {
            chatMessages.removeFirst(chatMessages.count - 12)
        }
    }

    private var codexStateLabel: String {
        codex.appServerState.label
    }

    private var codexStateColor: Color {
        switch codex.appServerState {
        case .stopped:
            return .gray
        case .starting:
            return .blue
        case .running:
            return .green
        case .restarting:
            return .orange
        case .failed:
            return .red
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
