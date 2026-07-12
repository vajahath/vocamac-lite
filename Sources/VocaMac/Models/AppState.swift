// AppState.swift
// VocaMac Lite
//
// Central observable state for the entire application.
// All UI and services react to changes in AppState.

import Foundation
import SwiftUI
import Combine
import ServiceManagement

// MARK: - Enums

/// Application status representing the current state of the transcription pipeline
enum AppStatus: String {
    case idle          // Ready for input, not recording
    case recording     // Actively capturing microphone audio
    case processing    // Transcribing audio via the remote endpoint
    case error         // Something went wrong
}

/// How recording is activated by the user
enum ActivationMode: String, CaseIterable, Codable, Identifiable {
    case pushToTalk       // Hold key to record, release to stop
    case doubleTapToggle  // Double-tap key to start/stop

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pushToTalk:      return "Push to Talk (Hold)"
        case .doubleTapToggle: return "Double-Tap Toggle"
        }
    }

    var description: String {
        switch self {
        case .pushToTalk:
            return "Hold the hotkey to record. Release to stop and transcribe."
        case .doubleTapToggle:
            return "Double-tap the hotkey to start recording. Double-tap again to stop."
        }
    }
}

/// Permission status for system permissions
enum PermissionStatus: String {
    case notDetermined
    case granted
    case denied
}

/// Reachability of the configured remote transcription endpoint
enum EndpointStatus: Equatable {
    case unconfigured
    case checking
    case reachable(String)      // human-readable summary, e.g. "Connected · 0.4s"
    case unreachable(String)    // error description
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published State

    /// Current application status
    @Published var appStatus: AppStatus = .idle

    /// Whether the app is actively recording audio
    @Published var isRecording: Bool = false

    /// Current audio input level (0.0 - 1.0) for visual feedback
    @Published var audioLevel: Float = 0.0

    /// The most recent transcription result
    @Published var lastTranscription: VocaTranscription?

    /// Error message to display, if any
    @Published var errorMessage: String?

    /// Reachability of the configured remote transcription endpoint
    @Published var endpointStatus: EndpointStatus = .unconfigured

    // Permissions are managed by PermissionManager.
    // These computed properties maintain backward compatibility for views.
    var micPermission: PermissionStatus { permissionManager.micPermission }
    var accessibilityPermission: PermissionStatus { permissionManager.accessibilityPermission }
    var inputMonitoringPermission: PermissionStatus { permissionManager.inputMonitoringPermission }

    /// Detected system capabilities
    @Published var systemCapabilities: SystemCapabilities?

    // MARK: - User Settings (persisted via UserDefaults)

