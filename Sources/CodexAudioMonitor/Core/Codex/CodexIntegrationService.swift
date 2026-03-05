import Foundation

protocol CodexIntegrationService: AnyObject, Sendable {
    func authState() async -> CodexAuthState
    func ensureLogin() async -> CodexAuthState
    func startAppServer() async throws
    func stopAppServer() async
    func send(request: String) async throws -> String
    func appServerState() async -> CodexAppServerState
}
