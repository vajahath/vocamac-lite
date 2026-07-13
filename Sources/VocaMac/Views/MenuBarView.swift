// MenuBarView.swift
// VocaMac Lite
//
// Contents of the menu bar menu, rendered natively via `.menuBarExtraStyle(.menu)`.
// Deliberately minimal: the OS renders this as a real system menu — native
// Liquid Glass material, automatic light/dark, no artifacts, and no custom
// styling of our own. `.menu` supports only text, buttons, and dividers, so
// anything richer (status detail, transcription history) lives in the Settings
// window instead.

import SwiftUI

// MARK: - Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settingsManager: SettingsWindowManager

    var body: some View {
        // Title — same size as the other items, but bold.
        Text("VocaMac Lite")
            .fontWeight(.bold)

        Divider()

        // Update notice — a prominent, actionable item at the very top.
        if let info = appState.updateChecker.activeUpdateInfo {
            Button("Update \(info.tagName) available") {
                NSWorkspace.shared.open(info.releasePageURL)
            }
            Divider()
        }

        // How to trigger dictation (or the current action). Plain text renders
        // as a disabled info item in a native menu.
        Text(activationHint)

        Divider()

        // Verify the transcription server, showing the live result in Settings.
        Button("Test Connection") {
            settingsManager.open(appState: appState, section: .endpoint)
            Task { @MainActor in await appState.testEndpointConnection() }
        }

        permissionItems

        Divider()

        actionItems
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionItems: some View {
        Button("Settings") {
            settingsManager.open(appState: appState)
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Setup Wizard") {
            NotificationCenter.default.post(name: .showOnboarding, object: nil)
        }

        Button("Quit VocaMac Lite") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    // MARK: - Permissions

    /// Grant/settings actions, shown only while a permission is still missing.
    @ViewBuilder
    private var permissionItems: some View {
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

    // MARK: - Derived State

    /// How to trigger dictation, or the current action, worded for a human.
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
}
