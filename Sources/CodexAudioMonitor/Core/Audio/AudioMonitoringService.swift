import Foundation

public enum AudioCaptureAccessState: Equatable {
    case unknown
    case granted
    case denied
}

public enum PerAppControlsState: Equatable {
    case inactive
    case active
}

@MainActor
protocol AudioMonitoringService: AnyObject {
    var sessions: [AudioSession] { get }
    var errorMessage: String? { get }
    var lastRefresh: Date { get }
    var outputVolume: Float { get }
    var canControlOutputVolume: Bool { get }
    var outputDeviceName: String { get }
    var isPerAppGainEnabled: Bool { get }
    var audioCaptureAccessState: AudioCaptureAccessState { get }
    var perAppControlsState: PerAppControlsState { get }

    func start()
    func stop()
    func refresh()
    func refreshOutputVolume()
    func toggleMute(sessionID: String)
    func setMuted(sessionID: String, muted: Bool)
    func setAllMuted(_ muted: Bool)
    func solo(sessionID: String)
    func muteOthers(except sessionID: String)
    func setSessionGain(sessionID: String, gain: Float)
    func setAllSessionGains(_ gain: Float)
    func restoreAllSessionGains()
    func setPerAppGainEnabled(_ enabled: Bool)
    func requestPerAppControlsActivation()
    func deactivatePerAppControls()
    func setOutputVolume(_ value: Float)
    func stepOutputVolume(by delta: Float)
}
