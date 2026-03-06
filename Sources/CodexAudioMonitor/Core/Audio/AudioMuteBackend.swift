import CoreAudio

protocol AudioMuteBackend: AnyObject {
    func mute(processObjectID: AudioObjectID) throws
    func unmute(processObjectID: AudioObjectID) throws
    func cleanup()
}

protocol AudioProcessControlBackend: AnyObject {
    func apply(processObjectID: AudioObjectID, muted: Bool, gain: Float) throws
    func requestAudioCaptureAccess(processObjectID: AudioObjectID) throws
    func remove(processObjectID: AudioObjectID) throws
    func cleanup()
}
