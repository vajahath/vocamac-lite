// MockServices.swift
// VocaMac Tests
//
// Mock implementations of service protocols for unit testing.
// These avoid triggering real system side effects (sounds, permissions, mic, etc.).

import Foundation
import Combine
@testable import VocaMac

// MARK: - MockAudioEngine

final class MockAudioEngine: AudioRecording {
    var isCurrentlyRecording = false
    var onAudioLevel: ((Float) -> Void)?
    var onSilenceDetected: (() -> Void)?
    var onMaxDurationReached: (() -> Void)?
    var onAudioDeviceChanged: (() -> Void)?

    var lastSilenceThreshold: Float?
    var lastSilenceDuration: Double?
    var lastMaxDuration: TimeInterval?
    var lastPreferredInputDeviceID: String?
    var stopRecordingResult: [Float] = []
    var forceResetCallCount = 0
    var startRecordingResult = true
    var startRecordingDelay: TimeInterval = 0

    private var permissionStatus: PermissionStatus = .granted

    @discardableResult
    func startRecording(
        silenceThreshold: Float,
        silenceDuration: Double,
        maxDuration: TimeInterval,
        preferredInputDeviceID: String?
    ) -> Bool {
        if startRecordingDelay > 0 {
            Thread.sleep(forTimeInterval: startRecordingDelay)
        }
        isCurrentlyRecording = startRecordingResult
        lastSilenceThreshold = silenceThreshold
        lastSilenceDuration = silenceDuration
        lastMaxDuration = maxDuration
        lastPreferredInputDeviceID = preferredInputDeviceID
        return startRecordingResult
    }

    @discardableResult
    func stopRecording() -> [Float] {
        isCurrentlyRecording = false
        return stopRecordingResult
    }

    func forceReset() {
        forceResetCallCount += 1
        isCurrentlyRecording = false
    }

    func checkPermissionStatus() -> PermissionStatus {
        permissionStatus
    }

    func setPermissionStatus(_ status: PermissionStatus) {
        permissionStatus = status
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        completion(permissionStatus == .granted)
    }
}

// MARK: - MockSoundManager

final class MockSoundManager: SoundPlaying {
    var volume: Float = 0.5
    var startSoundCallCount = 0
    var stopSoundCallCount = 0
    var startSoundAsyncCallCount = 0
    var stopSoundAsyncCallCount = 0

    func playStartSound() {
        startSoundCallCount += 1
    }

    func playStartSoundAsync() async {
        startSoundAsyncCallCount += 1
    }

    func playStopSound() {
        stopSoundCallCount += 1
    }

    func playStopSoundAsync() async {
        stopSoundAsyncCallCount += 1
    }
}

// MARK: - MockHotKeyManager

final class MockHotKeyManager: HotKeyMonitoring {
    var isListening = false
    var eventTap: CFMachPort? = nil
    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?

    var startListeningCallCount = 0
    var lastKeyCode: Int?
    var lastMode: ActivationMode?
    var lastDoubleTapThreshold: Double?
    var lastSafetyTimeout: Double?
    var resetKeyStateCallCount = 0
    var updateConfigurationCallCount = 0

    private var accessibilityPermission = false

    func checkAccessibilityPermission(prompt: Bool) -> Bool {
        accessibilityPermission
    }

    func setAccessibilityPermission(_ granted: Bool) {
        accessibilityPermission = granted
    }

    func startListening(keyCode: Int, mode: ActivationMode, doubleTapThreshold: Double, safetyTimeout: Double) {
        startListeningCallCount += 1
        lastKeyCode = keyCode
        lastMode = mode
        lastDoubleTapThreshold = doubleTapThreshold
        lastSafetyTimeout = safetyTimeout
        isListening = true
    }

    func stopListening() {
        isListening = false
    }

    func resetKeyState() {
        resetKeyStateCallCount += 1
    }

    func _updateConfiguration(keyCode: Int?, mode: ActivationMode?, doubleTapThreshold: Double?, safetyTimeout: Double?) {
        updateConfigurationCallCount += 1
        if let keyCode = keyCode {
            lastKeyCode = keyCode
        }
        if let mode = mode {
            lastMode = mode
        }
        if let doubleTapThreshold = doubleTapThreshold {
            lastDoubleTapThreshold = doubleTapThreshold
        }
        if let safetyTimeout = safetyTimeout {
            lastSafetyTimeout = safetyTimeout
        }
    }
}

// MARK: - MockPermissionManager

@MainActor
final class MockPermissionManager: ObservableObject, PermissionManaging {
    @Published var micPermission: PermissionStatus = .granted
    @Published var accessibilityPermission: PermissionStatus = .granted
    @Published var inputMonitoringPermission: PermissionStatus = .granted
    var onAllPermissionsGranted: (() -> Void)?

    var checkPermissionsCallCount = 0
    var startPollingCallCount = 0
    var stopPollingCallCount = 0
    var requestMicPermissionCallCount = 0
    var openMicSettingsCallCount = 0
    var requestAccessibilityCallCount = 0
    var requestInputMonitoringCallCount = 0

    var objectWillChangePublisher: AnyPublisher<Void, Never> {
        objectWillChange.eraseToAnyPublisher()
    }

    var allPermissionsGranted: Bool {
        micPermission == .granted &&
        accessibilityPermission == .granted &&
        inputMonitoringPermission == .granted
    }

