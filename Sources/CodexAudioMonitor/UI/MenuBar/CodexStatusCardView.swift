import SwiftUI

#if canImport(CodexAudioCore)
import CodexAudioCore
#endif

struct CodexStatusCardView: View {
    @Bindable var codex: CodexRuntimeController
    @Bindable var monitor: AudioProcessMonitor

    @State private var commandText = ""
    @State private var chatMessages: [CodexChatMessage] = [
        CodexChatMessage(role: .assistant, text: "Codex está listo.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
            header
            quickActionsRow
            chatPanel

            if let error = codex.lastUserFacingError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .transition(.opacity)
            }
        }
        .onAppear {
            codex.start()
        }
        .padding(DesignTokens.cardPadding)
        .glassPanel(cornerRadius: DesignTokens.rowCornerRadius)
        .animation(.easeInOut(duration: 0.18), value: codex.isBusy)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                Text(codex.authState.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusChipView(
                text: codex.connectionStatusLabel,
                color: statusColor,
                appearance: codex.connectionStatusLabel == "Connected" ? .subtle : .emphasis
            )

            Button(codex.isCheckingConnection ? "Checking..." : "Check") {
                Task { await codex.checkConnectivity() }
            }
            .font(.caption.weight(.semibold))
            .glassSecondaryButtonStyle()
            .disabled(codex.isCheckingConnection || codex.isBusy)

            if !isCodexConnected {
                Button("Login") {
                    Task { await codex.connectCodex() }
                }
                .font(.caption.weight(.semibold))
                .glassUtilityButtonStyle()
                .disabled(codex.isBusy)
            }
        }
    }

    private var quickActionsRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(codex.recommendedQuickActions(for: monitor)) { action in
                    Button {
                        runQuickAction(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .font(.caption2.weight(.semibold))
                    }
                    .glassSecondaryButtonStyle()
                    .disabled(codex.isBusy)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var chatPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(chatMessages.suffix(10))) { message in
                        chatBubble(message)
                    }

                    if codex.isBusy {
                        thinkingBubble
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 110, maxHeight: chatPanelHeight)

            HStack(spacing: 6) {
                TextField("Escribe un comando...", text: $commandText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(codex.isBusy)
                    .onSubmit {
                        submitCommand()
                    }

                Button(codex.isBusy ? "Thinking..." : "Send") {
                    submitCommand()
                }
                .font(.caption.weight(.semibold))
                .glassPrimaryButtonStyle()
                .disabled(commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || codex.isBusy)
            }
        }
    }

    private var thinkingBubble: some View {
        HStack {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text("Codex está pensando...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Spacer(minLength: 20)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
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

    private var statusColor: Color {
        switch codex.connectionStatusLabel {
        case "Connected", "Ready":
            return .green
        case "Auth required":
            return .orange
        case "Checking", "Not checked":
            return .secondary
        default:
            return .red
        }
    }

    private var isCodexConnected: Bool {
        switch codex.connectionStatusLabel {
        case "Connected", "Ready":
            return true
        default:
            return false
        }
    }

    private var chatPanelHeight: CGFloat {
        let dynamic = CGFloat(max(4, chatMessages.count)) * 32
        return min(240, max(130, dynamic))
    }

    private func submitCommand() {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        chatMessages.append(CodexChatMessage(role: .user, text: trimmed))
        commandText = ""

        Task {
            let response = await codex.handleChatCommand(trimmed, monitor: monitor)
            await MainActor.run {
                chatMessages.append(CodexChatMessage(role: .assistant, text: response))
            }
        }
    }

    private func runQuickAction(_ action: CodexQuickAction) {
        chatMessages.append(CodexChatMessage(role: .user, text: action.title))

        Task {
            let response = await codex.runQuickAction(action, monitor: monitor)
            await MainActor.run {
                chatMessages.append(CodexChatMessage(role: .assistant, text: response))
            }
        }
    }
}

private struct CodexChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
}
