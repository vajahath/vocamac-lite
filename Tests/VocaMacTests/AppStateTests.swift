// AppStateTests.swift
// VocaMac Tests
//
// Tests for AppState: translation toggle, onboarding, launch at login.

import XCTest
import ServiceManagement
@testable import VocaMac

// MARK: - Translation Toggle Tests

final class TranslationToggleTests: XCTestCase {

    @MainActor
    func testTranslationEnabledDefaultValue() {
        let (appState, _) = AppState.makeTestState()
        XCTAssertFalse(appState.translationEnabled)
    }

    @MainActor
    func testTranslationEnabledCanBeToggled() {
        let (appState, _) = AppState.makeTestState()
        XCTAssertFalse(appState.translationEnabled)

        appState.translationEnabled = true
        XCTAssertTrue(appState.translationEnabled)

        appState.translationEnabled = false
        XCTAssertFalse(appState.translationEnabled)
    }
}


// MARK: - OnboardingStep Tests

final class OnboardingStepTests: XCTestCase {

    func testOnboardingStepOrdering() {
        let steps = OnboardingStep.allCases
        XCTAssertEqual(steps.count, 6)
        XCTAssertEqual(steps[0], .welcome)
        XCTAssertEqual(steps[1], .permissions)
        XCTAssertEqual(steps[2], .endpointSetup)
        XCTAssertEqual(steps[3], .hotkeyConfig)
        XCTAssertEqual(steps[4], .quickTest)
        XCTAssertEqual(steps[5], .complete)
    }

    func testOnboardingStepTitles() {
        for step in OnboardingStep.allCases {
            XCTAssertFalse(step.title.isEmpty)
        }
    }

    func testOnboardingStepNumbers() {
        for (index, step) in OnboardingStep.allCases.enumerated() {
            XCTAssertEqual(step.stepNumber, "Step \(index + 1) of \(OnboardingStep.allCases.count)")
        }
    }

    func testOnboardingStepIdentifiable() {
        let steps = OnboardingStep.allCases
        let ids = steps.map { $0.id }
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count)
    }
}


// MARK: - Launch at Login Tests

final class LaunchAtLoginTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "vocamac.launchAtLogin")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "vocamac.launchAtLogin")
        super.tearDown()
    }

    @MainActor
    func testLaunchAtLoginDefaultsToFalse() {
        let (appState, _) = AppState.makeTestState()
        XCTAssertFalse(appState.launchAtLogin)
    }

    @MainActor
    func testLaunchAtLoginPersistence() {
        UserDefaults.standard.set(true, forKey: "vocamac.launchAtLogin")
        let (appState, _) = AppState.makeTestState()
        XCTAssertTrue(appState.launchAtLogin)
    }

    @MainActor
    func testSetLaunchAtLoginEnableUpdatesPreference() {
        let (appState, _) = AppState.makeTestState()
        XCTAssertFalse(appState.launchAtLogin)

        appState.setLaunchAtLogin(true)

        let expected = SMAppService.mainApp.status == .enabled
        XCTAssertEqual(appState.launchAtLogin, expected)
    }

    @MainActor
    func testSetLaunchAtLoginDisableUpdatesPreference() {
        let (appState, _) = AppState.makeTestState()
        appState.setLaunchAtLogin(true)
        appState.setLaunchAtLogin(false)

        let expected = SMAppService.mainApp.status == .enabled
        XCTAssertEqual(appState.launchAtLogin, expected)
    }

    @MainActor
    func testSetLaunchAtLoginToggleRoundTrip() {
        let (appState, _) = AppState.makeTestState()

        appState.setLaunchAtLogin(true)
        let afterEnable = appState.launchAtLogin

        appState.setLaunchAtLogin(false)
        let afterDisable = appState.launchAtLogin

        if SMAppService.mainApp.status != .enabled {
            XCTAssertFalse(afterDisable,
                "After disabling, launchAtLogin should be false")
        }
        XCTAssertNotNil(afterEnable)
        XCTAssertNotNil(afterDisable)
    }
}

// MARK: - AppState Onboarding Tests

