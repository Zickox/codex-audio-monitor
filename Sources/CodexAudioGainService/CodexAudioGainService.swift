import CoreAudio
import Foundation
import OSLog

final class CodexAudioGainService: NSObject, CodexAudioGainServiceProtocol {
    private let backend = CoreAudioTapProcessControlBackend()
    private let logger = Logger(subsystem: "com.zickox.codexaudiomonitor", category: "AppGainService")

    func health(withReply reply: @escaping (Bool, String) -> Void) {
        reply(true, "ok")
    }

    func requestPermission(processObjectID: UInt32, withReply reply: @escaping (Int32, Int32, String?) -> Void) {
        logger.notice("requestPermission processObjectID=\(processObjectID, privacy: .public)")
        handle(reply: reply) {
            try backend.requestAudioCaptureAccess(processObjectID: processObjectID)
        }
    }

    func apply(processObjectID: UInt32, gain: Float, withReply reply: @escaping (Int32, Int32, String?) -> Void) {
        logger.debug("apply processObjectID=\(processObjectID, privacy: .public) gain=\(gain, privacy: .public)")
        handle(reply: reply) {
            try backend.apply(processObjectID: processObjectID, gain: gain)
        }
    }

    func remove(processObjectID: UInt32, withReply reply: @escaping (Int32, Int32, String?) -> Void) {
        handle(reply: reply) {
            try backend.remove(processObjectID: processObjectID)
        }
    }

    func cleanup(withReply reply: @escaping (Int32, Int32, String?) -> Void) {
        handle(reply: reply) {
            backend.cleanup()
        }
    }

    private func handle(
        reply: @escaping (Int32, Int32, String?) -> Void,
        _ operation: () throws -> Void
    ) {
        do {
            try operation()
            reply(CodexAudioGainServiceResultCode.success, noErr, nil)
            logger.debug("operation success")
        } catch let error as GainBackendError {
            switch error {
            case .audioCapturePermissionRequired:
                logger.error("operation failed: permission required")
                reply(CodexAudioGainServiceResultCode.permissionRequired, kAudioDevicePermissionsError, nil)
            case .appGainUnavailable:
                logger.error("operation failed: app gain unavailable")
                reply(CodexAudioGainServiceResultCode.appGainUnavailable, noErr, nil)
            case .unsupportedOS:
                logger.error("operation failed: unsupported OS")
                reply(CodexAudioGainServiceResultCode.unsupportedOS, noErr, nil)
            case let .coreAudio(status):
                logger.error("operation failed: core audio status=\(status, privacy: .public)")
                reply(CodexAudioGainServiceResultCode.coreAudio, status, nil)
            }
        } catch {
            logger.error("operation failed: unknown error \(error.localizedDescription, privacy: .public)")
            reply(CodexAudioGainServiceResultCode.unknown, noErr, String(describing: error))
        }
    }
}

enum GainBackendError: Error {
    case unsupportedOS
    case coreAudio(OSStatus)
    case appGainUnavailable
    case audioCapturePermissionRequired
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

final class CoreAudioTapProcessControlBackend {
    private struct ActiveHandle {
        let tapID: AudioObjectID
        let aggregateDeviceID: AudioObjectID
        let ioProcID: AudioDeviceIOProcID
        let contextPointer: UnsafeMutableRawPointer
    }

    private final class IOProcContext {
        var gain: Float
        var sampleFormat: TapPCMScalarFormat?

        init(gain: Float, sampleFormat: TapPCMScalarFormat?) {
            self.gain = gain
            self.sampleFormat = sampleFormat
        }
    }

    private static let tapIOProc: AudioDeviceIOProc = { _, _, inInputData, _, outOutputData, _, inClientData in
        guard let inClientData else {
            return noErr
        }

        let context = Unmanaged<IOProcContext>.fromOpaque(inClientData).takeUnretainedValue()
        let effectiveGain: Float = min(max(context.gain, 0), 1)
        let outputBuffers = UnsafeMutableAudioBufferListPointer(outOutputData)

        guard effectiveGain > 0 else {
            zero(outputBuffers)
            return noErr
        }

        let inputBuffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inInputData)
        )
        let bufferCount = min(inputBuffers.count, outputBuffers.count)

        for index in 0..<bufferCount {
            let inputBuffer = inputBuffers[index]
            let outputBuffer = outputBuffers[index]

            guard let inputData = inputBuffer.mData,
                  let outputData = outputBuffer.mData
            else {
                continue
            }

            let byteCount = Int(min(inputBuffer.mDataByteSize, outputBuffer.mDataByteSize))
            guard byteCount > 0 else {
                continue
            }

            if effectiveGain >= 0.999 {
                memcpy(outputData, inputData, byteCount)
            } else if let sampleFormat = context.sampleFormat {
                TapPCMScaler.scaleSamples(
                    input: UnsafeRawPointer(inputData),
                    output: outputData,
                    byteCount: byteCount,
                    gain: effectiveGain,
                    format: sampleFormat
                )
            } else {
                memset(outputData, 0, byteCount)
            }
        }

