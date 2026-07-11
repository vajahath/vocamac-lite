// SettingsView.swift
// VocaMac
//
// Settings window for VocaMac configuration.
// Organized into tabs: General, Endpoint, Stats, Audio, Debug, About.

import SwiftUI

extension Notification.Name {
    static let showOnboarding = Notification.Name("com.vocamac.showOnboarding")
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            EndpointSettingsTab()
                .tabItem {
                    Label("Endpoint", systemImage: "network")
                }

            StatsSettingsTab()
                .tabItem {
                    Label("Stats", systemImage: "chart.xyaxis.line")
                }

            AudioSettingsTab()
                .tabItem {
                    Label("Audio", systemImage: "waveform")
                }

            DebugTab()
                .tabItem {
                    Label("Debug", systemImage: "ladybug")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 560, height: 520)
    }
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            // Activation Mode
            Section("Activation Mode") {
                Picker("Mode", selection: $appState.activationMode) {
                    ForEach(ActivationMode.allCases) { mode in
                        VStack(alignment: .leading) {
                            Text(mode.displayName)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appState.activationMode) { _ in
                    appState.syncHotKeyConfiguration()
                }

                Text(appState.activationMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Hotkey
            Section("Hotkey") {
                HotKeySelectionControl(
                    pickerLabel: "Activation Key",
                    footerText: "Choose a preset or record a key. VocaMac reserves this key while running."
                )

                if appState.activationMode == .doubleTapToggle {
                    HStack {
                        Text("Double-tap speed")
                        Slider(
                            value: $appState.doubleTapThreshold,
                            in: 0.2...0.8,
                            step: 0.05,
                            onEditingChanged: { isEditing in
                                if !isEditing {
                                    appState.syncHotKeyConfiguration()
                                }
                            }
                        )
                        Text("\(String(format: "%.2f", appState.doubleTapThreshold))s")
                            .monospacedDigit()
                            .frame(width: 40)
                    }

                    Text("Shorter = faster double-tap required. Longer = more forgiving.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Language
            Section("Transcription Language") {
                Picker("Language", selection: $appState.selectedLanguage) {
                    Text("Auto-detect").tag("auto")
                    Divider()
                    Group {
                        Text("English").tag("en")
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                        Text("Italian").tag("it")
                        Text("Portuguese").tag("pt")
                        Text("Dutch").tag("nl")
                    }
                    Divider()
                    Group {
                        Text("Chinese").tag("zh")
                        Text("Japanese").tag("ja")
                        Text("Korean").tag("ko")
                        Text("Hindi").tag("hi")
                        Text("Arabic").tag("ar")
                        Text("Russian").tag("ru")
                        Text("Turkish").tag("tr")
                        Text("Polish").tag("pl")
                        Text("Swedish").tag("sv")
                        Text("Ukrainian").tag("uk")
                    }
                }

                Text("Auto-detect works well for most cases. Set a specific language for better accuracy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Translation
            Section("Translation") {
                Toggle("Enable translation", isOn: $appState.translationEnabled)

                Text(appState.translationEnabled
                    ? "Speech will be translated to the selected language (or English if Auto-detect)."
                    : "Speech will be transcribed as-is in the spoken language. The language setting is used as a recognition hint only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Custom Vocabulary
            Section("Custom Vocabulary") {
                TextEditor(text: $appState.customVocabulary)
                    .font(.body)
                    .frame(minHeight: 90)
                    .overlay(alignment: .topLeading) {
                        if appState.customVocabulary.isEmpty {
                            Text("kubectl, PostgreSQL, nginx, Grafana")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }

                let count = RemoteTranscriptionService.vocabularyTerms(from: appState.customVocabulary).count
                Text(count == 0
                    ? "Add names, jargon, or proper nouns (one per line, or comma-separated) that get mis-transcribed. VocaMac hints these to the model so it spells them right."
                    : "\(count) term\(count == 1 ? "" : "s"). Keep the list short, since the model can only use the first 50 to 100 words as a hint.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("For best results, enter terms in the language you dictate and set a matching Transcription Language above. In Auto-detect, the terms can also nudge which language VocaMac picks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: { appState.setLaunchAtLogin($0) }
                ))

                Toggle("Preserve clipboard after text injection", isOn: $appState.preserveClipboard)

                Toggle("Show mic indicator near cursor while recording", isOn: $appState.showCursorIndicator)

                Text("When enabled, your clipboard contents are restored after injecting text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let name: String
    let icon: String
    let status: PermissionStatus
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 16)
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(name)
            Spacer()
            switch status {
            case .granted:
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .notDetermined:
                Button("Grant") { action() }
                    .controlSize(.small)
            case .denied:
                Button("Open Settings") { action() }
                    .controlSize(.small)
            }
        }
    }

    private var statusIcon: String {
        switch status {
        case .granted: return "checkmark.circle.fill"
        case .notDetermined: return "questionmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted: return .green
        case .notDetermined: return .orange
        case .denied: return .red
        }
    }
}

// MARK: - Endpoint Settings

struct EndpointSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Transcription Server") {
                TextField("Server URL", text: $appState.remoteEndpointURL, prompt: Text("http://192.168.1.10:8000"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                Picker("API format", selection: $appState.remoteEndpointFormat) {
                    ForEach(RemoteEndpointFormat.allCases) { format in
                        Text(format.displayName).tag(format.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(selectedFormat.detailDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Audio is recorded on this Mac (16 kHz mono WAV) and uploaded to this server for transcription. Nothing is transcribed locally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Authentication (optional)") {
                SecureField("API key", text: $appState.remoteAPIKey)
                    .textFieldStyle(.roundedBorder)

                Text("Sent as a Bearer token. Stored unencrypted in app preferences — use HTTPS and a key when the server is outside your trusted network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Model (optional)") {
                TextField("Model name", text: $appState.remoteModelName, prompt: Text("Systran/faster-whisper-small"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                Text("Sent as the \"model\" field for OpenAI-compatible servers. Leave empty to use the server's default model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Connection") {
                HStack {
                    Button("Test Connection") {
                        Task { @MainActor in
                            await appState.checkEndpointReachability()
                        }
                    }
                    .disabled(appState.remoteEndpointURL.trimmingCharacters(in: .whitespaces).isEmpty
                              || appState.endpointStatus == .checking)

                    Spacer()

                    EndpointStatusView(status: appState.endpointStatus)
                }

                Text("Sends a short silent clip through the real transcription path to verify URL, format, and API key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var selectedFormat: RemoteEndpointFormat {
        RemoteEndpointFormat(rawValue: appState.remoteEndpointFormat) ?? .openAI
    }
}

/// Compact status row for the endpoint reachability state.
struct EndpointStatusView: View {
    let status: EndpointStatus

    var body: some View {
        HStack(spacing: 6) {
            switch status {
            case .unconfigured:
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.secondary)
                Text("Not configured")
                    .foregroundStyle(.secondary)
            case .checking:
                ProgressView()
                    .controlSize(.small)
                Text("Checking…")
                    .foregroundStyle(.secondary)
            case .reachable(let summary):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(summary)
                    .foregroundStyle(.green)
            case .unreachable(let message):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .help(message)
            }
        }
        .font(.caption)
    }
}

// MARK: - Audio Settings

struct AudioSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var audioDevices: [AudioDevice] = []

    var body: some View {
        Form {
            Section("Recording") {
                Picker("Max recording duration", selection: $appState.maxRecordingDuration) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                    Text("120 seconds").tag(120)
                    Text("300 seconds (5 min)").tag(300)
                }
                .onChange(of: appState.maxRecordingDuration) { _ in
                    appState.syncHotKeyConfiguration()
                }

                Text("Recording will automatically stop after this duration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Silence Detection") {
                HStack {
                    Text("Sensitivity")
                    Slider(
                        value: $appState.silenceThreshold,
                        in: 0.001...0.05,
                        step: 0.001
                    )
                    Text(sensitivityLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }

                HStack {
                    Text("Auto-stop after silence")
                    Slider(
                        value: $appState.silenceDuration,
                        in: 0.5...5.0,
                        step: 0.5
                    )
                    Text("\(String(format: "%.1f", appState.silenceDuration))s")
                        .monospacedDigit()
                        .frame(width: 35)
                }

                Text("In double-tap mode, recording auto-stops after this duration of silence. In push-to-talk mode, you control when to stop by releasing the key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sound Effects") {
                Toggle("Enable sound effects", isOn: $appState.soundEffectsEnabled)

                Text("Play subtle audio cues when recording starts and stops.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Input Device") {
                Picker("Microphone", selection: $appState.selectedAudioDeviceID) {
                    Text("System Default").tag("")
                    if selectedAudioDeviceIsUnavailable {
                        Text("\(selectedAudioDeviceDisplayName) (Unavailable)").tag(appState.selectedAudioDeviceID)
                    }
                    ForEach(audioDevices) { device in
                        Text(audioDeviceLabel(for: device)).tag(device.id)
                    }
                }
                .onChange(of: appState.selectedAudioDeviceID) { _ in
                    syncSelectedAudioDeviceName()
                }

                if audioDevices.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("No audio input devices found")
                            .foregroundStyle(.secondary)
                    }
                } else if selectedAudioDeviceIsUnavailable {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("\(selectedAudioDeviceDisplayName) is unavailable. VocaMac will use System Default until it reconnects.")
                            .foregroundStyle(.secondary)
                    }
                } else if let selectedAudioDevice {
                    HStack {
                        Image(systemName: "mic.circle.fill")
                            .foregroundStyle(.blue)
                        Text("VocaMac will record from \(selectedAudioDevice.name) without changing macOS' system default input.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(systemDefaultInputDescription)
                        .foregroundStyle(.secondary)
                }

                Button("Refresh Devices") {
                    refreshAudioDevices()
                }
                .controlSize(.small)

                Text("Choose System Default to follow macOS, or pin VocaMac to a specific microphone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshAudioDevices()
        }
    }

    private var selectedAudioDevice: AudioDevice? {
        guard !appState.selectedAudioDeviceID.isEmpty else { return nil }
        return audioDevices.first { $0.id == appState.selectedAudioDeviceID }
    }

    private var selectedAudioDeviceIsUnavailable: Bool {
        !appState.selectedAudioDeviceID.isEmpty && selectedAudioDevice == nil
    }

    private var selectedAudioDeviceDisplayName: String {
        appState.selectedAudioDeviceName.isEmpty ? "Selected microphone" : appState.selectedAudioDeviceName
    }

    private var systemDefaultInputDescription: String {
        if let defaultDevice = audioDevices.first(where: { $0.isDefault }) {
            return "VocaMac will follow macOS' system default input: \(defaultDevice.name)."
        }
        return "VocaMac will follow macOS' system default input."
    }

    private func audioDeviceLabel(for device: AudioDevice) -> String {
        device.isDefault ? "\(device.name) (System Default)" : device.name
    }

    private func refreshAudioDevices() {
        audioDevices = AudioEngine.availableInputDevices()
        syncSelectedAudioDeviceName()
    }

    private func syncSelectedAudioDeviceName() {
        guard !appState.selectedAudioDeviceID.isEmpty else {
            appState.selectedAudioDeviceName = ""
            return
        }

        if let selectedAudioDevice {
            appState.selectedAudioDeviceName = selectedAudioDevice.name
        }
    }

    private var sensitivityLabel: String {
        if appState.silenceThreshold < 0.01 { return "High" }
        if appState.silenceThreshold < 0.03 { return "Medium" }
        return "Low"
    }
}

// MARK: - About Tab

struct AboutTab: View {
    @EnvironmentObject var appState: AppState
    @State private var showingUpdateSheet = false
    @State private var updateInfoForSheet: UpdateInfo?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // App icon
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            // App name and version
            Text("VocaMac Lite")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Menu-bar dictation that transcribes\non your own server.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Version \(appVersionDisplay) (\(buildChannelLabel))")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button {
                Task { @MainActor in
                    await appState.updateChecker.checkForUpdates()
                    switch appState.updateChecker.updateState {
                    case .updateAvailable(let info), .updateAvailableViaHomebrew(let info, _):
                        updateInfoForSheet = info
                        showingUpdateSheet = true
                    default:
                        break
                    }
                }
            } label: {
                if case .checking = appState.updateChecker.updateState {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking for Updates...")
                    }
                    .font(.caption)
                } else {
                    Label("Check for Updates...", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Text(updateStatusText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            // Tech info
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    if let capabilities = appState.systemCapabilities {
                        InfoRow2(label: "Device", value: capabilities.processorName)
                        InfoRow2(label: "Architecture", value: capabilities.isAppleSilicon ? "Apple Silicon (ARM64)" : "Intel (x86_64)")
                        InfoRow2(label: "Neural Engine", value: capabilities.supportsMetalAcceleration ? "Available" : "Not Available")
                    }
                    InfoRow2(label: "Server", value: serverDisplayValue)
                    InfoRow2(label: "Format", value: formatDisplayValue)
                }
                .font(.caption)
                .padding(4)
            }
            .frame(width: 300)

            Divider()
                .frame(width: 200)

            // Links
            HStack(spacing: 16) {
                Link(destination: URL(string: "https://github.com/vajahath/vocamac-lite")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://github.com/jatinkrmalik/vocamac")!) {
                    Label("Upstream VocaMac", systemImage: "arrow.triangle.branch")
                }
            }
            .font(.caption)

            Divider()
                .frame(width: 200)

            Button(action: {
                NotificationCenter.default.post(name: .showOnboarding, object: nil)
            }) {
                Label("Show Setup Wizard…", systemImage: "wand.and.stars")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .help("Re-run the first-launch setup wizard")

            Spacer()

            HStack(spacing: 0) {
                Text("Fork of VocaMac by ")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Link("Jatin Kumar Malik", destination: URL(string: "https://x.com/intent/user?screen_name=jatinkrmalik")!)
                    .font(.caption2)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .sheet(isPresented: $showingUpdateSheet) {
            if let info = updateInfoForSheet {
                UpdateDetailView(info: info)
                    .environmentObject(appState)
            }
        }
    }

    private var appVersionDisplay: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildChannelLabel: String {
        appVersionDisplay.contains("nightly") ? "Nightly" : "Beta"
    }

    private var serverDisplayValue: String {
        let raw = appState.remoteEndpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "Not configured" }
        guard let url = URL(string: raw), let host = url.host else { return raw }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }

    private var formatDisplayValue: String {
        (RemoteEndpointFormat(rawValue: appState.remoteEndpointFormat) ?? .openAI).displayName
    }

    private var updateStatusText: String {
        switch appState.updateChecker.updateState {
        case .upToDate:
            return "You are on the latest version."
        case .updateAvailable(let info):
            return "Update available: \(info.tagName)"
        case .updateAvailableViaHomebrew(_, let install):
            return "Update available via Homebrew. Run: \(install.upgradeCommand)"
        case .error(let message):
            return message
        case .downloading(let progress, _, _, _):
            return "Downloading update... \(Int(progress * 100))%"
        case .verifying:
            return "Verifying download integrity..."
        case .readyToInstall:
            return "Update downloaded. Open the DMG to install."
        case .checking:
            return "Checking for updates..."
        case .idle:
            return ""
        }
    }
}

// MARK: - Debug Tab

struct DebugTab: View {
    @EnvironmentObject var appState: AppState
    @State private var logEntryCount: Int = VocaLogger.logEntryCount

    var body: some View {
        Form {
            // Permissions
            Section("Permissions") {
                PermissionRow(
                    name: "Microphone",
                    icon: "mic.fill",
                    status: appState.micPermission,
                    action: { appState.requestMicrophonePermission() }
                )

                PermissionRow(
                    name: "Accessibility",
                    icon: "accessibility",
                    status: appState.accessibilityPermission,
                    action: { appState.requestAccessibilityPermission() }
                )

                PermissionRow(
                    name: "Input Monitoring",
                    icon: "keyboard",
                    status: appState.inputMonitoringPermission,
                    action: { appState.requestInputMonitoringPermission() }
                )

                if appState.micPermission == .denied || appState.accessibilityPermission == .denied || appState.inputMonitoringPermission == .denied {
                    Text("Denied permissions must be enabled manually in System Settings → Privacy & Security.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Re-check Permissions") {
                        appState.checkPermissions()
                    }
                    .controlSize(.small)

                    Spacer()

                    Button(action: resetPermissions) {
                        Label("Reset All Permissions", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.red)
                    }
                    .controlSize(.small)
                    .help("Reset all TCC permissions for VocaMac. The app will quit and you'll need to re-grant permissions on next launch.")
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text("**Upgrading?** VocaMac Lite ships unsigned (ad-hoc) builds, so macOS may forget permission grants after an update. If permissions appear stuck, use the Reset button above and re-grant on next launch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Debug Logs
            Section("Debug Logs") {
                LabeledContent("Log File") {
                    Text(VocaLogger.logFileURL().lastPathComponent)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Log Entries") {
                    Text("\(logEntryCount)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(action: copyDebugLogs) {
                        Label("Copy to Clipboard", systemImage: "doc.on.clipboard")
                    }
                    .help("Copy last 500 lines of logs to clipboard")

                    Spacer()

                    Button(action: exportDebugLogs) {
                        Label("Export to File…", systemImage: "square.and.arrow.up")
                    }
                    .help("Save debug logs to file and reveal in Finder")

                    Spacer()

                    Button(action: {
                        VocaLogger.clearLogs()
                        logEntryCount = VocaLogger.logEntryCount
                    }) {
                        Label("Clear", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .help("Clear all log entries")
                }

                Text("Copy or export recent application logs for troubleshooting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Application
            Section("Application") {
                HStack {
                    Button(action: restartApp) {
                        Label("Restart VocaMac", systemImage: "arrow.trianglehead.clockwise")
                    }
                    .help("Quit and relaunch VocaMac")

                    Spacer()

                    Button(role: .destructive, action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        Label("Quit VocaMac", systemImage: "power")
                    }
                    .help("Quit VocaMac")
                }

                Text("Restart can help resolve issues with permissions or audio devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Actions

    private func resetPermissions() {
        let alert = NSAlert()
        alert.messageText = "Reset All Permissions?"
        alert.informativeText = "This will clear all permission grants (Microphone, Accessibility, Input Monitoring) for VocaMac. The app will quit and you'll need to re-grant permissions on next launch.\n\nThis is useful when permissions appear stuck or aren't being recognized after an update."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset & Quit")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Run tccutil to reset all TCC permissions for this app
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            task.arguments = ["reset", "All", "com.vocamac.lite"]
            try? task.run()
            task.waitUntilExit()

            VocaLogger.info(.general, "TCC permissions reset via tccutil")

            // Quit the app so permissions take effect on next launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func restartApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundlePath, "--args", "--restarted"]
        try? task.run()

        // Give the new instance a moment to start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Debug Log Actions

    private func copyDebugLogs() {
        let logs = VocaLogger.exportLogs(lastLines: 500)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logs, forType: .string)
    }

    private func exportDebugLogs() {
        let logs = VocaLogger.exportLogs(lastLines: 1000)

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "VocaMac-Debug-\(ISO8601DateFormatter().string(from: Date()).prefix(19)).log"
        savePanel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        savePanel.begin { response in
            if response == .OK, let fileURL = savePanel.url {
                do {
                    try logs.write(to: fileURL, atomically: true, encoding: .utf8)
                    NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
                } catch {
                    VocaLogger.error(.general, "Failed to export logs: \(error)")
                }
            }
        }
    }
}

struct InfoRow2: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .fontWeight(.medium)
            Spacer()
        }
    }
}
