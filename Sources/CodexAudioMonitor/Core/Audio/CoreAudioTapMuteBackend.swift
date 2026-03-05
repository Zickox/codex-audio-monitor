import CoreAudio
import Foundation

final class CoreAudioTapMuteBackend: AudioMuteBackend {
    private struct ActiveMuteHandle {
        let tapID: AudioObjectID
        let aggregateDeviceID: AudioObjectID
        let ioProcID: AudioDeviceIOProcID
    }

    private static let tapIOProc: AudioDeviceIOProc = { _, _, _, _, _, _, _ in
        noErr
    }

    private var handlesByProcessObjectID: [AudioObjectID: ActiveMuteHandle] = [:]

    func mute(processObjectID: AudioObjectID) throws {
        guard handlesByProcessObjectID[processObjectID] == nil else {
            return
        }

        guard #available(macOS 14.2, *) else {
            throw AudioMonitorError.unsupportedOS
        }

        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        tapDescription.name = "CodexAudioMonitorMute-\(processObjectID)"
        tapDescription.muteBehavior = .muted
        tapDescription.isPrivate = true

        var tapID: AudioObjectID = 0
        let status = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard status == noErr else {
            throw AudioMonitorError.coreAudio(status)
        }

        do {
            let handle = try makeActiveHandle(processObjectID: processObjectID, tapID: tapID)
            handlesByProcessObjectID[processObjectID] = handle
        } catch {
            _ = AudioHardwareDestroyProcessTap(tapID)
            throw error
        }
    }

    func unmute(processObjectID: AudioObjectID) throws {
        guard let handle = handlesByProcessObjectID.removeValue(forKey: processObjectID) else {
            return
        }

        guard #available(macOS 14.2, *) else {
            throw AudioMonitorError.unsupportedOS
        }

        var firstError: OSStatus?

        let stopStatus = AudioDeviceStop(handle.aggregateDeviceID, handle.ioProcID)
        if stopStatus != noErr && stopStatus != kAudioHardwareNotRunningError {
            firstError = stopStatus
        }

        let destroyIOProcStatus = AudioDeviceDestroyIOProcID(handle.aggregateDeviceID, handle.ioProcID)
        if destroyIOProcStatus != noErr && firstError == nil {
            firstError = destroyIOProcStatus
        }

        let destroyAggregateStatus = AudioHardwareDestroyAggregateDevice(handle.aggregateDeviceID)
        if destroyAggregateStatus != noErr && firstError == nil {
            firstError = destroyAggregateStatus
        }

        let destroyTapStatus = AudioHardwareDestroyProcessTap(handle.tapID)
        if destroyTapStatus != noErr && firstError == nil {
            firstError = destroyTapStatus
        }

        if let firstError {
            throw AudioMonitorError.coreAudio(firstError)
        }
    }

    func cleanup() {
        for processObjectID in Array(handlesByProcessObjectID.keys) {
            try? unmute(processObjectID: processObjectID)
        }
    }

    deinit {
        cleanup()
    }

    private func makeActiveHandle(processObjectID: AudioObjectID, tapID: AudioObjectID) throws -> ActiveMuteHandle {
        let tapUID = try getTapUID(for: tapID)
        let aggregateUID = "com.codexaudiomonitor.mute.\(processObjectID).\(UUID().uuidString)"
        let aggregateName = "CodexAudioMonitorMute-\(processObjectID)"
        let tapList: [[String: Any]] = [
            [
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: true
            ]
        ]

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: aggregateName,
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceTapListKey: tapList,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceIsPrivateKey: true
        ]

        var aggregateDeviceID: AudioObjectID = 0
        var status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID)
        guard status == noErr else {
            throw AudioMonitorError.coreAudio(status)
        }

        var ioProcID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcID(aggregateDeviceID, Self.tapIOProc, nil, &ioProcID)
        guard status == noErr, let ioProcID else {
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            throw AudioMonitorError.coreAudio(status)
        }

        status = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard status == noErr else {
            _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            throw AudioMonitorError.coreAudio(status)
        }

        return ActiveMuteHandle(tapID: tapID, aggregateDeviceID: aggregateDeviceID, ioProcID: ioProcID)
    }

    private func getTapUID(for tapID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                tapID,
                &address,
                0,
                nil,
                &size,
                pointer
            )
        }

        guard status == noErr, let value else {
            throw AudioMonitorError.coreAudio(status)
        }

        return value.takeRetainedValue() as String
    }
}
