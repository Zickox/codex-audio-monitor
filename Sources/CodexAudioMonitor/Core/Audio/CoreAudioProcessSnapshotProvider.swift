import CoreAudio
import Foundation

struct CoreAudioProcessSnapshotProvider: AudioProcessSnapshotProviding {
    func snapshots() throws -> [AudioProcessSnapshot] {
        let processObjectIDs = try getAudioProcessObjectList()

        return processObjectIDs.compactMap { processObjectID in
            guard let pid = getPIDProperty(
                objectID: processObjectID,
                selector: kAudioProcessPropertyPID
            ) else {
                return nil
            }

            let isRunningOutput = getUInt32Property(
                objectID: processObjectID,
                selector: kAudioProcessPropertyIsRunningOutput
            ) == 1

            let bundleID = getCFStringProperty(
                objectID: processObjectID,
                selector: kAudioProcessPropertyBundleID
            )

            return AudioProcessSnapshot(
                processObjectID: processObjectID,
                pid: pid,
                bundleID: bundleID,
                isRunningOutput: isRunningOutput
            )
        }
    }

    private func getAudioProcessObjectList() throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            systemObjectID,
            &address,
            0,
            nil,
            &size
        )
        guard status == noErr else {
            throw AudioMonitorError.coreAudio(status)
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var processObjectIDs = [AudioObjectID](repeating: 0, count: count)

        status = AudioObjectGetPropertyData(
            systemObjectID,
            &address,
            0,
            nil,
            &size,
            &processObjectIDs
        )
        guard status == noErr else {
            throw AudioMonitorError.coreAudio(status)
        }

        return processObjectIDs
    }

    private func getUInt32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(objectID, &address) else {
            return nil
        }

        var size = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        return status == noErr ? value : nil
    }

    private func getPIDProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(objectID, &address) else {
            return nil
        }

        var size = UInt32(MemoryLayout<pid_t>.size)
        var value: pid_t = 0
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        return status == noErr ? value : nil
    }

    private func getCFStringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(objectID, &address) else {
            return nil
        }

        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                objectID,
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
}
