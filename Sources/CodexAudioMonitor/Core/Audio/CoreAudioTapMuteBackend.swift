import CoreAudio
import Foundation

final class CoreAudioTapMuteBackend: AudioMuteBackend {
    private var mutedPIDByProcessObjectID: [AudioObjectID: pid_t] = [:]

    func mute(processObjectID: AudioObjectID) throws {
        if mutedPIDByProcessObjectID[processObjectID] != nil {
            return
        }

        let pid = try resolvePID(for: processObjectID)
        try setAudible(false, pid: pid)
        mutedPIDByProcessObjectID[processObjectID] = pid
    }

    func unmute(processObjectID: AudioObjectID) throws {
        guard let pid = mutedPIDByProcessObjectID.removeValue(forKey: processObjectID) else {
            return
        }

        try setAudible(true, pid: pid)
    }

    func cleanup() {
        for processObjectID in Array(mutedPIDByProcessObjectID.keys) {
            try? unmute(processObjectID: processObjectID)
        }
    }

    deinit {
        cleanup()
    }

    private func resolvePID(for processObjectID: AudioObjectID) throws -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(
            processObjectID,
            &address,
            0,
            nil,
            &size,
            &pid
        )
        guard status == noErr else {
            throw AudioMonitorError.coreAudio(status)
        }
        return pid
    }

    private func setAudible(_ isAudible: Bool, pid: pid_t) throws {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessIsAudible,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pidQualifier = pid
        var value: UInt32 = isAudible ? 1 : 0
        let status = withUnsafePointer(to: &pidQualifier) { qualifier in
            AudioObjectSetPropertyData(
                systemObjectID,
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                qualifier,
                UInt32(MemoryLayout<UInt32>.size),
                &value
            )
        }
        guard status == noErr else {
            throw AudioMonitorError.coreAudio(status)
        }
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
