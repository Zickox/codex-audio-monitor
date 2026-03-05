import Foundation

struct CodexConnectivityReport: Equatable, Sendable {
    let binaryFound: Bool
    let authState: CodexAuthState
    let pingOK: Bool
    let structuredProbeOK: Bool
    let roundTripMs: Int?
    let assistantPreview: String?
    let errorMessage: String?
    let checkedAt: Date

    var isConnected: Bool {
        binaryFound && pingOK && structuredProbeOK
    }
}
