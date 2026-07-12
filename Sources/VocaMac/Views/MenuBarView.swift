// MenuBarView.swift
// VocaMac Lite
//
// Content of the menu bar item. Rendered as a native macOS menu
// (`.menuBarExtraStyle(.menu)`), so this view contains only menu-legal SwiftUI
// primitives — `Text` (informational rows), `Button` (actions), and `Divider`.
// AppKit owns all font, spacing, hover, shadow, and padding, matching system
// menus like the Wi-Fi menu. No custom fonts or styling live here.

import SwiftUI

// MARK: - Process Stats

/// Reads the process's current CPU and memory usage synchronously. Called each
/// time the menu is built (native menus have no always-open state to poll).
enum ProcessStats {
    /// - Returns: instantaneous CPU percentage and `phys_footprint` in MB.
    ///   `phys_footprint` is what Activity Monitor's "Memory" column reports —
    ///   the app's private/dirty memory — deliberately in preference to
    ///   `resident_size`, which also counts shared framework pages and reads ~3x
    ///   higher even though that memory is shared across apps.
    static func current() -> (cpu: Double, memoryMB: Double) {
        var memoryMB = 0.0
        var vmInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            memoryMB = Double(vmInfo.phys_footprint) / (1024 * 1024)
        }

        var cpu = 0.0
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        if task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS, let threads = threadList {
            for i in 0..<Int(threadCount) {
                var threadInfo = thread_basic_info()
                var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
                let infoKr = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                        thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                    }
                }
                if infoKr == KERN_SUCCESS && threadInfo.flags != TH_FLAGS_IDLE {
                    cpu += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100
                }
            }
            let size = vm_size_t(MemoryLayout<thread_t>.stride * Int(threadCount))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)
        }

        return (cpu, memoryMB)
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settingsManager: SettingsWindowManager

    var body: some View {
        let stats = ProcessStats.current()

        // Update notice
        if let info = appState.updateChecker.activeUpdateInfo {
            Button("Update \(info.tagName) available…") {
                NSWorkspace.shared.open(info.releasePageURL)
            }
            Divider()
        }

        // Header: app name + server status
        Text("VocaMac Lite")
        Text(serverStatusLine)

        Divider()

        // Status + recording controls
        Text(statusLine)
        if appState.appStatus == .recording {
            Button("Stop Recording") {
                Task { @MainActor in
                    await appState.stopRecordingAndTranscribe()
                }
            }
        }
        if appState.appStatus == .error {
            Button("Reset to Idle") {
                appState.forceRecovery()
            }
        }

        Divider()

        // Resource usage
        Text("CPU \(String(format: "%.0f%%", stats.cpu))  ·  Memory \(formattedMemory(stats.memoryMB))")

        // Last transcription
        if let transcription = appState.lastTranscription {
            Divider()
            Text("Last: \(transcriptionPreview(transcription.text))")
            Button("Copy Last Transcription") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcription.text, forType: .string)
            }
        }

        // Missing permissions
        if needsPermissions {
            Divider()
            permissionButtons
        }

        Divider()

        // Actions
        Button("Settings") {
            settingsManager.open(appState: appState)
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Setup Wizard") {
            NotificationCenter.default.post(name: .showOnboarding, object: nil)
        }

        Divider()

        Button("Quit VocaMac Lite") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    // MARK: - Permissions

    private var needsPermissions: Bool {
        appState.micPermission != .granted
            || appState.accessibilityPermission != .granted
            || appState.inputMonitoringPermission != .granted
    }

    @ViewBuilder
    private var permissionButtons: some View {
        if appState.micPermission != .granted {
            Button(appState.micPermission == .denied ? "Open Microphone Settings" : "Grant Microphone Access") {
                if appState.micPermission == .denied {
                    appState.openMicrophoneSettings()
                } else {
                    appState.requestMicrophonePermission()
                }
            }
        }
        if appState.accessibilityPermission != .granted {
            Button("Grant Accessibility Access") {
                appState.requestAccessibilityPermission()
            }
        }
        if appState.inputMonitoringPermission != .granted {
            Button("Grant Input Monitoring") {
                appState.requestInputMonitoringPermission()
            }
        }
    }

    // MARK: - Text Helpers

    /// Server row text for the current endpoint state.
    private var serverStatusLine: String {
        switch appState.endpointStatus {
        case .reachable:   return "Server: \(serverDisplayName)"
        case .checking:    return "Checking server…"
        case .unreachable: return "Server unreachable"
        case .unconfigured: return "No server configured"
        }
    }

    /// Status row text, combining the app status with the activation hint.
    private var statusLine: String {
        switch appState.appStatus {
        case .idle:       return "Ready — \(activationModeHint)"
        case .recording:  return "Recording… — \(activationModeHint)"
        case .processing: return "Transcribing…"
        case .error:      return appState.errorMessage ?? "Error"
        }
    }

    /// Compact "host:port" for the configured server, without scheme/path noise.
    private var serverDisplayName: String {
        let raw = appState.remoteEndpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), let host = url.host else { return raw }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
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

    /// Single-line, length-capped preview of a transcription for the menu row.
    private func transcriptionPreview(_ text: String) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count > 50 ? String(flat.prefix(50)) + "…" : flat
    }

    /// Formats memory in MB to a compact human-readable string.
    private func formattedMemory(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}
