# VocaMac Lite — AI Coding Agent Guidelines

## Project Overview

VocaMac Lite is a **native macOS menu bar application** for voice-to-text dictation, built with **Swift 5.9+** and **SwiftUI**. It is a lean fork of [VocaMac](https://github.com/jatinkrmalik/vocamac): instead of running a local WhisperKit model, it records audio on the Mac (16 kHz mono WAV) and uploads it to a **user-configured remote transcription server** (OpenAI-compatible `/v1/audio/transcriptions` or whisper.cpp `/inference`). There is no local AI model, no HuggingFace download, and no website.

- **License:** AGPL-3.0
- **Minimum target:** macOS 13 (Ventura)
- **Build system:** Swift Package Manager (no external dependencies)
- **CI:** GitHub Actions (`.github/workflows/ci.yml`); releases build a DMG signed with a stable self-signed identity (`release.yml`)

---

## Repository Structure

```
vocamac-lite/
├── Sources/VocaMac/
│   ├── App/              # App entry point, MenuBarExtra, MenuBarIcon
│   ├── Models/           # AppState, RemoteEndpoint, TranscriptionResult
│   ├── Services/         # AudioEngine, HotKeyManager, RemoteTranscriptionService,
│   │                     #   SystemInfo, TextInjector, UpdateChecker
│   ├── Views/            # MenuBarView, SettingsView, OnboardingView
│   └── Resources/        # Bundled resources (icons, sounds, DMG background)
├── Tests/VocaMacTests/   # Unit tests (XCTest)
├── homebrew/             # Cask source of truth, synced to the tap repo on release
├── Makefile              # make build, install, test, clean, reset
├── scripts/              # build.sh, dist.sh, install.sh, uninstall.sh, release.sh
├── Package.swift         # SPM manifest
└── VocaMac.entitlements  # App entitlements
```

---

## Build & Run

```bash
make install      # Build + install to /Applications (recommended)
make build        # Build .app bundle in repo root (fast dev iteration)
make test         # swift test (requires full Xcode for XCTest)
make clean        # Remove build artifacts
```

The project builds on **macOS only** (requires AppKit, AVFoundation). CI runs on `macos-15`.

---

## Code Style & Best Practices

### Swift Conventions
- Use **SwiftUI** for all views — no AppKit views unless necessary for system integration
- Use `ObservableObject` with `@Published` for state management
- Prefer **`async/await`** over callbacks for asynchronous work
- Use **`guard`** for early returns; avoid deep nesting
- Mark sections with `// MARK: -`; add doc comments (`///`) on non-trivial methods

### Architecture Patterns
- **Single source of truth:** `AppState` (Models/AppState.swift) is the central observable state object
- **Service layer:** Business logic lives in `Services/`; services conform to protocols in `Services/ServiceProtocols.swift` and are injected into `AppState` (enables test mocking — see `Tests/VocaMacTests/Mocks/MockServices.swift`)
- **Views are thin:** Views observe state and dispatch actions
- **Settings** are `@AppStorage` keys under the `vocamac.*` namespace in `AppState`

### Performance — Keep It Lean
- This is a **menu bar app that runs at login** — it must stay lightweight (tens of MB resident)
- No local models, no heavy dependencies; keep `Package.swift` dependency-free
- Avoid polling; prefer event-driven updates. Heavy work runs off the main actor.

---

## Testing Requirements

- All new logic must have tests in `Tests/VocaMacTests/` (XCTest, run via `swift test`)
- Test pure logic (request building, parsing, state transitions); don't test SwiftUI rendering or system APIs
- CI executes `swift build` + `swift test` + a bundle verification via `./scripts/build.sh release`

---

## Git & PR Workflow

- Branch names: `feat/`, `fix/`, `ui/`, `chore/`, `docs/`, `ci/` + description
- Follow [Conventional Commits](https://www.conventionalcommits.org/)
- Never commit directly to main; one logical change per PR; PRs must pass CI
- Do not commit per-version release-notes files — release notes live on the GitHub Release page

---

## macOS-Specific Considerations

- **LSUIElement:** App runs as a menu bar agent (no dock icon)
- **Side-by-side isolation:** installs as `VocaMac Lite.app` with bundle id `com.vocamac.lite`, and stores data under `~/Library/Application Support/VocaMac Lite` + preferences `com.vocamac.lite`. All deliberately distinct from upstream (`VocaMac.app` / `com.vocamac.app` / `Application Support/VocaMac`) so both apps coexist with zero conflict. The SwiftPM product/executable stays named `VocaMac` (scheme, binary); only the bundle directory + display name are "VocaMac Lite" (see `scripts/build.sh` APP_DISPLAY_NAME).
- **Code signing:** Release builds (via CI) are signed with a stable, reused self-signed certificate (`MACOS_CERTIFICATE_P12_BASE64`/`_PASSWORD`/`MACOS_SIGN_IDENTITY` secrets) — not an Apple Developer ID, so Gatekeeper still quarantines the app, but the constant Designated Requirement means TCC keeps Accessibility/Input Monitoring grants across updates. Local dev builds (no cert in your keychain) fall back to ad-hoc, where permissions do reset on every rebuild. The Debug settings tab has a TCC reset button either way.
- **ATS:** the generated Info.plist allows arbitrary loads so plain-HTTP LAN endpoints work
- **MenuBarExtra limitations:** the label only renders `Image`/`Text`; use `NSImage` with `isTemplate = false` for colored menu bar icons

---

## Release Flow

1. `make release VERSION=x.y.z` tags and pushes `vx.y.z`
2. `release.yml` runs tests, imports the stable self-signed identity and builds the DMG via `./scripts/dist.sh --skip-notarize` (or `--skip-sign` if the cert secret is unset), uploads it as an artifact, and publishes a GitHub Release
3. `update-homebrew-cask.yml` updates `Casks/vocamac-lite.rb` in the `vajahath/homebrew-vocamac-lite` tap (requires `HOMEBREW_TAP_TOKEN` secret)
