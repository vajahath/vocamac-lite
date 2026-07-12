// RemoteTranscriptionService.swift
// VocaMac Lite
//
// Sends recorded audio to a user-configured remote transcription server.
// Supports OpenAI-compatible endpoints (/v1/audio/transcriptions) and
// whisper.cpp's bundled HTTP server (/inference). Audio is encoded as an
// in-memory 16 kHz mono 16-bit PCM WAV and uploaded as multipart/form-data;
// the server responds with JSON containing a "text" field.

import Foundation

// MARK: - RemoteTranscriptionError

enum RemoteTranscriptionError: LocalizedError {
    case notConfigured
    case invalidURL(String)
    case emptyAudio
    case network(URLError)
    case httpError(status: Int, body: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No transcription server configured. Set the server URL in Settings → Endpoint."
        case .invalidURL(let url):
            return "Invalid server URL: \(url)"
        case .emptyAudio:
            return "No audio data to transcribe."
        case .network(let underlying):
            return "Could not reach server: \(underlying.localizedDescription)"
        case .httpError(let status, let body):
            var message = "Server returned HTTP \(status)"
            if status == 401 || status == 403 {
                message += " — check the API key in Settings → Endpoint"
            }
            let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedBody.isEmpty {
                message += ": \(trimmedBody.prefix(200))"
            }
            return message
        case .invalidResponse:
            return "Server response was not valid JSON with a 'text' field."
        }
    }
}

// MARK: - WAVEncoder

/// Encodes Float32 PCM samples into an in-memory WAV file (16-bit PCM, mono).
enum WAVEncoder {
    static func encode(samples: [Float], sampleRate: Int = 16000) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = samples.count * 2

        var data = Data(capacity: 44 + dataSize)

        func append(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func append(_ value: UInt16) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))                 // fmt chunk size
        append(UInt16(1))                  // PCM
        append(UInt16(channels))
        append(UInt32(sampleRate))
        append(UInt32(byteRate))
        append(UInt16(blockAlign))
        append(UInt16(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))

        var pcm = [Int16](repeating: 0, count: samples.count)
        for (index, sample) in samples.enumerated() {
            let clamped = max(-1.0, min(1.0, sample))
            pcm[index] = Int16(clamped * Float(Int16.max))
        }
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }

        return data
    }
}

// MARK: - RemoteTranscriptionService

final class RemoteTranscriptionService: @unchecked Sendable {

    /// Reads the current endpoint settings; injectable so tests can supply a fixed config.
    private let configProvider: () -> RemoteEndpointConfiguration

    private let session: URLSession

