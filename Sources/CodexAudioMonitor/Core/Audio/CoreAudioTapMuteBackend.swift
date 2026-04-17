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

enum TapPCMScalarFormat: Equatable {
    case float32
    case float64
    case int16
    case int32

    init?(streamFormat: AudioStreamBasicDescription) {
        guard streamFormat.mFormatID == kAudioFormatLinearPCM else {
            return nil
        }

        let formatFlags = streamFormat.mFormatFlags
        let isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (formatFlags & kAudioFormatFlagIsSignedInteger) != 0

        switch (isFloat, isSignedInteger, streamFormat.mBitsPerChannel) {
        case (true, _, 32):
            self = .float32
        case (true, _, 64):
            self = .float64
        case (false, true, 16):
            self = .int16
        case (false, true, 32):
            self = .int32
        default:
            return nil
        }
    }
}

enum TapPCMScaler {
    static func scaleSamples(
        input: UnsafeRawPointer,
        output: UnsafeMutableRawPointer,
        byteCount: Int,
        gain: Float,
        format: TapPCMScalarFormat
    ) {
        switch format {
        case .float32:
            scaleFloat32(input: input, output: output, byteCount: byteCount, gain: gain)
        case .float64:
            scaleFloat64(input: input, output: output, byteCount: byteCount, gain: gain)
        case .int16:
            scaleInt16(input: input, output: output, byteCount: byteCount, gain: gain)
        case .int32:
            scaleInt32(input: input, output: output, byteCount: byteCount, gain: gain)
        }
    }

    private static func scaleFloat32(
        input: UnsafeRawPointer,
        output: UnsafeMutableRawPointer,
        byteCount: Int,
        gain: Float
    ) {
        let sampleCount = byteCount / MemoryLayout<Float32>.stride
        let inputSamples = input.bindMemory(to: Float32.self, capacity: sampleCount)
        let outputSamples = output.bindMemory(to: Float32.self, capacity: sampleCount)

        for sampleIndex in 0..<sampleCount {
            outputSamples[sampleIndex] = inputSamples[sampleIndex] * gain
        }
    }

    private static func scaleFloat64(
        input: UnsafeRawPointer,
        output: UnsafeMutableRawPointer,
        byteCount: Int,
        gain: Float
    ) {
        let sampleCount = byteCount / MemoryLayout<Float64>.stride
        let inputSamples = input.bindMemory(to: Float64.self, capacity: sampleCount)
        let outputSamples = output.bindMemory(to: Float64.self, capacity: sampleCount)
        let multiplier = Double(gain)

        for sampleIndex in 0..<sampleCount {
            outputSamples[sampleIndex] = inputSamples[sampleIndex] * multiplier
        }
    }

    private static func scaleInt16(
        input: UnsafeRawPointer,
        output: UnsafeMutableRawPointer,
        byteCount: Int,
        gain: Float
    ) {
        let sampleCount = byteCount / MemoryLayout<Int16>.stride
        let inputSamples = input.bindMemory(to: Int16.self, capacity: sampleCount)
        let outputSamples = output.bindMemory(to: Int16.self, capacity: sampleCount)

        for sampleIndex in 0..<sampleCount {
            let scaled = Int((Float(inputSamples[sampleIndex]) * gain).rounded())
            outputSamples[sampleIndex] = Int16(clamping: scaled)
        }
    }

    private static func scaleInt32(
        input: UnsafeRawPointer,
        output: UnsafeMutableRawPointer,
        byteCount: Int,
        gain: Float
    ) {
        let sampleCount = byteCount / MemoryLayout<Int32>.stride
        let inputSamples = input.bindMemory(to: Int32.self, capacity: sampleCount)
        let outputSamples = output.bindMemory(to: Int32.self, capacity: sampleCount)

        for sampleIndex in 0..<sampleCount {
            let scaled = Int64((Double(inputSamples[sampleIndex]) * Double(gain)).rounded())
            outputSamples[sampleIndex] = Int32(clamping: scaled)
        }
    }
}