        return noErr
    }

    private var handlesByProcessObjectID: [AudioObjectID: ActiveHandle] = [:]
    private var currentOutputDeviceUID: String?

    func apply(processObjectID: AudioObjectID, gain: Float) throws {
        guard #available(macOS 14.2, *) else {
            throw GainBackendError.unsupportedOS
        }

        let clampedGain = clamp(gain)
        let needsTap = clampedGain < 0.999

        if !needsTap {
            try remove(processObjectID: processObjectID)
            return
        }

        try resetHandlesIfOutputDeviceChanged()

        if let handle = handlesByProcessObjectID[processObjectID] {
            let context = Unmanaged<IOProcContext>.fromOpaque(handle.contextPointer).takeUnretainedValue()
            if clampedGain < 0.999, context.sampleFormat == nil {
                context.sampleFormat = try sampleFormat(for: handle.tapID)
            }
            context.gain = clampedGain
            return
        }

        let handle = try makeHandle(processObjectID: processObjectID, gain: clampedGain)
        handlesByProcessObjectID[processObjectID] = handle
    }

    func requestAudioCaptureAccess(processObjectID: AudioObjectID) throws {
        guard #available(macOS 14.2, *) else {
            throw GainBackendError.unsupportedOS
        }

        try ensureAudioCaptureUsageDescriptionPresent()
        if handlesByProcessObjectID[processObjectID] != nil {
            return
        }

        // Force the exact path used by real App Gain (gain < 1), which validates
        // both permission and sample format support in one deterministic probe.
        do {
            try apply(processObjectID: processObjectID, gain: 0.95)
            try remove(processObjectID: processObjectID)
        } catch {
            try? remove(processObjectID: processObjectID)
            throw error
        }
    }

    func remove(processObjectID: AudioObjectID) throws {
        guard let handle = handlesByProcessObjectID.removeValue(forKey: processObjectID) else {
            return
        }

        guard #available(macOS 14.2, *) else {
            throw GainBackendError.unsupportedOS
        }

        defer {
            Unmanaged<IOProcContext>.fromOpaque(handle.contextPointer).release()
            if handlesByProcessObjectID.isEmpty {
                currentOutputDeviceUID = nil
            }
        }

        var firstError: OSStatus?

        let stopStatus = AudioDeviceStop(handle.aggregateDeviceID, handle.ioProcID)
        if stopStatus != noErr, stopStatus != kAudioHardwareNotRunningError {
            firstError = stopStatus
        }

        let destroyIOProcStatus = AudioDeviceDestroyIOProcID(handle.aggregateDeviceID, handle.ioProcID)
        if destroyIOProcStatus != noErr, firstError == nil {
            firstError = destroyIOProcStatus
        }

        let destroyAggregateStatus = AudioHardwareDestroyAggregateDevice(handle.aggregateDeviceID)
        if destroyAggregateStatus != noErr, firstError == nil {
            firstError = destroyAggregateStatus
        }

        let destroyTapStatus = AudioHardwareDestroyProcessTap(handle.tapID)
        if destroyTapStatus != noErr, firstError == nil {
            firstError = destroyTapStatus
        }

        if let firstError {
            throw GainBackendError.coreAudio(firstError)
        }
    }

    func cleanup() {
        for processObjectID in Array(handlesByProcessObjectID.keys) {
            try? remove(processObjectID: processObjectID)
        }
        handlesByProcessObjectID.removeAll()
        currentOutputDeviceUID = nil
    }

    private func makeHandle(processObjectID: AudioObjectID, gain: Float) throws -> ActiveHandle {
        try ensureAudioCaptureUsageDescriptionPresent()

        let outputDeviceUID = try getDefaultSystemOutputDeviceUID()
        currentOutputDeviceUID = outputDeviceUID

        let tapID = try createTap(processObjectID: processObjectID)
        let tapUUID = try tapUUID(for: tapID)

        var contextPointer: UnsafeMutableRawPointer?

        do {
            let sampleFormat = gain < 0.999 ? try sampleFormat(for: tapID) : nil
            let context = IOProcContext(gain: gain, sampleFormat: sampleFormat)
            let retainedContext = Unmanaged.passRetained(context).toOpaque()
            contextPointer = retainedContext
            let aggregateDescription = makeAggregateDescription(
                processObjectID: processObjectID,
                tapUID: tapUUID.uuidString,
                outputDeviceUID: outputDeviceUID
            )

            var aggregateDeviceID: AudioObjectID = 0
            var status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID)
            guard status == noErr else {
                throw mapStatus(status)
            }

            var ioProcID: AudioDeviceIOProcID?
            status = AudioDeviceCreateIOProcID(aggregateDeviceID, Self.tapIOProc, retainedContext, &ioProcID)
            guard status == noErr, let ioProcID else {
                _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
                throw mapStatus(status)
            }

            status = AudioDeviceStart(aggregateDeviceID, ioProcID)
            guard status == noErr else {
                _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
                _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
                throw mapStatus(status)
            }

            return ActiveHandle(
                tapID: tapID,
                aggregateDeviceID: aggregateDeviceID,
                ioProcID: ioProcID,
                contextPointer: retainedContext
            )
        } catch {
            if let contextPointer {
                Unmanaged<IOProcContext>.fromOpaque(contextPointer).release()
            }
            _ = AudioHardwareDestroyProcessTap(tapID)
            throw error
        }
    }

    private func createTap(processObjectID: AudioObjectID) throws -> AudioObjectID {
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        tapDescription.uuid = UUID()
        tapDescription.name = "CodexAudioMonitorTap-\(processObjectID)"
        tapDescription.muteBehavior = CATapMuteBehavior.mutedWhenTapped
        tapDescription.isPrivate = true

        var tapID: AudioObjectID = 0
        let status = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard status == noErr else {
            throw mapStatus(status)
        }

        return tapID
    }

    private func tapUUID(for tapID: AudioObjectID) throws -> UUID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(tapID, &address) else {
            throw GainBackendError.coreAudio(kAudioHardwareUnknownPropertyError)
        }

        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, pointer)
        }

        guard status == noErr,
              let uid = value?.takeRetainedValue() as String?,
              let uuid = UUID(uuidString: uid)
        else {
            throw mapStatus(status)
        }

        return uuid
    }

    private func makeAggregateDescription(
        processObjectID: AudioObjectID,
        tapUID: String,
        outputDeviceUID: String
    ) -> [String: Any] {
        let aggregateUID = "com.zickox.codexaudiomonitor.tap.\(processObjectID).\(UUID().uuidString)"
        let aggregateName = "CodexAudioMonitorTap-\(processObjectID)"

        let tapList: [[String: Any]] = [
            [
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: true
            ]
        ]

        let subdeviceList: [[String: Any]] = [
            [
                kAudioSubDeviceUIDKey: outputDeviceUID
            ]
        ]

        return [
            kAudioAggregateDeviceNameKey: aggregateName,
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceSubDeviceListKey: subdeviceList,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapListKey: tapList,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceIsPrivateKey: true
        ]
    }

    private func resetHandlesIfOutputDeviceChanged() throws {
        let latestUID = try getDefaultSystemOutputDeviceUID()

        guard let currentUID = currentOutputDeviceUID else {
            currentOutputDeviceUID = latestUID
            return
        }

        guard currentUID != latestUID else {
            return
        }

        cleanup()
        currentOutputDeviceUID = latestUID
    }

    private func sampleFormat(for tapID: AudioObjectID) throws -> TapPCMScalarFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var streamFormat = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &streamFormat)
        guard status == noErr else {
            throw mapStatus(status)
        }

        guard let scalarFormat = TapPCMScalarFormat(streamFormat: streamFormat) else {
            throw GainBackendError.appGainUnavailable
        }

        return scalarFormat
    }

    private func getDefaultSystemOutputDeviceID() throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
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
            throw GainBackendError.coreAudio(status)
        }
        guard deviceID != kAudioObjectUnknown else {
            throw GainBackendError.coreAudio(kAudioHardwareBadObjectError)
        }

        return deviceID
    }

    private func getDefaultSystemOutputDeviceUID() throws -> String {
        let deviceID = try getDefaultSystemOutputDeviceID()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            throw GainBackendError.coreAudio(kAudioHardwareUnknownPropertyError)
        }

        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }

        guard status == noErr, let value else {
            throw GainBackendError.coreAudio(status)
        }

        return value.takeRetainedValue() as String
    }

    private func ensureAudioCaptureUsageDescriptionPresent(bundle: Bundle = .main) throws {
        guard let usageDescription = bundle.object(forInfoDictionaryKey: "NSAudioCaptureUsageDescription") as? String,
              !usageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GainBackendError.audioCapturePermissionRequired
        }
    }

    private func mapStatus(_ status: OSStatus) -> GainBackendError {
        if status == kAudioDevicePermissionsError {
            return .audioCapturePermissionRequired
        }
        return .coreAudio(status)
    }

    private static func zero(_ buffers: UnsafeMutableAudioBufferListPointer) {
        for index in 0..<buffers.count {
            guard let data = buffers[index].mData else {
                continue
            }

            memset(data, 0, Int(buffers[index].mDataByteSize))
        }
    }

    private func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
