import Foundation

@MainActor
protocol AudioMonitoringService: AnyObject {
    var sessions: [AudioSession] { get }
    var errorMessage: String? { get }
    var lastRefresh: Date { get }
    var outputVolume: Float { get }
    var canControlOutputVolume: Bool { get }
    var outputDeviceName: String { get }

    func start()
    func stop()
    func refresh()
    func refreshOutputVolume()
    func toggleMute(sessionID: String)
    func setMuted(sessionID: String, muted: Bool)
    func setAllMuted(_ muted: Bool)
    func setOutputVolume(_ value: Float)
    func stepOutputVolume(by delta: Float)
}
