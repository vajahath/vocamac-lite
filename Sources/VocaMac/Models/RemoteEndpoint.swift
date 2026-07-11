// RemoteEndpoint.swift
// VocaMac
//
// Configuration types for the remote transcription endpoint.

import Foundation

// MARK: - RemoteEndpointFormat

/// The wire format the remote transcription server speaks.
enum RemoteEndpointFormat: String, CaseIterable, Identifiable {
    /// OpenAI-compatible Whisper API: POST {base}/v1/audio/transcriptions
    /// (Speaches, faster-whisper-server, LocalAI, OpenAI itself).
    case openAI = "openai"

    /// whisper.cpp's bundled HTTP server: POST {base}/inference
    case whisperCpp = "whispercpp"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI-compatible"
        case .whisperCpp:
            return "whisper.cpp server"
        }
    }

    var detailDescription: String {
        switch self {
        case .openAI:
            return "Speaches, faster-whisper-server, LocalAI, OpenAI (/v1/audio/transcriptions)"
        case .whisperCpp:
            return "whisper.cpp whisper-server (/inference)"
        }
    }
}

// MARK: - RemoteEndpointConfiguration

/// Snapshot of the user's endpoint settings, read from UserDefaults
/// (the same store that @AppStorage in AppState writes to).
struct RemoteEndpointConfiguration {
    /// Server base URL, e.g. "http://192.168.1.10:8000". Trailing slashes are tolerated.
    var baseURL: String

    var format: RemoteEndpointFormat

    /// Optional API key, sent as "Authorization: Bearer <key>" when non-empty.
    var apiKey: String

    /// Optional model name, sent as the multipart "model" field (OpenAI format only) when non-empty.
    var modelName: String

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Base URL normalized: whitespace trimmed, trailing slashes removed.
    var normalizedBaseURL: String {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    static let urlKey = "vocamac.remoteEndpointURL"
    static let formatKey = "vocamac.remoteEndpointFormat"
    static let apiKeyKey = "vocamac.remoteAPIKey"
    static let modelNameKey = "vocamac.remoteModelName"

    static func fromUserDefaults(_ defaults: UserDefaults = .standard) -> RemoteEndpointConfiguration {
        RemoteEndpointConfiguration(
            baseURL: defaults.string(forKey: urlKey) ?? "",
            format: RemoteEndpointFormat(rawValue: defaults.string(forKey: formatKey) ?? "") ?? .openAI,
            apiKey: defaults.string(forKey: apiKeyKey) ?? "",
            modelName: defaults.string(forKey: modelNameKey) ?? ""
        )
    }
}
