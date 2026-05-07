import Foundation
import Security

// MARK: - Провайдеры

enum CloudProvider: String, CaseIterable, Identifiable {
    case openai  = "openai"
    case groq    = "groq"
    case deepgram = "deepgram"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai:   return "OpenAI Whisper"
        case .groq:     return "Groq"
        case .deepgram: return "Deepgram"
        }
    }

    var description: String {
        switch self {
        case .openai:   return "OpenAI API, whisper-1"
        case .groq:     return "Groq API, whisper-large-v3"
        case .deepgram: return "Deepgram Nova-3"
        }
    }

    var endpointURL: URL {
        switch self {
        case .openai:
            return URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        case .groq:
            return URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        case .deepgram:
            return URL(string: "https://api.deepgram.com/v1/listen?model=nova-3&language=ru")!
        }
    }

    // Ключ в Keychain для хранения API-ключа провайдера
    var keychainKey: String { "com.voicetotext.apikey.\(rawValue)" }
}

// MARK: - Keychain

enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String:   data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - CloudTranscriber

class CloudTranscriber {

    func transcribe(audio: [Float], provider: CloudProvider, language: String = "ru") async -> String? {
        guard let apiKey = KeychainHelper.load(key: provider.keychainKey), !apiKey.isEmpty else {
            print("CloudTranscriber: API-ключ для \(provider.displayName) не задан")
            return nil
        }

        // Конвертируем Float-аудио в WAV-данные
        guard let wavData = floatsToWAV(samples: audio, sampleRate: 16000) else {
            print("CloudTranscriber: не удалось конвертировать аудио")
            return nil
        }

        switch provider {
        case .openai, .groq:
            return await transcribeWhisperAPI(wavData: wavData, provider: provider, apiKey: apiKey, language: language)
        case .deepgram:
            return await transcribeDeepgram(wavData: wavData, apiKey: apiKey, language: language)
        }
    }

    // MARK: - OpenAI / Groq (совместимый API)

    private func transcribeWhisperAPI(
        wavData: Data,
        provider: CloudProvider,
        apiKey: String,
        language: String
    ) async -> String? {
        let boundary = UUID().uuidString
        var request = URLRequest(url: provider.endpointURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // model
        let modelName = provider == .groq ? "whisper-large-v3" : "whisper-1"
        body.appendFormField(boundary: boundary, name: "model", value: modelName)
        // language
        if language != "auto" {
            body.appendFormField(boundary: boundary, name: "language", value: language)
        }
        // response_format
        body.appendFormField(boundary: boundary, name: "response_format", value: "text")
        // file
        body.appendFilePart(boundary: boundary, name: "file", filename: "audio.wav", mimeType: "audio/wav", data: wavData)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? "unknown"
                print("CloudTranscriber [\(provider.displayName)] HTTP error: \(msg)")
                return nil
            }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("CloudTranscriber [\(provider.displayName)] error: \(error)")
            return nil
        }
    }

    // MARK: - Deepgram

    private func transcribeDeepgram(wavData: Data, apiKey: String, language: String) async -> String? {
        var urlString = "https://api.deepgram.com/v1/listen?model=nova-3"
        if language != "auto" {
            urlString += "&language=\(language)"
        }
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wavData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? "unknown"
                print("CloudTranscriber [Deepgram] HTTP error: \(msg)")
                return nil
            }
            // Deepgram возвращает JSON: results.channels[0].alternatives[0].transcript
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let results = json["results"] as? [String: Any],
                let channels = results["channels"] as? [[String: Any]],
                let first = channels.first,
                let alternatives = first["alternatives"] as? [[String: Any]],
                let transcript = alternatives.first?["transcript"] as? String
            else { return nil }
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("CloudTranscriber [Deepgram] error: \(error)")
            return nil
        }
    }

    // MARK: - WAV конвертер

    private func floatsToWAV(samples: [Float], sampleRate: Int) -> Data? {
        let numSamples = samples.count
        let numChannels: Int = 1
        let bitsPerSample: Int = 16
        let byteRate = sampleRate * numChannels * bitsPerSample / 8
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = numSamples * blockAlign
        let fileSize = 44 + dataSize

        var data = Data(capacity: fileSize)

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.appendLE32(UInt32(fileSize - 8))
        data.append(contentsOf: "WAVE".utf8)
        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.appendLE32(16)            // chunk size
        data.appendLE16(1)             // PCM
        data.appendLE16(UInt16(numChannels))
        data.appendLE32(UInt32(sampleRate))
        data.appendLE32(UInt32(byteRate))
        data.appendLE16(UInt16(blockAlign))
        data.appendLE16(UInt16(bitsPerSample))
        // data chunk
        data.append(contentsOf: "data".utf8)
        data.appendLE32(UInt32(dataSize))

        // Samples: float -> int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * Float(Int16.max))
            data.appendLE16(UInt16(bitPattern: int16))
        }

        return data
    }
}

// MARK: - Data helpers

private extension Data {
    mutating func appendLE32(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
    mutating func appendLE16(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
    mutating func appendFormField(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
    mutating func appendFilePart(boundary: String, name: String, filename: String, mimeType: String, data fileData: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(fileData)
        append("\r\n".data(using: .utf8)!)
    }
}
