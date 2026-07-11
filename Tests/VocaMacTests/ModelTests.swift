// ModelTests.swift
// VocaMac Tests
//
// Tests for data models: SystemInfo, RemoteEndpoint, TranscriptionResult,
// AppStatus, ActivationMode.

import XCTest
import ServiceManagement
@testable import VocaMac

// MARK: - SystemInfo Tests

final class SystemInfoTests: XCTestCase {

    func testDetectSystemCapabilities() {
        let capabilities = SystemInfo.detect()
        XCTAssertGreaterThan(capabilities.physicalMemoryGB, 0)
        XCTAssertGreaterThan(capabilities.coreCount, 0)
        XCTAssertFalse(capabilities.processorName.isEmpty)
    }

    func testModelIdentifier() {
        XCTAssertFalse(SystemInfo.modelIdentifier.isEmpty)
    }

    func testSummaryDescription() {
        let capabilities = SystemInfo.detect()
        let summary = capabilities.summaryDescription
        XCTAssertTrue(summary.contains("Processor:"))
        XCTAssertTrue(summary.contains("Architecture:"))
        XCTAssertTrue(summary.contains("Memory:"))
        XCTAssertTrue(summary.contains("Cores:"))
        XCTAssertTrue(summary.contains("Metal:"))
    }
}

// MARK: - RemoteEndpoint Tests

final class RemoteEndpointConfigurationTests: XCTestCase {

    func testIsConfigured() {
        var config = RemoteEndpointConfiguration(baseURL: "", format: .openAI, apiKey: "", modelName: "")
        XCTAssertFalse(config.isConfigured)

        config.baseURL = "   "
        XCTAssertFalse(config.isConfigured)

        config.baseURL = "http://192.168.1.10:8000"
        XCTAssertTrue(config.isConfigured)
    }

    func testNormalizedBaseURLTrimsTrailingSlashes() {
        let config = RemoteEndpointConfiguration(
            baseURL: "  http://host:8000// ", format: .openAI, apiKey: "", modelName: ""
        )
        XCTAssertEqual(config.normalizedBaseURL, "http://host:8000")
    }

    func testFromUserDefaultsFallsBackToOpenAI() {
        let defaults = UserDefaults(suiteName: "test.remoteEndpoint")!
        defaults.removePersistentDomain(forName: "test.remoteEndpoint")
        let config = RemoteEndpointConfiguration.fromUserDefaults(defaults)
        XCTAssertEqual(config.format, .openAI)
        XCTAssertEqual(config.baseURL, "")
        XCTAssertFalse(config.isConfigured)
    }

    func testFormatDisplayNames() {
        for format in RemoteEndpointFormat.allCases {
            XCTAssertFalse(format.displayName.isEmpty)
            XCTAssertFalse(format.detailDescription.isEmpty)
        }
    }

    func testFormatRawValues() {
        XCTAssertEqual(RemoteEndpointFormat.openAI.rawValue, "openai")
        XCTAssertEqual(RemoteEndpointFormat.whisperCpp.rawValue, "whispercpp")
    }
}

// MARK: - TranscriptionResult Tests

final class VocaTranscriptionTests: XCTestCase {

    func testCreationPreservesValues() {
        let result = VocaTranscription(
            text: "Hello world", duration: 1.5,
            detectedLanguage: "en", audioLengthSeconds: 3.0, modelUsed: "remote"
        )
        XCTAssertEqual(result.text, "Hello world")
        XCTAssertEqual(result.duration, 1.5)
        XCTAssertEqual(result.detectedLanguage, "en")
        XCTAssertEqual(result.audioLengthSeconds, 3.0)
        XCTAssertEqual(result.modelUsed, "remote")
    }

    func testUniqueID() {
        let r1 = VocaTranscription(
            text: "Hello", duration: 1.0,
            detectedLanguage: "en", audioLengthSeconds: 2.0, modelUsed: "remote"
        )
        let r2 = VocaTranscription(
            text: "Hello", duration: 1.0,
            detectedLanguage: "en", audioLengthSeconds: 2.0, modelUsed: "remote"
        )
        XCTAssertNotEqual(r1.id, r2.id)
    }
}

// MARK: - AppStatus Tests

final class AppStatusTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(AppStatus.idle.rawValue, "idle")
        XCTAssertEqual(AppStatus.recording.rawValue, "recording")
        XCTAssertEqual(AppStatus.processing.rawValue, "processing")
        XCTAssertEqual(AppStatus.error.rawValue, "error")
    }
}

// MARK: - ActivationMode Tests

final class ActivationModeTests: XCTestCase {

    func testDisplayNames() {
        for mode in ActivationMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty)
        }
    }

    func testDescriptions() {
        for mode in ActivationMode.allCases {
            XCTAssertFalse(mode.description.isEmpty)
        }
    }

    func testActivationModeCaseCount() {
        XCTAssertEqual(ActivationMode.allCases.count, 2)
    }

    func testRawValues() {
        XCTAssertEqual(ActivationMode.pushToTalk.rawValue, "pushToTalk")
        XCTAssertEqual(ActivationMode.doubleTapToggle.rawValue, "doubleTapToggle")
    }
}
