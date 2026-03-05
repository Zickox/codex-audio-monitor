import CoreAudio
import Foundation

struct AudioOutputVolumeState: Equatable {
    let volume: Float
    let canSetVolume: Bool
    let deviceName: String
}

protocol AudioOutputVolumeControlling {
    func currentState() throws -> AudioOutputVolumeState
    func setVolume(_ value: Float) throws
}

struct CoreAudioOutputVolumeController: AudioOutputVolumeControlling {
    func currentState() throws -> AudioOutputVolumeState {
        let outputDeviceID = try getDefaultOutputDeviceID()
        let deviceName = getDeviceName(for: outputDeviceID) ?? "System Output"
        let elements = volumeElements(for: outputDeviceID)
        guard !elements.isEmpty else {
            throw AudioMonitorError.volumeControlUnavailable
        }

        let volumes = elements.compactMap { getVolume(deviceID: outputDeviceID, element: $0) }
        guard !volumes.isEmpty else {
            throw AudioMonitorError.volumeControlUnavailable
        }

        let canSetVolume = elements.contains { isVolumeSettable(deviceID: outputDeviceID, element: $0) }
        let average = volumes.reduce(0, +) / Float(volumes.count)

        return AudioOutputVolumeState(
            volume: clamp(average),
            canSetVolume: canSetVolume,
            deviceName: deviceName
        )
    }

    func setVolume(_ value: Float) throws {
        let outputDeviceID = try getDefaultOutputDeviceID()
        let clamped = clamp(value)

        let elements = volumeElements(for: outputDeviceID)
        let settableElements = elements.filter { isVolumeSettable(deviceID: outputDeviceID, element: $0) }
        guard !settableElements.isEmpty else {
            throw AudioMonitorError.volumeControlUnavailable
        }

        var firstError: OSStatus?
        for element in settableElements {
            let status = setVolume(deviceID: outputDeviceID, element: element, value: clamped)
            if status != noErr, firstError == nil {
                firstError = status
            }
        }

        if let firstError {
            throw AudioMonitorError.coreAudio(firstError)
        }
    }

    private func getDefaultOutputDeviceID() throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        var deviceID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            systemObjectID,
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else {
            throw AudioMonitorError.coreAudio(status)
        }
        guard deviceID != kAudioObjectUnknown else {
            throw AudioMonitorError.volumeControlUnavailable
        }

        return deviceID
    }

    private func volumeElements(for deviceID: AudioObjectID) -> [AudioObjectPropertyElement] {
        let preferred: [AudioObjectPropertyElement] = [
            kAudioObjectPropertyElementMain,
            1,
            2
        ]

        var seen = Set<AudioObjectPropertyElement>()
        var result: [AudioObjectPropertyElement] = []

        for element in preferred where seen.insert(element).inserted {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            if AudioObjectHasProperty(deviceID, &address) {
                result.append(element)
            }
        }

        return result
    }

    private func getVolume(deviceID: AudioObjectID, element: AudioObjectPropertyElement) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }

        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &volume
        )

        guard status == noErr else {
            return nil
        }
        return clamp(volume)
    }

    private func setVolume(deviceID: AudioObjectID, element: AudioObjectPropertyElement, value: Float) -> OSStatus {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return kAudioHardwareUnknownPropertyError
        }

        var floatValue = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            size,
            &floatValue
        )
    }

    private func isVolumeSettable(deviceID: AudioObjectID, element: AudioObjectPropertyElement) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return false
        }

        var isSettable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        return status == noErr && isSettable.boolValue
    }

    private func getDeviceName(for deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }

        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                pointer
            )
        }

        guard status == noErr, let value else {
            return nil
        }

        return value.takeRetainedValue() as String
    }

    private func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