    func checkPermissions() {
        checkPermissionsCallCount += 1
    }

    func startPermissionPolling() {
        startPollingCallCount += 1
    }

    func stopPermissionPolling() {
        stopPollingCallCount += 1
    }

    func requestMicrophonePermission() {
        requestMicPermissionCallCount += 1
    }

    func openMicrophoneSettings() {
        openMicSettingsCallCount += 1
    }

    func requestAccessibilityPermission() {
        requestAccessibilityCallCount += 1
    }

    func requestInputMonitoringPermission() {
        requestInputMonitoringCallCount += 1
    }
}

// MARK: - MockCursorOverlay

@MainActor
final class MockCursorOverlay: CursorOverlayManaging {
    var showCallCount = 0
    var hideCallCount = 0
    var transitionCallCount = 0
    var lastAudioLevel: Float?

    func show() {
        showCallCount += 1
    }

    func hide() {
        hideCallCount += 1
    }

    func transitionToProcessing() {
        transitionCallCount += 1
    }

    func updateAudioLevel(_ level: Float) {
        lastAudioLevel = level
    }
}

// MARK: - MockTranscriptionService

final class MockTranscriptionService: SpeechTranscribing {
    var lastTranscribedAudioData: [Float]?
    var lastLanguage: String?
    var lastTranslate: Bool?
    var lastVocabulary: String?
    var mockTranscriptionResult: VocaTranscription = VocaTranscription(text: "mock transcription", duration: 1.0, detectedLanguage: "en", audioLengthSeconds: 1.0, modelUsed: "remote")
    var shouldThrow = false

    var testConnectionCallCount = 0
    var testConnectionResult: Result<String, Error> = .success("Connected · 0.1s")

    func transcribe(audioData: [Float], language: String?, translate: Bool, vocabulary: String) async throws -> VocaTranscription {
        lastTranscribedAudioData = audioData
        lastLanguage = language
        lastTranslate = translate
        lastVocabulary = vocabulary
        if shouldThrow {
            throw RemoteTranscriptionError.httpError(status: 500, body: "mock error")
        }
        return mockTranscriptionResult
    }

    func testConnection() async throws -> String {
        testConnectionCallCount += 1
        return try testConnectionResult.get()
    }
}

// MARK: - MockTextInjector

final class MockTextInjector: TextInjecting {
    var injectCallCount = 0
    var lastInjectedText: String?
    var lastPreserveClipboard: Bool?

    func inject(text: String, preserveClipboard: Bool) {
        injectCallCount += 1
        lastInjectedText = text
        lastPreserveClipboard = preserveClipboard
    }
}

// MARK: - MockStatsManager

@MainActor
final class MockStatsManager: StatsManaging, ObservableObject {
    @Published var stats: UserStats = UserStats()

    var recordCallCount = 0
    var resetCallCount = 0

    var objectWillChangePublisher: AnyPublisher<Void, Never> {
        objectWillChange.eraseToAnyPublisher()
    }

    func recordTranscription(_ transcription: VocaTranscription) {
        recordCallCount += 1
    }

    func resetStats() {
        resetCallCount += 1
    }
}

// MARK: - Test Helper

extension AppState {
    @MainActor
    static func makeTestState(
        transcriptionService: MockTranscriptionService = MockTranscriptionService()
    ) -> (appState: AppState, mocks: TestMocks) {
        UserDefaults.standard.removeObject(forKey: "vocamac.selectedAudioDeviceID")
        UserDefaults.standard.removeObject(forKey: "vocamac.selectedAudioDeviceName")
        UserDefaults.standard.removeObject(forKey: RemoteEndpointConfiguration.urlKey)
        UserDefaults.standard.removeObject(forKey: RemoteEndpointConfiguration.formatKey)
        UserDefaults.standard.removeObject(forKey: RemoteEndpointConfiguration.apiKeyKey)
        UserDefaults.standard.removeObject(forKey: RemoteEndpointConfiguration.modelNameKey)

        let audioEngine = MockAudioEngine()
        let soundManager = MockSoundManager()
        let hotKeyManager = MockHotKeyManager()
        let permissionManager = MockPermissionManager()
        let cursorOverlay = MockCursorOverlay()
        let textInjector = MockTextInjector()
        let statsManager = MockStatsManager()

        let mocks = TestMocks(
            audioEngine: audioEngine,
            soundManager: soundManager,
            hotKeyManager: hotKeyManager,
            permissionManager: permissionManager,
            cursorOverlay: cursorOverlay,
            transcriptionService: transcriptionService,
            textInjector: textInjector,
            statsManager: statsManager
        )
        let appState = AppState(
            audioEngine: audioEngine,
            transcriptionService: transcriptionService,
            textInjector: textInjector,
            hotKeyManager: hotKeyManager,
            soundManager: soundManager,
            cursorOverlay: cursorOverlay,
            statsManager: statsManager,
            permissionManager: permissionManager,
            skipSystemIntegration: true
        )
        return (appState, mocks)
    }
}

struct TestMocks {
    let audioEngine: MockAudioEngine
    let soundManager: MockSoundManager
    let hotKeyManager: MockHotKeyManager
    let permissionManager: MockPermissionManager
    let cursorOverlay: MockCursorOverlay
    let transcriptionService: MockTranscriptionService
    let textInjector: MockTextInjector
    let statsManager: MockStatsManager
}
