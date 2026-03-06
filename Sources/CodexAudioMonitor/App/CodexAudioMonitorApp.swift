import AppKit
import SwiftUI

#if canImport(CodexAudioCore)
import CodexAudioCore
#endif

@main
struct CodexAudioMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var monitor = AudioProcessMonitor()
    @State private var codexRuntime = CodexRuntimeController(service: CodexCLIIntegrationService())

    var body: some Scene {
        MenuBarExtra {
            AudioMenuView(monitor: monitor, codex: codexRuntime)
        } label: {
            Label {
                if monitor.sessions.isEmpty {
                    Text("Audio")
                } else {
                    Text("\(monitor.sessions.count)")
                }
            } icon: {
                if monitor.sessions.contains(where: { $0.isMuted }) {
                    Image(systemName: "speaker.slash.fill")
                } else if monitor.sessions.isEmpty {
                    Image(systemName: "speaker.slash")
                } else {
                    Image(systemName: "speaker.wave.2.fill")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
