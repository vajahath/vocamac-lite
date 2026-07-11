// RemoteTranscriptionServiceTests.swift
// VocaMac Tests
//
// Tests for RemoteTranscriptionService: WAV encoding, request building,
// response parsing, error mapping, hallucination filtering, and vocabulary.

import XCTest
@testable import VocaMac

// MARK: - WAV Encoder Tests

final class WAVEncoderTests: XCTestCase {

    func testOutputSizeIsHeaderPlusSamples() {
        let samples = [Float](repeating: 0.5, count: 1600)
        let data = WAVEncoder.encode(samples: samples)
        XCTAssertEqual(data.count, 44 + samples.count * 2)
    }

    func testHeaderMagicBytes() {
        let data = WAVEncoder.encode(samples: [0.0, 0.1, -0.1])
        XCTAssertEqual(String(data: data[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: data[12..<16], encoding: .ascii), "fmt ")
        XCTAssertEqual(String(data: data[36..<40], encoding: .ascii), "data")
    }

    func testFormatFields() {
        let data = WAVEncoder.encode(samples: [0.0], sampleRate: 16000)
        // PCM format tag
        XCTAssertEqual(data[20], 1)
        XCTAssertEqual(data[21], 0)
        // Mono
        XCTAssertEqual(data[22], 1)
        XCTAssertEqual(data[23], 0)
        // Sample rate 16000 = 0x3E80 little-endian
        XCTAssertEqual(data[24], 0x80)
        XCTAssertEqual(data[25], 0x3E)
        // Bits per sample = 16
        XCTAssertEqual(data[34], 16)
        XCTAssertEqual(data[35], 0)
    }

    func testClampsOutOfRangeSamples() {
        let data = WAVEncoder.encode(samples: [2.0, -2.0])
        let maxSample = data[44..<46].withUnsafeBytes { $0.load(as: Int16.self) }
        XCTAssertEqual(maxSample, Int16.max)
    }

    func testEmptyInputProducesHeaderOnly() {
        let data = WAVEncoder.encode(samples: [])
        XCTAssertEqual(data.count, 44)
    }
}

// MARK: - Request Building Tests

final class RemoteRequestBuildingTests: XCTestCase {

    private func config(
        baseURL: String = "http://host:8000",
        format: RemoteEndpointFormat = .openAI,
        apiKey: String = "",
        modelName: String = ""
    ) -> RemoteEndpointConfiguration {
        RemoteEndpointConfiguration(baseURL: baseURL, format: format, apiKey: apiKey, modelName: modelName)
    }

    func testOpenAITranscriptionURL() throws {
        let url = try RemoteTranscriptionService.requestURL(config: config(), translate: false)
        XCTAssertEqual(url.absoluteString, "http://host:8000/v1/audio/transcriptions")
    }

    func testOpenAITranslationURL() throws {
        let url = try RemoteTranscriptionService.requestURL(config: config(), translate: true)
        XCTAssertEqual(url.absoluteString, "http://host:8000/v1/audio/translations")
    }

    func testWhisperCppURL() throws {
        let url = try RemoteTranscriptionService.requestURL(
            config: config(format: .whisperCpp), translate: true
        )
        XCTAssertEqual(url.absoluteString, "http://host:8000/inference")
    }

    func testTrailingSlashIsTrimmed() throws {
        let url = try RemoteTranscriptionService.requestURL(
            config: config(baseURL: "http://host:8000/"), translate: false
        )
        XCTAssertEqual(url.absoluteString, "http://host:8000/v1/audio/transcriptions")
    }

    func testUnconfiguredThrows() {
        XCTAssertThrowsError(
            try RemoteTranscriptionService.requestURL(config: config(baseURL: ""), translate: false)
        ) { error in
            guard case RemoteTranscriptionError.notConfigured = error else {
                return XCTFail("Expected .notConfigured, got \(error)")
            }
        }
    }

    func testInvalidURLThrows() {
        XCTAssertThrowsError(
            try RemoteTranscriptionService.requestURL(config: config(baseURL: "not a url"), translate: false)
        ) { error in
            guard case RemoteTranscriptionError.invalidURL = error else {
                return XCTFail("Expected .invalidURL, got \(error)")
            }
        }
    }

    private func bodyString(
        format: RemoteEndpointFormat = .openAI,
        modelName: String = "",
        language: String? = nil,
        translate: Bool = false,
        vocabulary: String = ""
    ) -> String {
        let body = RemoteTranscriptionService.multipartBody(
            boundary: "test-boundary",
            wavData: Data("wav".utf8),
            config: config(format: format, modelName: modelName),
            language: language,
            translate: translate,
            vocabulary: vocabulary
        )
        return String(decoding: body, as: UTF8.self)
    }

    func testBodyContainsFilePart() {
        let body = bodyString()
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"audio.wav\""))
        XCTAssertTrue(body.contains("Content-Type: audio/wav"))
        XCTAssertTrue(body.contains("name=\"response_format\""))
        XCTAssertTrue(body.hasSuffix("--test-boundary--\r\n"))
    }

    func testModelFieldOnlyWhenSetAndOpenAI() {
        XCTAssertFalse(bodyString().contains("name=\"model\""))
        XCTAssertTrue(bodyString(modelName: "whisper-1").contains("name=\"model\""))
        XCTAssertFalse(bodyString(format: .whisperCpp, modelName: "whisper-1").contains("name=\"model\""))
    }

    func testLanguageFieldOnlyWhenSet() {
        XCTAssertFalse(bodyString().contains("name=\"language\""))
        XCTAssertTrue(bodyString(language: "en").contains("name=\"language\""))
    }

    func testPromptFieldFromVocabulary() {
        XCTAssertFalse(bodyString().contains("name=\"prompt\""))
        let body = bodyString(vocabulary: "kubectl, Grafana")
        XCTAssertTrue(body.contains("name=\"prompt\""))
        XCTAssertTrue(body.contains("Glossary: kubectl, Grafana"))
    }

    func testTranslateFieldOnlyForWhisperCpp() {
        XCTAssertFalse(bodyString(translate: true).contains("name=\"translate\""))
        XCTAssertTrue(bodyString(format: .whisperCpp, translate: true).contains("name=\"translate\""))
    }
}