    init(configProvider: @escaping () -> RemoteEndpointConfiguration = { RemoteEndpointConfiguration.fromUserDefaults() }) {
        self.configProvider = configProvider

        let configuration = URLSessionConfiguration.ephemeral
        // Fail fast: a stuck dictation hotkey flow is worse than an error.
        configuration.timeoutIntervalForRequest = 30
        // Long clips on a slow remote box need headroom for the full round-trip.
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Request Building

    /// Build the request URL for the configured format.
    static func requestURL(config: RemoteEndpointConfiguration, translate: Bool) throws -> URL {
        guard config.isConfigured else {
            throw RemoteTranscriptionError.notConfigured
        }
        let base = config.normalizedBaseURL
        let path: String
        switch config.format {
        case .openAI:
            path = translate ? "/v1/audio/translations" : "/v1/audio/transcriptions"
        case .whisperCpp:
            path = "/inference"
        }
        guard let url = URL(string: base + path), url.scheme != nil, url.host != nil else {
            throw RemoteTranscriptionError.invalidURL(base)
        }
        return url
    }

    /// Build the multipart/form-data body for a transcription request.
    static func multipartBody(
        boundary: String,
        wavData: Data,
        config: RemoteEndpointConfiguration,
        language: String?,
        translate: Bool,
        vocabulary: String
    ) -> Data {
        var body = Data()

        func appendField(name: String, value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wavData)
        body.append(Data("\r\n".utf8))

        if config.format == .openAI, !config.modelName.trimmingCharacters(in: .whitespaces).isEmpty {
            appendField(name: "model", value: config.modelName.trimmingCharacters(in: .whitespaces))
        }
        if let language, !language.isEmpty {
            appendField(name: "language", value: language)
        }
        let terms = vocabularyTerms(from: vocabulary)
        if !terms.isEmpty {
            appendField(name: "prompt", value: "Glossary: " + terms.joined(separator: ", "))
        }
        if config.format == .whisperCpp, translate {
            // Honored by whisper.cpp's whisper-server; older builds ignore it.
            appendField(name: "translate", value: "true")
        }
        appendField(name: "response_format", value: "json")

        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    /// Parse the server's JSON response, expecting a top-level "text" field.
    static func parseResponse(_ data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = object["text"] as? String
        else {
            return nil
        }
        return text
    }

    // MARK: - Networking

    private func performRequest(
        wavData: Data,
        config: RemoteEndpointConfiguration,
        language: String?,
        translate: Bool,
        vocabulary: String
    ) async throws -> String {
        let url = try Self.requestURL(config: config, translate: translate)
        let boundary = "vocamac-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespaces)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            wavData: wavData,
            config: config,
            language: language,
            translate: translate,
            vocabulary: vocabulary
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw RemoteTranscriptionError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RemoteTranscriptionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RemoteTranscriptionError.httpError(
                status: http.statusCode,
                body: String(data: data.prefix(500), encoding: .utf8) ?? ""
            )
        }
        guard let text = Self.parseResponse(data) else {
            throw RemoteTranscriptionError.invalidResponse
        }
        return text
    }

    // MARK: - Connection Test

    /// Send 1s of silence through the real request path to validate URL,
    /// format, auth, and multipart handling in one shot. (A full second,
    /// because some whisper.cpp builds reject sub-second audio.)
    func testConnection() async throws -> String {
        let config = configProvider()
        let silence = [Float](repeating: 0, count: 16000)
        let wavData = WAVEncoder.encode(samples: silence)

        let startTime = CFAbsoluteTimeGetCurrent()
        _ = try await performRequest(
            wavData: wavData,
            config: config,
            language: nil,
            translate: false,
            vocabulary: ""
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        return String(format: "Connected · %.1fs", elapsed)
    }

    /// Lightweight liveness probe: a `GET {base}/health`. Any HTTP response —
    /// even 404 or 401 — proves the server is up and reachable at the configured
    /// host:port; only a transport failure (connection refused, timeout, DNS)
    /// counts as unreachable. Far cheaper than `testConnection()`, which encodes
    /// and uploads a full WAV through the transcription path, so this is what the
    /// automatic/background status check uses.
    func checkHealth() async throws -> String {
        let config = configProvider()
        guard config.isConfigured else {
            throw RemoteTranscriptionError.notConfigured
        }
        let base = config.normalizedBaseURL
        guard let url = URL(string: base + "/health"), url.scheme != nil, url.host != nil else {
            throw RemoteTranscriptionError.invalidURL(base)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Liveness should fail fast — no reason to wait the full 30s upload budget.
        request.timeoutInterval = 5
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespaces)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            let (_, response) = try await session.data(for: request)
            guard response is HTTPURLResponse else {
                throw RemoteTranscriptionError.invalidResponse
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            return String(format: "Online · %.2fs", elapsed)
        } catch let error as URLError {
            throw RemoteTranscriptionError.network(error)
        }
    }

    // MARK: - Hallucination Filtering

    /// Tokens Whisper models may emit for silence, noise, or very short audio.
    /// These are model artifacts and should never be shown to the user.
    private static let hallucinationPatterns: [String] = [
        "[BLANK_AUDIO]",
        "(blank audio)",
        "[NO_SPEECH]",
        "(no speech)",
        "[ Silence ]",
        "[silence]",
        "(silence)",
        "[Music]",
        "(music)",
        "[Applause]",
        "(applause)",
    ]

    /// Remove hallucination tokens from transcribed text.
    /// Returns the cleaned string, which may be empty if the entire output
    /// consisted of hallucination tokens.
    static func filterHallucinationTokens(_ text: String) -> String {
        var cleaned = text
        for pattern in hallucinationPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
        }
        // Collapse multiple spaces left behind by removed tokens
        cleaned = cleaned.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Custom Vocabulary

    /// Parse a raw vocabulary string into individual terms. Terms are separated
    /// by newlines or commas; surrounding whitespace and blank entries are dropped.
    static func vocabularyTerms(from vocabulary: String) -> [String] {
        vocabulary
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - SpeechTranscribing Conformance

extension RemoteTranscriptionService: SpeechTranscribing {

    /// Transcribe audio by uploading it to the configured remote server.
    /// - Parameters:
    ///   - audioData: Array of Float32 PCM samples at 16kHz mono
    ///   - language: ISO 639-1 language code (e.g., "en"), or nil for auto-detection
    ///   - translate: Whether to translate to English (if true) or transcribe as-is (if false)
    ///   - vocabulary: Custom terms (newline/comma separated) sent as a "Glossary:" prompt
    func transcribe(
        audioData: [Float],
        language: String?,
        translate: Bool,
        vocabulary: String
    ) async throws -> VocaTranscription {
        let config = configProvider()
        guard config.isConfigured else {
            throw RemoteTranscriptionError.notConfigured
        }
        guard !audioData.isEmpty else {
            throw RemoteTranscriptionError.emptyAudio
        }

        let audioLengthSeconds = Double(audioData.count) / 16000.0
        VocaLogger.info(.transcription, "Uploading \(String(format: "%.1f", audioLengthSeconds))s of audio to \(config.normalizedBaseURL) (\(config.format.rawValue))...")

        let startTime = CFAbsoluteTimeGetCurrent()
        let wavData = WAVEncoder.encode(samples: audioData)
        let rawText = try await performRequest(
            wavData: wavData,
            config: config,
            language: language,
            translate: translate,
            vocabulary: vocabulary
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        let fullText = Self.filterHallucinationTokens(rawText)

        VocaLogger.info(.transcription, "Transcription completed in \(String(format: "%.2f", elapsed))s")
        VocaLogger.info(.transcription, "Result: \(fullText.prefix(100))...")

        let modelName = config.modelName.trimmingCharacters(in: .whitespaces)
        return VocaTranscription(
            text: fullText,
            duration: elapsed,
            detectedLanguage: language ?? "auto",
            audioLengthSeconds: audioLengthSeconds,
            modelUsed: modelName.isEmpty ? "remote" : modelName
        )
    }
}
