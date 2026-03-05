import CoreAudio

protocol AudioProcessControlBackend: AnyObject {
    func apply(processObjectID: AudioObjectID, muted: Bool, gain: Float) throws
    func remove(processObjectID: AudioObjectID) throws
    func cleanup()
}
