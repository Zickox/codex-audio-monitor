import Foundation

@objc protocol CodexAudioGainServiceProtocol {
    func health(withReply reply: @escaping (Bool, String) -> Void)
    func requestPermission(processObjectID: UInt32, withReply reply: @escaping (Int32, Int32, String?) -> Void)
    func apply(processObjectID: UInt32, gain: Float, withReply reply: @escaping (Int32, Int32, String?) -> Void)
    func remove(processObjectID: UInt32, withReply reply: @escaping (Int32, Int32, String?) -> Void)
    func cleanup(withReply reply: @escaping (Int32, Int32, String?) -> Void)
}

enum CodexAudioGainServiceResultCode {
    static let success: Int32 = 0
    static let permissionRequired: Int32 = 1
    static let appGainUnavailable: Int32 = 2
    static let unsupportedOS: Int32 = 3
    static let coreAudio: Int32 = 4
    static let transport: Int32 = 5
    static let unknown: Int32 = 6
}
