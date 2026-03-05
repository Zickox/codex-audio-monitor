import Foundation

protocol CodexIntegrationService: AnyObject, Sendable {
    func authState() async -> CodexAuthState
    func ensureLogin() async -> CodexAuthState
    func runConnectivityChecks() async -> CodexConnectivityReport
    func generateActionPlan(message: String, context: CodexChatContext) async throws -> CodexActionPlan
}
