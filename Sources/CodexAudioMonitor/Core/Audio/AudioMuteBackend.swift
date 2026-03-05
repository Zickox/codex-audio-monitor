import CoreAudio

protocol AudioMuteBackend: AnyObject {
    func mute(processObjectID: AudioObjectID) throws
    func unmute(processObjectID: AudioObjectID) throws
    func cleanup()
}
