import Foundation

#if canImport(CodexAudioCore)
import CodexAudioCore
#endif

@main
enum CodexAudioBridgeMain {
    static func main() async {
        let monitor = AudioProcessMonitor(pollInterval: .seconds(1))
        let handlers = BridgeHandlers(monitor: monitor)
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = []

        monitor.start()
        defer {
            monitor.stop()
        }

        while let line = readLine() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            let response: BridgeResponse

            do {
                let requestData = Data(trimmed.utf8)
                let request = try decoder.decode(BridgeRequest.self, from: requestData)
                response = handlers.handle(request: request)
            } catch {
                response = .invalidRequest(message: "Invalid JSON payload")
            }

            do {
                let responseData = try encoder.encode(response)
                if var responseText = String(data: responseData, encoding: .utf8) {
                    responseText.append("\n")
                    FileHandle.standardOutput.write(Data(responseText.utf8))
                }
            } catch {
                let fallback = BridgeResponse.failure(
                    id: response.id,
                    code: .internalError,
                    message: "Could not encode response"
                )
                if let fallbackData = try? encoder.encode(fallback),
                   var fallbackText = String(data: fallbackData, encoding: .utf8) {
                    fallbackText.append("\n")
                    FileHandle.standardOutput.write(Data(fallbackText.utf8))
                }
            }
        }
    }
}
