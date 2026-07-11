// MenuBarView.swift
// VocaMac Lite
//
// The popover view shown when clicking the menu bar icon.
// Displays current status, audio level, last transcription, and quick actions.

import SwiftUI

// MARK: - Process Monitor

/// Polls the current process for CPU and memory usage while the menu popover
/// is open. Polling is paused when the popover closes (see MenuBarView's
/// onAppear/onDisappear) so an idle menu bar app isn't waking up every 5s.
final class ProcessMonitor: ObservableObject {
    @Published var cpuUsage: Double = 0       // percentage (0–100+)
    @Published var memoryMB: Double = 0       // phys_footprint in MB (matches Activity Monitor)
    @Published var memoryPeakMB: Double = 0   // peak footprint seen
    @Published var threadCount: Int = 0       // active thread count

    private var timer: Timer?

    /// Begin polling and refresh immediately. Safe to call repeatedly.
    func startPolling() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    /// Stop polling while the popover is closed.
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }

    func refresh() {
        // --- Memory via task_vm_info.phys_footprint ---
        // phys_footprint is what Activity Monitor's "Memory" column reports: the
        // app's private/dirty memory. We deliberately do NOT use resident_size,
        // which also counts shared OS framework pages (AppKit, SwiftUI, …) and
        // inflates the figure ~3x even though that memory is shared across apps.
        var vmInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let mb = Double(vmInfo.phys_footprint) / (1024 * 1024)
            DispatchQueue.main.async {
                self.memoryMB = mb
                self.memoryPeakMB = max(self.memoryPeakMB, mb)
            }
        }

        // --- CPU via task_threads + thread_basic_info ---
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let threadKr = task_threads(mach_task_self_, &threadList, &threadCount)
        guard threadKr == KERN_SUCCESS, let threads = threadList else { return }

        var totalCPU: Double = 0
        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
            let infoKr = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if infoKr == KERN_SUCCESS && threadInfo.flags != TH_FLAGS_IDLE {
                totalCPU += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            }
        }

        let count2 = Int(threadCount)
        // Deallocate the thread list
        let size = vm_size_t(MemoryLayout<thread_t>.stride * Int(threadCount))
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)

        DispatchQueue.main.async {
            self.cpuUsage = totalCPU
            self.threadCount = count2
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settingsManager: SettingsWindowManager
    @StateObject private var processMonitor = ProcessMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let info = appState.updateChecker.activeUpdateInfo {
                UpdateBannerView(info: info)
                menuDivider
            }

            // Header
            headerSection

            menuDivider

            // Status & Recording
            statusSection

            // Last Transcription
            if let transcription = appState.lastTranscription {
                menuDivider
                transcriptionSection(transcription)
            }

            // Permissions Warning
            if appState.micPermission != .granted || appState.accessibilityPermission != .granted || appState.inputMonitoringPermission != .granted {
                menuDivider
                permissionsSection
            }

            menuDivider

            // Quick Actions
            actionsSection
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 320)
        // Only poll CPU/RAM while the popover is actually open.
        .onAppear { processMonitor.startPolling() }
        .onDisappear { processMonitor.stopPolling() }
    }

    /// Hairline separator matching the system menu's low-contrast dividers.
    private var menuDivider: some View {
        Divider()
            .opacity(0.6)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("VocaMac Lite")
                    .font(.system(size: 13, weight: .semibold))

                switch appState.endpointStatus {
                case .reachable:
                    Text("Server: \(serverDisplayName)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                case .checking:
                    Text("Checking server…")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                case .unreachable(let message):
                    Text("Server unreachable")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .help(message)
                case .unconfigured:
                    Text("No server configured")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .help("Set the server URL in Settings → Endpoint")
                }
            }

            Spacer()

            // CPU & RAM usage display
            HStack(spacing: 6) {
                ResourceBadge(
                    icon: "cpu",
                    value: String(format: "%.0f%%", processMonitor.cpuUsage),
                    details: [
                        ("CPU Usage", String(format: "%.1f%%", processMonitor.cpuUsage)),
                        ("Threads", "\(processMonitor.threadCount)"),
                        ("Cores", "\(ProcessInfo.processInfo.activeProcessorCount)"),
                    ]
                )

                ResourceBadge(
                    icon: "memorychip",
                    value: formattedMemory(processMonitor.memoryMB),
                    details: [
                        ("Footprint", String(format: "%.1f MB", processMonitor.memoryMB)),
                        ("Peak", String(format: "%.1f MB", processMonitor.memoryPeakMB)),
                        ("System", "\(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)) GB"),
                    ]
                )
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(statusColor)

                Spacer()

                Text(activationModeHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Audio level indicator (visible during recording)
            if appState.appStatus == .recording {
                AudioLevelView(level: appState.audioLevel)
                    .frame(height: 4)

                // Stop/recovery button — visible during recording so the user
                // can unstick the app if the hotkey isn't responding
                Button {
                    Task { @MainActor in
                        await appState.stopRecordingAndTranscribe()
                    }
                } label: {
                    Label("Stop Recording", systemImage: "stop.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            // Processing indicator
            if appState.appStatus == .processing {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // Force recovery button — visible in error state
            if appState.appStatus == .error {
                Button {
                    appState.forceRecovery()
                } label: {
                    Label("Reset to Idle", systemImage: "arrow.counterclockwise.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Transcription

    private func transcriptionSection(_ result: VocaTranscription) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Last Transcription")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy to clipboard")
            }

            Text(result.text)
                .font(.system(size: 12))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)

            HStack {
                Text("\(String(format: "%.1f", result.audioLengthSeconds))s audio")
                Text("•")
                Text("\(String(format: "%.1f", result.duration))s to transcribe")
                Text("•")
                Text(result.detectedLanguage)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Permissions Required")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)

            if appState.micPermission != .granted {
                permissionButton(
                    label: appState.micPermission == .denied ? "Open Microphone Settings" : "Grant Microphone Access",
                    icon: "mic.badge.xmark",
                    isDenied: appState.micPermission == .denied,
                    action: { appState.requestMicrophonePermission() }
                )

                Text(appState.micPermission == .denied
                     ? "Denied. Enable in System Settings → Privacy & Security → Microphone."
                     : "Required to capture your voice for transcription.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appState.accessibilityPermission != .granted {
                permissionButton(
                    label: "Grant Accessibility Access",
                    icon: "lock.shield",
                    isDenied: appState.accessibilityPermission == .denied,
                    action: { appState.requestAccessibilityPermission() }
                )

                Text("Required for global hotkeys and text injection. Opens System Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appState.inputMonitoringPermission != .granted {
                permissionButton(
                    label: "Grant Input Monitoring",
                    icon: "keyboard",
                    isDenied: appState.inputMonitoringPermission == .denied,
                    action: { appState.requestInputMonitoringPermission() }
                )

                Text("Required to detect hotkey presses system-wide. Enable VocaMac Lite in the list.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Reusable permission button that shows different styling for denied vs not determined
    private func permissionButton(label: String, icon: String, isDenied: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Label(label, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDenied ? .red : .orange)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 1) {
            menuActionRow(icon: "gear", title: "Settings", shortcut: "⌘,") {
                settingsManager.open(appState: appState)
            }

            menuActionRow(icon: "wand.and.stars", title: "Setup Wizard", shortcut: nil) {
                NotificationCenter.default.post(name: .showOnboarding, object: nil)
            }

            menuActionRow(icon: "power", title: "Quit VocaMac Lite", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, -8)
    }

    /// A single action row styled like a native macOS menu item: fixed-width
    /// icon column, consistent 13pt label, trailing shortcut hint, and a
    /// hover highlight spanning the full row width.
    private func menuActionRow(icon: String, title: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(0.0001))
            )
        }
        .buttonStyle(MenuRowButtonStyle())
    }

    // MARK: - Helpers

    /// Compact "host:port" for the configured server, without scheme/path noise.
    private var serverDisplayName: String {
        let raw = appState.remoteEndpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), let host = url.host else { return raw }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }

    private var statusText: String {
        switch appState.appStatus {
        case .idle:       return "Ready"
        case .recording:  return "Recording..."
        case .processing: return "Transcribing..."
        case .error:      return appState.errorMessage ?? "Error"
        }
    }

    private var statusColor: Color {
        switch appState.appStatus {
        case .idle:       return .green
        case .recording:  return .red
        case .processing: return .orange
        case .error:      return .yellow
        }
    }

    private var activationModeHint: String {
        let keyName = KeyCodeReference.displayName(for: appState.hotKeyCode)
        switch appState.activationMode {
        case .pushToTalk:
            return "Hold \(keyName)"
        case .doubleTapToggle:
            return "Double-tap \(keyName)"
        }
    }

    /// Formats memory in MB to a compact human-readable string
    private func formattedMemory(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Menu Row Button Style

/// A button style that highlights on hover, matching native macOS menu behavior.
struct MenuRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Resource Badge

/// A compact CPU/RAM badge that shows a detail popover on hover.
struct ResourceBadge: View {
    let icon: String
    let value: String
    let details: [(String, String)]

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .popover(isPresented: $isHovered, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                    Text(value)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Divider()

                ForEach(details, id: \.0) { label, val in
                    HStack {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(val)
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
            }
            .padding(10)
            .frame(width: 160)
        }
    }
}

// MARK: - Audio Level View

/// A simple horizontal bar that visualizes the current audio input level
struct AudioLevelView: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.2))

                // Level indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(levelColor)
                    .frame(width: max(0, geometry.size.width * CGFloat(level)))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
    }

    private var levelColor: Color {
        if level > 0.8 { return .red }
        if level > 0.5 { return .orange }
        return .green
    }
}
