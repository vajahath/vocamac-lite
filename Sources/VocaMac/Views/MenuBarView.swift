// MenuBarView.swift
// VocaMac Lite
//
// Content of the menu bar popover (rendered with `.menuBarExtraStyle(.window)`).
// Styled after the macOS Control Center widgets (e.g. Battery): a prominent
// title, informative description lines rendered in full-strength text (not the
// greyed/disabled look of a stock NSMenu), and clean, icon-free action rows
// with a hover highlight.

import SwiftUI

// MARK: - Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settingsManager: SettingsWindowManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Update notice — a prominent, actionable row at the very top.
            if let info = appState.updateChecker.activeUpdateInfo {
                MenuActionRow(title: "Update \(info.tagName) available", tint: .blue) {
                    NSWorkspace.shared.open(info.releasePageURL)
                }
                rowDivider
            }

            header
            contextualControls

            if let transcription = appState.lastTranscription {
                rowDivider
                transcriptionSection(transcription)
            }

            if needsPermissions {
                rowDivider
                permissionsSection
            }

            rowDivider

            // Actions
            VStack(spacing: 1) {
                MenuActionRow(title: "Settings", shortcut: "⌘,") {
                    settingsManager.open(appState: appState)
                }
                MenuActionRow(title: "Setup Wizard") {
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                }
                MenuActionRow(title: "Quit VocaMac Lite", shortcut: "⌘Q") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(4)
        }
        .frame(width: 280)
        // Refresh reachability every time the popover opens, so a server that
        // has since come back online shows as reachable instead of stale.
        .onAppear {
            Task { @MainActor in await appState.checkEndpointReachability() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("VocaMac Lite")
                .font(.system(size: 13, weight: .semibold))

            // Description lines — full-strength primary text for the key fact,
            // secondary for the hint, and a tint when the server needs attention.
            Text(serverLine)
                .font(.system(size: 12))
                .foregroundStyle(serverLineColor)
                .fixedSize(horizontal: false, vertical: true)

            Text(activationHint)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 7)
    }

    // MARK: - Contextual Controls

    @ViewBuilder
    private var contextualControls: some View {
        switch appState.appStatus {
        case .recording:
            MenuActionRow(title: "Stop Recording", tint: .red) {
                Task { @MainActor in await appState.stopRecordingAndTranscribe() }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        case .error:
            MenuActionRow(title: "Reset to Idle", tint: .orange) {
                appState.forceRecovery()
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        case .idle, .processing:
            EmptyView()
        }
    }

    // MARK: - Last Transcription

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
                    Text("Copy")
                        .font(.system(size: 11))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }

            Text(result.text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))

            Text("\(String(format: "%.1f", result.audioLengthSeconds))s · \(result.detectedLanguage)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Permissions

    private var needsPermissions: Bool {
        appState.micPermission != .granted
            || appState.accessibilityPermission != .granted
            || appState.inputMonitoringPermission != .granted
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Permissions Needed")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)

            if appState.micPermission != .granted {
                MenuActionRow(
                    title: appState.micPermission == .denied ? "Open Microphone Settings" : "Grant Microphone Access",
                    tint: .orange
                ) {
                    if appState.micPermission == .denied {
                        appState.openMicrophoneSettings()
                    } else {
                        appState.requestMicrophonePermission()
                    }
                }
            }
            if appState.accessibilityPermission != .granted {
                MenuActionRow(title: "Grant Accessibility Access", tint: .orange) {
                    appState.requestAccessibilityPermission()
                }
            }
            if appState.inputMonitoringPermission != .granted {
                MenuActionRow(title: "Grant Input Monitoring", tint: .orange) {
                    appState.requestInputMonitoringPermission()
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // MARK: - Divider

    private var rowDivider: some View {
        Divider().padding(.horizontal, 10)
    }

    // MARK: - Derived State

    /// Primary description line: server reachability, worded for a human.
    private var serverLine: String {
        switch appState.endpointStatus {
        case .reachable:    return "Server connected · \(serverDisplayName)"
        case .checking:     return "Checking server…"
        case .unreachable:  return "Server unreachable · \(serverDisplayName)"
        case .unconfigured: return "No server configured"
        }
    }

    private var serverLineColor: Color {
        switch appState.endpointStatus {
        case .reachable:    return .primary
        case .checking:     return .secondary
        case .unreachable:  return .orange
        case .unconfigured: return .orange
        }
    }

    /// Second description line: how to trigger dictation, or the current action.
    private var activationHint: String {
        switch appState.appStatus {
        case .recording:  return "Recording your voice…"
        case .processing: return "Transcribing your audio…"
        case .idle, .error:
            let keyName = KeyCodeReference.displayName(for: appState.hotKeyCode)
            switch appState.activationMode {
            case .pushToTalk:      return "Hold \(keyName) to dictate"
            case .doubleTapToggle: return "Double-tap \(keyName) to dictate"
            }
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
}

// MARK: - Menu Action Row

/// A clickable, icon-free row styled like a Control Center menu item:
/// full-strength label, optional trailing shortcut, and a full-width hover
/// highlight.
private struct MenuActionRow: View {
    let title: String
    var shortcut: String? = nil
    var tint: Color? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13))
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(tint ?? .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