// MARK: - Response Parsing Tests

final class RemoteResponseParsingTests: XCTestCase {

    func testParsesTextField() {
        let data = Data(#"{"text": "hello world"}"#.utf8)
        XCTAssertEqual(RemoteTranscriptionService.parseResponse(data), "hello world")
    }

    func testRejectsMissingTextField() {
        XCTAssertNil(RemoteTranscriptionService.parseResponse(Data(#"{"result": "x"}"#.utf8)))
        XCTAssertNil(RemoteTranscriptionService.parseResponse(Data("not json".utf8)))
        XCTAssertNil(RemoteTranscriptionService.parseResponse(Data(#"{"text": 42}"#.utf8)))
    }
}

// MARK: - Transcribe Error Tests

final class RemoteTranscribeErrorTests: XCTestCase {

    func testUnconfiguredThrowsBeforeNetworking() async {
        let service = RemoteTranscriptionService(configProvider: {
            RemoteEndpointConfiguration(baseURL: "", format: .openAI, apiKey: "", modelName: "")
        })
        do {
            _ = try await service.transcribe(audioData: [0.1], language: nil, translate: false, vocabulary: "")
            XCTFail("Expected notConfigured")
        } catch {
            guard case RemoteTranscriptionError.notConfigured = error else {
                return XCTFail("Expected .notConfigured, got \(error)")
            }
        }
    }

    func testEmptyAudioThrows() async {
        let service = RemoteTranscriptionService(configProvider: {
            RemoteEndpointConfiguration(baseURL: "http://host:8000", format: .openAI, apiKey: "", modelName: "")
        })
        do {
            _ = try await service.transcribe(audioData: [], language: nil, translate: false, vocabulary: "")
            XCTFail("Expected emptyAudio")
        } catch {
            guard case RemoteTranscriptionError.emptyAudio = error else {
                return XCTFail("Expected .emptyAudio, got \(error)")
            }
        }
    }

    func testHTTPErrorDescriptionsIncludeHints() {
        let unauthorized = RemoteTranscriptionError.httpError(status: 401, body: "")
        XCTAssertTrue(unauthorized.localizedDescription.contains("API key"))

        let serverError = RemoteTranscriptionError.httpError(status: 500, body: "boom")
        XCTAssertTrue(serverError.localizedDescription.contains("500"))
        XCTAssertTrue(serverError.localizedDescription.contains("boom"))
    }
}

// MARK: - Hallucination Filtering Tests

final class HallucinationFilteringTests: XCTestCase {

    func testFilterBlankAudioToken() {
        XCTAssertEqual(RemoteTranscriptionService.filterHallucinationTokens("[BLANK_AUDIO]"), "")
    }

    func testFilterBlankAudioTokenCaseInsensitive() {
        XCTAssertEqual(RemoteTranscriptionService.filterHallucinationTokens("[blank_audio]"), "")
    }

    func testFilterBlankAudioMixedWithText() {
        XCTAssertEqual(
            RemoteTranscriptionService.filterHallucinationTokens("Hello [BLANK_AUDIO] world"),
            "Hello world"
        )
    }

    func testFilterMultipleHallucinationTokens() {
        XCTAssertEqual(
            RemoteTranscriptionService.filterHallucinationTokens("[BLANK_AUDIO] [NO_SPEECH] some text (silence)"),
            "some text"
        )
    }

    func testFilterPreservesNormalText() {
        XCTAssertEqual(
            RemoteTranscriptionService.filterHallucinationTokens("This is a normal transcription"),
            "This is a normal transcription"
        )
    }

    func testFilterEmptyInput() {
        XCTAssertEqual(RemoteTranscriptionService.filterHallucinationTokens(""), "")
    }

    func testFilterOnlyWhitespaceAroundToken() {
        XCTAssertEqual(RemoteTranscriptionService.filterHallucinationTokens("   [BLANK_AUDIO]   "), "")
    }
}

// MARK: - Custom Vocabulary Tests

final class VocabularyTermsTests: XCTestCase {

    func testEmptyStringYieldsNoTerms() {
        XCTAssertEqual(RemoteTranscriptionService.vocabularyTerms(from: ""), [])
        XCTAssertEqual(RemoteTranscriptionService.vocabularyTerms(from: "   \n  \n"), [])
    }

    func testSplitsOnNewlinesAndCommas() {
        let input = "Namrata\nKubernetes, kubectl\n  etcd  "
        XCTAssertEqual(
            RemoteTranscriptionService.vocabularyTerms(from: input),
            ["Namrata", "Kubernetes", "kubectl", "etcd"]
        )
    }

    func testDropsBlankEntries() {
        let input = "Namrata,,\n\n, ,VocaMac"
        XCTAssertEqual(RemoteTranscriptionService.vocabularyTerms(from: input), ["Namrata", "VocaMac"])
    }
}