    @AppStorage("vocamac.hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("vocamac.activationMode") var activationMode: ActivationMode = .pushToTalk
    @AppStorage("vocamac.hotKeyCode") var hotKeyCode: Int = 61  // Right Option
    @AppStorage("vocamac.doubleTapThreshold") var doubleTapThreshold: Double = 0.4
    @AppStorage("vocamac.silenceThreshold") var silenceThreshold: Double = 0.01
    @AppStorage("vocamac.silenceDuration") var silenceDuration: Double = 2.0
    @AppStorage("vocamac.maxRecordingDuration") var maxRecordingDuration: Int = 60
    @AppStorage("vocamac.selectedAudioDeviceID") var selectedAudioDeviceID: String = ""
    @AppStorage("vocamac.selectedAudioDeviceName") var selectedAudioDeviceName: String = ""
    @AppStorage("vocamac.selectedLanguage") var selectedLanguage: String = "auto"
    @AppStorage("vocamac.launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("vocamac.preserveClipboard") var preserveClipboard: Bool = true
    @AppStorage("vocamac.soundEffectsEnabled") var soundEffectsEnabled: Bool = true
    @AppStorage("vocamac.translationEnabled") var translationEnabled: Bool = false
    @AppStorage("vocamac.customVocabulary") var customVocabulary: String = ""
    @AppStorage("vocamac.logLevel") var logLevel: String = "info"

    // Remote endpoint settings. The API key is stored in UserDefaults
    // (plaintext on disk) — acceptable for a lean personal tool; the
    // settings UI notes this tradeoff.
    @AppStorage(RemoteEndpointConfiguration.urlKey) var remoteEndpointURL: String = ""
    @AppStorage(RemoteEndpointConfiguration.formatKey) var remoteEndpointFormat: String = RemoteEndpointFormat.openAI.rawValue
    @AppStorage(RemoteEndpointConfiguration.apiKeyKey) var remoteAPIKey: String = ""
    @AppStorage(RemoteEndpointConfiguration.modelNameKey) var remoteModelName: String = ""

    private var hotKeySafetyTimeout: Double {
        Double(maxRecordingDuration) + 5.0
    }

    // MARK: - Services

    let audioEngine: AudioRecording
    let transcriptionService: SpeechTranscribing
    let textInjector: TextInjecting
    let hotKeyManager: HotKeyMonitoring
    let soundManager: SoundPlaying
    let statsManager: StatsManaging
    let updateChecker = UpdateChecker()
    let permissionManager: any PermissionManaging

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false

    /// AudioEngine serializes its own lifecycle internally; this wrapper makes
    /// the intentional background handoff explicit for Dispatch's @Sendable API.
    private struct AudioEngineWorker: @unchecked Sendable {
        let audioEngine: AudioRecording

        func startRecording(
            silenceThreshold: Float,
            silenceDuration: Double,
            maxDuration: TimeInterval,
            preferredInputDeviceID: String?
        ) -> Bool {
            audioEngine.startRecording(
                silenceThreshold: silenceThreshold,
                silenceDuration: silenceDuration,
                maxDuration: maxDuration,
                preferredInputDeviceID: preferredInputDeviceID
            )
        }

        func stopRecording() -> [Float] {
            audioEngine.stopRecording()
        }
    }

    /// Process-level flag that prevents performStartup from running more than
    /// once even when SwiftUI instantiates multiple AppState objects (which it
    /// does during MenuBarExtra scene setup). Instance-level `hasStarted` guards
    /// re-entry on the same object; this static flag guards across all instances.
    ///
    /// Internal (not private) so test teardown can reset it between test cases.
    static var hasStartedGlobally = false

    /// Whether to skip system integration calls (SMAppService, etc.) during init.
    /// Set to `true` in tests to avoid side effects.
    let skipSystemIntegration: Bool

    // MARK: - Initialization

    init(
        audioEngine: AudioRecording = AudioEngine(),
        transcriptionService: SpeechTranscribing = RemoteTranscriptionService(),
        textInjector: TextInjecting = TextInjector(),
        hotKeyManager: HotKeyMonitoring = HotKeyManager(),
        soundManager: SoundPlaying = SoundManager(),
        statsManager: StatsManaging,
        permissionManager: (any PermissionManaging)? = nil,
        skipSystemIntegration: Bool = false
    ) {
        self.audioEngine = audioEngine
        self.transcriptionService = transcriptionService
        self.textInjector = textInjector
        self.hotKeyManager = hotKeyManager
        self.soundManager = soundManager
        self.statsManager = statsManager
        self.permissionManager = permissionManager ?? PermissionManager(audioEngine: audioEngine, hotKeyManager: hotKeyManager)
        self.skipSystemIntegration = skipSystemIntegration

        VocaLogger.info(.appState, "Initializing... id=\(ObjectIdentifier(self))")
        if !skipSystemIntegration {
            syncLaunchAtLogin()
        }
        setupServices()

        // Forward updateChecker changes so SwiftUI views observing AppState
        // re-render when updateState changes (nested ObservableObject fix).
        updateChecker.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Forward statsManager changes
        statsManager.objectWillChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    /// Single production AppState instance for the process.
    ///
    /// SwiftUI can recreate the `App` value during scene setup, especially for
    /// menu bar apps. Keeping the production instance outside the `App` value's
    /// stored-property initialization prevents duplicate service graphs, event
    /// taps, audio observers, and stale SwiftUI environment objects.
    @MainActor
    private static let sharedProductionInstance = AppState(
        statsManager: StatsManager()
    )

    /// Convenience factory for creating AppState with all real services.
    /// Needed because StatsManager is @MainActor and can't be a default parameter.
    @MainActor
    static func production() -> AppState {
        VocaLogger.debug(.appState, "Using production AppState id=\(ObjectIdentifier(sharedProductionInstance))")
        return sharedProductionInstance
    }

    /// Called once from the SwiftUI lifecycle to complete initialization.
    /// Safe to call multiple times and across multiple instances — only the
    /// first call across the entire process takes effect.
    func triggerStartupIfNeeded() {
        guard !hasStarted, !AppState.hasStartedGlobally else {
            VocaLogger.debug(.appState, "triggerStartupIfNeeded called again — skipping (already started)")
            return
        }
        hasStarted = true
        AppState.hasStartedGlobally = true
        Task {
            await performStartup()
        }
    }

    // MARK: - Launch at Login

    /// Sync the persisted launchAtLogin preference with SMAppService.
    /// Called once on init to reconcile state (e.g. if the user toggled it
    /// in System Settings directly, or if the app was re-installed).
    private func syncLaunchAtLogin() {
        let currentStatus = SMAppService.mainApp.status
        let isRegistered = currentStatus == .enabled

        if launchAtLogin && !isRegistered {
            // User wants launch-at-login but it's not registered — register now
            setLaunchAtLogin(true)
        } else if !launchAtLogin && isRegistered {
            // Persisted preference says disabled but system says enabled — unregister
            setLaunchAtLogin(false)
        }
    }

    /// Register or unregister the app as a login item via SMAppService.
    /// Updates the persisted `launchAtLogin` preference to match.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                VocaLogger.info(.appState, "Registered as login item")
            } else {
                try SMAppService.mainApp.unregister()
                VocaLogger.info(.appState, "Unregistered as login item")
            }
            launchAtLogin = enabled
        } catch {
            VocaLogger.error(.appState, "Failed to \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)")
            // Revert the preference to match the actual system state
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Setup

    private func setupServices() {
        // Detect system capabilities
        systemCapabilities = SystemInfo.detect()

        // Setup audio level reporting
        audioEngine.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
            }
        }

        // Setup silence detection callback
        audioEngine.onSilenceDetected = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                if self.activationMode == .doubleTapToggle && self.isRecording {
                    VocaLogger.info(.appState, "Silence detected — auto-stopping recording (double-tap mode)")
                    await self.stopRecordingAndTranscribe()
                }
            }
        }

        // Setup max recording duration callback.
        // AudioEngine fires this when the recording reaches maxRecordingDuration.
        // This is the primary duration limit — the HotKeyManager safety timer
        // (maxRecordingDuration + 5s) acts as a backstop in case this callback
        // fails or the key-up event is lost entirely.
        audioEngine.onMaxDurationReached = { [weak self] in
            Task { @MainActor in
                guard let self = self, self.isRecording else { return }
                VocaLogger.info(.appState, "Max recording duration (\(self.maxRecordingDuration)s) reached — auto-stopping")
                await self.stopRecordingAndTranscribe()
            }
        }

        // Setup audio device change callback.
        // Fires when the microphone is unplugged/replugged, Bluetooth disconnects,
        // or the default audio device changes (e.g., after sleep). AudioEngine has
        // already stopped and reset itself — we just need to recover the app state.
        audioEngine.onAudioDeviceChanged = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                VocaLogger.warning(.appState, "Audio device changed — recovering from interrupted recording")
                self.isRecording = false
                self.audioLevel = 0.0
                self.hotKeyManager.resetKeyState()
                self.appStatus = .idle
                self.errorMessage = nil
            }
        }

        // Setup hotkey callbacks
        hotKeyManager.onRecordingStart = { [weak self] in
            Task { @MainActor in
                await self?.startRecording()
            }
        }

        hotKeyManager.onRecordingStop = { [weak self] in
            Task { @MainActor in
                await self?.stopRecordingAndTranscribe()
            }
        }

        // Wire permission manager: start hotkey listener when permissions granted
        permissionManager.onAllPermissionsGranted = { [weak self] in
            guard let self = self else { return }
            self.hotKeyManager.startListening(
                keyCode: self.hotKeyCode,
                mode: self.activationMode,
                doubleTapThreshold: self.doubleTapThreshold,
                safetyTimeout: self.hotKeySafetyTimeout
            )
            VocaLogger.info(.appState, "Hotkey listener started after permission grant")
        }

        // Forward PermissionManager state changes to trigger SwiftUI updates
        permissionManager.objectWillChangePublisher
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Check permissions
        checkPermissions()
    }

    // MARK: - Endpoint Reachability

    /// Automatic/background reachability check: a cheap `GET /health` liveness
    /// probe. Used at startup and wherever the status just needs to reflect
    /// whether the server is up. Non-blocking callers should wrap this in a Task.
    func checkEndpointReachability() async {
        await probeEndpoint { try await self.transcriptionService.checkHealth() }
    }

    /// Explicit "Test Connection" action: sends a short silent clip through the
    /// real transcription path to validate URL, format, auth, and multipart
    /// handling — more thorough (and costlier) than the liveness check.
    func testEndpointConnection() async {
        await probeEndpoint { try await self.transcriptionService.testConnection() }
    }

    /// Shared driver for both endpoint checks: guards on configuration, flips to
    /// `.checking`, then records the reachable/unreachable outcome.
    private func probeEndpoint(_ probe: () async throws -> String) async {
        guard !remoteEndpointURL.trimmingCharacters(in: .whitespaces).isEmpty else {
            endpointStatus = .unconfigured
            return
        }
        endpointStatus = .checking
        do {
            let summary = try await probe()
            endpointStatus = .reachable(summary)
            VocaLogger.info(.appState, "Endpoint reachable: \(summary)")
        } catch {
            endpointStatus = .unreachable(error.localizedDescription)
            VocaLogger.warning(.appState, "Endpoint unreachable: \(error.localizedDescription)")
        }
    }

    // MARK: - Permission Handling (delegated to PermissionManager)

    func checkPermissions() { permissionManager.checkPermissions() }
    func startPermissionPolling() { permissionManager.startPermissionPolling() }
    func stopPermissionPolling() { permissionManager.stopPermissionPolling() }
    var allPermissionsGranted: Bool { permissionManager.allPermissionsGranted }
    func requestMicrophonePermission() { permissionManager.requestMicrophonePermission() }
    func openMicrophoneSettings() { permissionManager.openMicrophoneSettings() }
    func requestAccessibilityPermission() { permissionManager.requestAccessibilityPermission() }
    func requestInputMonitoringPermission() { permissionManager.requestInputMonitoringPermission() }

    // MARK: - Hotkey Configuration

    /// Apply persisted hotkey settings to the active listener.
    /// `@AppStorage` updates save preferences immediately, but an already-running
    /// event tap also needs its in-memory configuration refreshed.
    func syncHotKeyConfiguration() {
        hotKeyManager.updateConfiguration(
            keyCode: hotKeyCode,
            mode: activationMode,
            doubleTapThreshold: doubleTapThreshold,
            safetyTimeout: hotKeySafetyTimeout
        )
        VocaLogger.debug(.appState, "Hotkey configuration synced (keyCode=\(hotKeyCode), mode=\(activationMode.rawValue))")
    }

    // MARK: - Force Recovery

    /// Forcibly reset the entire recording pipeline to idle state.
    /// This is a last-resort recovery mechanism callable from the menu bar UI.
    /// It unconditionally resets the audio engine, hotkey state, cursor overlay,
    /// and all published state back to idle.
    func forceRecovery() {
        VocaLogger.warning(.appState, "Force recovery: resetting all state to idle (was appStatus=\(appStatus.rawValue), isRecording=\(isRecording))")

        // Reset audio engine unconditionally
        audioEngine.forceReset()

        // Reset hotkey tracking state
        hotKeyManager.resetKeyState()

        // Reset UI state
        isRecording = false
        audioLevel = 0.0
        appStatus = .idle
        errorMessage = nil
    }

    // MARK: - Recording Flow

    func startRecording() async {
        // If we're already recording, this is a recovery attempt — the user
        // pressed the hotkey again because a previous key-up was missed.
        // Stop the current recording and transcribe what we have.
        if appStatus == .recording || isRecording {
            VocaLogger.warning(.appState, "startRecording called while already recording — treating as stop (recovery)")
            await stopRecordingAndTranscribe()
            return
        }

        guard appStatus == .idle else {
            // If stuck in .processing or .error for too long, force recovery
            // so the user can start a fresh recording.
            if appStatus == .error || appStatus == .processing {
                VocaLogger.warning(.appState, "startRecording called in \(appStatus.rawValue) state — force recovering to allow new recording")
                forceRecovery()
                // Don't start recording in the same call — let the user press again
                return
            }
            VocaLogger.warning(.appState, "startRecording called in non-idle state: \(appStatus.rawValue) — ignoring")
            return
        }
        guard micPermission == .granted else {
            errorMessage = "Microphone permission is required. Please grant access in System Settings."
            appStatus = .error
            return
        }

        appStatus = .recording
        isRecording = true
        errorMessage = nil

        // Start recording immediately for instant responsiveness.
        // The start sound is played concurrently — any brief bleed into the
        // mic buffer is negligible and handled well by Whisper's noise model.
        let didStartRecording = await startAudioEngine(
            silenceThreshold: Float(silenceThreshold),
            silenceDuration: silenceDuration,
            maxDuration: TimeInterval(maxRecordingDuration),
            preferredInputDeviceID: selectedAudioDeviceID.isEmpty ? nil : selectedAudioDeviceID
        )

        guard didStartRecording else {
            VocaLogger.warning(.appState, "Audio engine failed to start — resetting recording state")
            isRecording = false
            audioLevel = 0.0
            hotKeyManager.resetKeyState()
            appStatus = .idle
            return
        }

        // Play start sound after mic is active (fire-and-forget)
        if soundEffectsEnabled && isRecording && appStatus == .recording {
            soundManager.playStartSound()
        }
    }

    func stopRecordingAndTranscribe() async {
        // Accept stop if we're recording OR if the audio engine thinks
        // it's recording (covers stuck-state recovery scenarios where
        // isRecording and appStatus may be out of sync).
        guard isRecording || appStatus == .recording else { return }

        let audioData = await stopAudioEngine()
        isRecording = false
        audioLevel = 0.0

        // Play stop sound
        if soundEffectsEnabled {
            soundManager.playStopSound()
        }

        guard !audioData.isEmpty else {
            appStatus = .idle
            return
        }

        appStatus = .processing

        do {
            let language = selectedLanguage == "auto" ? nil : selectedLanguage
            let result = try await transcriptionService.transcribe(
                audioData: audioData,
                language: language,
                translate: translationEnabled,
                vocabulary: customVocabulary
            )

            lastTranscription = result

            // Update stats
            statsManager.recordTranscription(result)

            // Inject text at cursor position (the service already removed
            // hallucination tokens like [BLANK_AUDIO])
            let trimmedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                textInjector.inject(
                    text: trimmedText,
                    preserveClipboard: preserveClipboard
                )
            } else {
                VocaLogger.info(.appState, "Transcription produced no usable text (silence or blank audio)")
            }

            appStatus = .idle
        } catch {
            errorMessage = "Transcription failed: \(error.localizedDescription)"
            appStatus = .error

            // Auto-recover after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                if self?.appStatus == .error {
                    self?.appStatus = .idle
                    self?.errorMessage = nil
                }
            }
        }
    }

    private func startAudioEngine(
        silenceThreshold: Float,
        silenceDuration: Double,
        maxDuration: TimeInterval,
        preferredInputDeviceID: String?
    ) async -> Bool {
        let worker = AudioEngineWorker(audioEngine: audioEngine)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let didStart = worker.startRecording(
                    silenceThreshold: silenceThreshold,
                    silenceDuration: silenceDuration,
                    maxDuration: maxDuration,
                    preferredInputDeviceID: preferredInputDeviceID
                )
                continuation.resume(returning: didStart)
            }
        }
    }

    private func stopAudioEngine() async -> [Float] {
        let worker = AudioEngineWorker(audioEngine: audioEngine)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: worker.stopRecording())
            }
        }
    }

    // MARK: - Startup

    func performStartup() async {
        VocaLogger.info(.appState, "performStartup beginning...")

        // 1. Detect hardware
        systemCapabilities = SystemInfo.detect()
        let sysInfo = systemCapabilities
        VocaLogger.info(.appState, "System: \(sysInfo?.processorName ?? "unknown") | \(sysInfo?.physicalMemoryGB ?? 0) GB RAM | \(sysInfo?.coreCount ?? 0) cores")

        // 2. Check/request permissions
        checkPermissions()
        VocaLogger.info(.appState, "Mic permission: \(micPermission.rawValue) | Accessibility: \(accessibilityPermission.rawValue) | Input Monitoring: \(inputMonitoringPermission.rawValue)")

        // Auto-prompt for microphone permission on first launch
        if micPermission == .notDetermined {
            VocaLogger.info(.appState, "Mic permission not determined — requesting...")
            requestMicrophonePermission()
        }

        // Start polling if any permission is still missing
        startPermissionPolling()

        // 3. Probe the remote endpoint in the background. Never blocks startup:
        // the app must be instantly usable at login, and there's no local model
        // to load into memory.
        Task { [weak self] in
            await self?.checkEndpointReachability()
        }

        // 4. Always attempt to start hotkey listener
        // The event tap creation itself will fail if permissions aren't granted,
        // and we handle that gracefully in HotKeyManager.
        VocaLogger.info(.appState, "Attempting to start hotkey listener...")
        hotKeyManager.startListening(
            keyCode: hotKeyCode,
            mode: activationMode,
            doubleTapThreshold: doubleTapThreshold,
            safetyTimeout: hotKeySafetyTimeout
        )
        if hotKeyManager.isListening {
            VocaLogger.info(.appState, "Hotkey listener active (keyCode=\(hotKeyCode), mode=\(activationMode.rawValue))")
        } else {
            VocaLogger.warning(.appState, "Hotkey listener failed to start. Check Accessibility & Input Monitoring permissions.")
        }

        await updateChecker.checkOnLaunchIfNeeded()

        VocaLogger.info(.appState, "Startup complete!")
    }
    func completeOnboarding() {
        syncHotKeyConfiguration()
        if !isRecording {
            hotKeyManager.resetKeyState()
        }
        hasCompletedOnboarding = true
        VocaLogger.info(.appState, "Onboarding completed")
    }
}
