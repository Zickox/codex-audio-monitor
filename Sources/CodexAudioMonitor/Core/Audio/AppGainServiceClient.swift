import CoreAudio
import Foundation

final class AppGainServiceClient: AudioProcessControlBackend {
    private let serviceName: String
    private var connection: NSXPCConnection?

    init(serviceName: String = "com.zickox.codexaudiomonitor.gainservice") {
        self.serviceName = serviceName
    }

    func apply(processObjectID: AudioObjectID, muted: Bool, gain: Float) throws {
        // App Gain path never mutes in this architecture; mute is handled by CoreAudioTapMuteBackend.
        _ = muted
        let response = try invoke { proxy, reply in
            proxy.apply(
                processObjectID: processObjectID,
                gain: gain,
                withReply: reply
            )
        }
        try mapResponse(response)
    }

    func requestAudioCaptureAccess(processObjectID: AudioObjectID) throws {
        let response = try invoke { proxy, reply in
            proxy.requestPermission(processObjectID: processObjectID, withReply: reply)
        }
        try mapResponse(response)
    }

    func remove(processObjectID: AudioObjectID) throws {
        let response = try invoke { proxy, reply in
            proxy.remove(processObjectID: processObjectID, withReply: reply)
        }
        try mapResponse(response)
    }

    func cleanup() {
        _ = try? invoke { proxy, reply in
            proxy.cleanup(withReply: reply)
        }
        invalidateConnection()
    }

    private typealias Response = (resultCode: Int32, coreAudioStatus: Int32, message: String?)

    private func invoke(
        _ call: (
            _ proxy: CodexAudioGainServiceProtocol,
            _ reply: @escaping (Int32, Int32, String?) -> Void
        ) -> Void
    ) throws -> Response {
        let connection = ensureConnection()

        var transportError: Error?
        guard let proxy = connection.synchronousRemoteObjectProxyWithErrorHandler({ error in
            transportError = error
        }) as? CodexAudioGainServiceProtocol else {
            throw AudioMonitorError.appGainUnavailable
        }

        var response: Response?
        call(proxy) { resultCode, coreAudioStatus, message in
            response = (resultCode, coreAudioStatus, message)
        }

        if let transportError {
            invalidateConnection()
            throw transportError
        }

        guard let response else {
            throw AudioMonitorError.appGainUnavailable
        }

        return response
    }

    private func ensureConnection() -> NSXPCConnection {
        if let connection {
            return connection
        }

        let connection = NSXPCConnection(serviceName: serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: CodexAudioGainServiceProtocol.self)
        connection.interruptionHandler = { [weak self] in
            self?.invalidateConnection()
        }
        connection.invalidationHandler = { [weak self] in
            self?.invalidateConnection()
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func invalidateConnection() {
        connection?.invalidate()
        connection = nil
    }

    private func mapResponse(_ response: Response) throws {
        switch response.resultCode {
        case CodexAudioGainServiceResultCode.success:
            return
        case CodexAudioGainServiceResultCode.permissionRequired:
            throw AudioMonitorError.audioCapturePermissionRequired
        case CodexAudioGainServiceResultCode.appGainUnavailable:
            throw AudioMonitorError.appGainUnavailable
        case CodexAudioGainServiceResultCode.unsupportedOS:
            throw AudioMonitorError.unsupportedOS
        case CodexAudioGainServiceResultCode.coreAudio:
            throw AudioMonitorError.coreAudio(OSStatus(response.coreAudioStatus))
        case CodexAudioGainServiceResultCode.transport:
            throw AudioMonitorError.appGainUnavailable
        default:
            throw AudioMonitorError.coreAudio(OSStatus(response.coreAudioStatus))
        }
    }
}
