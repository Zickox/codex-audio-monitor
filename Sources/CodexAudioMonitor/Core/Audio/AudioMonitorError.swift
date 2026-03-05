import CoreAudio
import Foundation

enum AudioMonitorError: LocalizedError, Equatable {
    case unsupportedOS
    case coreAudio(OSStatus)
    case sessionNotFound(String)
    case volumeControlUnavailable
    case appGainUnavailable
    case audioCapturePermissionRequired

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "Se requiere macOS 14.2 o superior para silenciar por app."
        case let .coreAudio(status):
            let code = Self.decodeFourCharCode(status)
            return "CoreAudio devolvió \(code) (\(status))."
        case let .sessionNotFound(sessionID):
            return "No se encontró la sesión de audio: \(sessionID)."
        case .volumeControlUnavailable:
            return "El dispositivo de salida actual no permite cambiar volumen."
        case .appGainUnavailable:
            return "App Gain no está disponible con el formato de salida actual."
        case .audioCapturePermissionRequired:
            return "App Gain requiere permiso de captura de audio del sistema. Acepta el prompt de macOS para continuar."
        }
    }

    private static func decodeFourCharCode(_ status: OSStatus) -> String {
        let bigEndian = CFSwapInt32HostToBig(UInt32(bitPattern: status))
        let chars = [
            Character(UnicodeScalar((bigEndian >> 24) & 0xFF)!),
            Character(UnicodeScalar((bigEndian >> 16) & 0xFF)!),
            Character(UnicodeScalar((bigEndian >> 8) & 0xFF)!),
            Character(UnicodeScalar(bigEndian & 0xFF)!)
        ]
        let text = String(chars)
        if text.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 127 }) {
            return "'\(text)'"
        }
        return String(status)
    }
}