final class AppStateOnboardingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearPersistedSettings()
    }

    override func tearDown() {
        clearPersistedSettings()
        super.tearDown()
    }

    private func clearPersistedSettings() {
        [
            "vocamac.hasCompletedOnboarding",
            "vocamac.activationMode",
            "vocamac.hotKeyCode",
            "vocamac.doubleTapThreshold",
            "vocamac.maxRecordingDuration",
        ].forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    @MainActor
    func testOnboardingFlagInitiallyFalse() {
        let (appState, _) = AppState.makeTestState()
        XCTAssertFalse(appState.hasCompletedOnboarding)
    }

    @MainActor
    func testCompleteOnboardingSetsFlagTrue() {
        let (appState, _) = AppState.makeTestState()
        XCTAssertFalse(appState.hasCompletedOnboarding)

        appState.completeOnboarding()

        XCTAssertTrue(appState.hasCompletedOnboarding)
    }

    @MainActor
    func testCompleteOnboardingSyncsHotKeyConfiguration() {
        let (appState, mocks) = AppState.makeTestState()
        appState.activationMode = .doubleTapToggle
        appState.hotKeyCode = 58
        appState.doubleTapThreshold = 0.55
        appState.maxRecordingDuration = 120

        appState.completeOnboarding()

        XCTAssertEqual(mocks.hotKeyManager.updateConfigurationCallCount, 1)
        XCTAssertEqual(mocks.hotKeyManager.lastMode, .doubleTapToggle)
        XCTAssertEqual(mocks.hotKeyManager.lastKeyCode, 58)
        XCTAssertEqual(mocks.hotKeyManager.lastDoubleTapThreshold, 0.55)
        XCTAssertEqual(mocks.hotKeyManager.lastSafetyTimeout, 125.0)
        XCTAssertEqual(mocks.hotKeyManager.resetKeyStateCallCount, 1)
    }

    @MainActor
    func testCompleteOnboardingDoesNotResetHotKeyStateWhileRecording() {
        let (appState, mocks) = AppState.makeTestState()
        appState.isRecording = true

        appState.completeOnboarding()

        XCTAssertEqual(mocks.hotKeyManager.updateConfigurationCallCount, 1)
        XCTAssertEqual(mocks.hotKeyManager.resetKeyStateCallCount, 0)
        XCTAssertTrue(appState.hasCompletedOnboarding)
    }

    @MainActor
    func testSyncHotKeyConfigurationAppliesCurrentSettings() {
        let (appState, mocks) = AppState.makeTestState()
        appState.activationMode = .doubleTapToggle
        appState.hotKeyCode = 54
        appState.doubleTapThreshold = 0.3
        appState.maxRecordingDuration = 30

        appState.syncHotKeyConfiguration()

        XCTAssertEqual(mocks.hotKeyManager.updateConfigurationCallCount, 1)
        XCTAssertEqual(mocks.hotKeyManager.lastMode, .doubleTapToggle)
        XCTAssertEqual(mocks.hotKeyManager.lastKeyCode, 54)
        XCTAssertEqual(mocks.hotKeyManager.lastDoubleTapThreshold, 0.3)
        XCTAssertEqual(mocks.hotKeyManager.lastSafetyTimeout, 35.0)
    }

    @MainActor
    func testSyncHotKeyConfigurationAppliesDefaultSettings() {
        let (appState, mocks) = AppState.makeTestState()

        appState.syncHotKeyConfiguration()

        XCTAssertEqual(mocks.hotKeyManager.updateConfigurationCallCount, 1)
        XCTAssertEqual(mocks.hotKeyManager.lastMode, .pushToTalk)
        XCTAssertEqual(mocks.hotKeyManager.lastKeyCode, 61)
        XCTAssertEqual(mocks.hotKeyManager.lastDoubleTapThreshold, 0.4)
        XCTAssertEqual(mocks.hotKeyManager.lastSafetyTimeout, 65.0)
    }

    @MainActor
    func testOnboardingFlagPersistence() {
        UserDefaults.standard.set(true, forKey: "vocamac.hasCompletedOnboarding")

        let (appState, _) = AppState.makeTestState()

        XCTAssertTrue(appState.hasCompletedOnboarding)
    }

}

// MARK: - AppState Endpoint Tests

final class AppStateEndpointTests: XCTestCase {

    @MainActor
    func testStartupLeavesEndpointUnconfiguredWithEmptyURL() async {
        let (appState, mocks) = AppState.makeTestState()

        await appState.performStartup()
        // Give the fire-and-forget reachability task a beat to run.
        await Task.yield()

        XCTAssertEqual(appState.endpointStatus, .unconfigured)
        XCTAssertEqual(mocks.transcriptionService.testConnectionCallCount, 0)
        // Hotkey listener should still start regardless of endpoint state.
        XCTAssertEqual(mocks.hotKeyManager.startListeningCallCount, 1)
    }

    @MainActor
    func testCheckEndpointReachabilitySuccess() async {
        let (appState, mocks) = AppState.makeTestState()
        appState.remoteEndpointURL = "http://192.168.1.10:8000"
        mocks.transcriptionService.testConnectionResult = .success("Connected · 0.2s")

        await appState.checkEndpointReachability()

        XCTAssertEqual(appState.endpointStatus, .reachable("Connected · 0.2s"))
        XCTAssertEqual(mocks.transcriptionService.testConnectionCallCount, 1)
    }

    @MainActor
    func testCheckEndpointReachabilityFailure() async {
        let (appState, mocks) = AppState.makeTestState()
        appState.remoteEndpointURL = "http://192.168.1.10:9999"
        mocks.transcriptionService.testConnectionResult = .failure(
            RemoteTranscriptionError.httpError(status: 401, body: "")
        )

        await appState.checkEndpointReachability()

        guard case .unreachable(let message) = appState.endpointStatus else {
            return XCTFail("Expected .unreachable, got \(appState.endpointStatus)")
        }
        XCTAssertTrue(message.contains("401"))
    }

    @MainActor
    func testRemoteEndpointSettingsRoundTrip() {
        let (appState, _) = AppState.makeTestState()
        XCTAssertEqual(appState.remoteEndpointURL, "")
        XCTAssertEqual(appState.remoteEndpointFormat, RemoteEndpointFormat.openAI.rawValue)
        XCTAssertEqual(appState.remoteAPIKey, "")
        XCTAssertEqual(appState.remoteModelName, "")

        appState.remoteEndpointURL = "http://myserver:8000"
        appState.remoteEndpointFormat = RemoteEndpointFormat.whisperCpp.rawValue
        appState.remoteAPIKey = "secret"
        appState.remoteModelName = "whisper-1"

        let config = RemoteEndpointConfiguration.fromUserDefaults()
        XCTAssertEqual(config.baseURL, "http://myserver:8000")
        XCTAssertEqual(config.format, .whisperCpp)
        XCTAssertEqual(config.apiKey, "secret")
        XCTAssertEqual(config.modelName, "whisper-1")

        // Clean up shared defaults for other tests.
        UserDefaults.standard.removeObject(forKey: RemoteEndpointConfiguration.urlKey)
        UserDefaults.standard.removeObject(forKey: RemoteEndpointConfiguration.formatKey)
        UserDefaults.standard.removeObject(forKey: RemoteEndpointConfiguration.apiKeyKey)
        UserDefaults.standard.removeObject(forKey: RemoteEndpointConfiguration.modelNameKey)
    }
}
