# VocaMac Lite

**Menu-bar dictation for macOS that transcribes on *your own* server.**

Hold a hotkey, speak, and your words are typed wherever your cursor is. Audio is recorded locally (16 kHz mono WAV) and sent to a Whisper server you run — on your LAN box, homelab, or any OpenAI-compatible API. Nothing is transcribed on the Mac itself, so the app stays tiny: no local AI model, no gigabytes of RAM, safe to keep running from login.

A lean fork of [VocaMac](https://github.com/jatinkrmalik/vocamac) by Jatin Kumar Malik (AGPL-3.0). The upstream app runs WhisperKit locally; this fork replaces the local engine with a remote endpoint and strips everything else.

## How it works

```
hotkey ──▶ mic (16 kHz WAV) ──▶ POST to your server ──▶ text typed at your cursor
```

Two server API formats are supported (pick one in Settings → Endpoint):

| Format | Endpoint | Works with |
|---|---|---|
| OpenAI-compatible | `POST /v1/audio/transcriptions` | Speaches, faster-whisper-server, LocalAI, OpenAI |
| whisper.cpp server | `POST /inference` | whisper.cpp's bundled `whisper-server` |

## Install

**Homebrew (recommended):** (BETA)

```bash
brew tap vajahath/vocamac-lite
brew install --cask vocamac-lite --no-quarantine
```

**Manual:** download the DMG from [Releases](https://github.com/vajahath/vocamac-lite/releases), drag VocaMac to Applications, then remove the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/VocaMac.app
```

> `--no-quarantine` / `xattr` is needed because builds are not signed with an Apple Developer ID (no paid developer account). The source is right here — build it yourself if you prefer.

On first launch, the setup wizard walks you through permissions (Microphone, Accessibility, Input Monitoring), your server endpoint, and the hotkey.

## Set up a transcription server

Run one of these on the machine that hosts your models:

**Speaches (faster-whisper, Docker):**

```bash
docker run --publish 8000:8000 --volume speaches-cache:/home/ubuntu/.cache \
  ghcr.io/speaches-ai/speaches:latest-cpu   # or :latest-cuda for GPU
```

→ Format: *OpenAI-compatible*, URL: `http://<server-ip>:8000`, Model: e.g. `Systran/faster-whisper-small`

**whisper.cpp server:**

```bash
./build/bin/whisper-server -m models/ggml-base.en.bin --host 0.0.0.0 --port 8080
```

→ Format: *whisper.cpp server*, URL: `http://<server-ip>:8080`

**OpenAI's hosted API** also works (URL `https://api.openai.com`, your API key, model `whisper-1`) — but then your audio leaves your network; that's the tradeoff.

Use the **Test Connection** button in Settings → Endpoint (or the setup wizard) to verify — it sends a short silent clip through the real transcription path.

## Settings overview

- **General** — activation mode (push-to-talk / double-tap toggle), hotkey, transcription language, translation toggle, custom vocabulary (sent to the server as a prompt hint), clipboard preservation, launch at login
- **Endpoint** — server URL, API format, optional API key (Bearer), optional model name, test connection
- **Stats** — words dictated, time saved
- **Audio** — input device, silence auto-stop, max recording duration, sound effects
- **Debug** — permission status/reset, log export

## Security notes

- The API key is stored **unencrypted** in app preferences (`~/Library/Preferences/com.vocamac.lite.plist`). Plain HTTP is fine on a trusted LAN; use HTTPS + an API key for anything beyond it.
- Because builds are ad-hoc signed, macOS may forget permission grants after an update — the Debug tab has a "Reset All Permissions" button if they get stuck.

## Build from source

Requires macOS 13+ and Xcode (for `xcodebuild` and XCTest).

```bash
git clone https://github.com/vajahath/vocamac-lite.git
cd vocamac-lite
make install   # build + install to /Applications
make test      # run the test suite
```

## Releasing (maintainer)

```bash
make release VERSION=x.y.z
```

This tags `vx.y.z` and pushes; GitHub Actions then runs the tests, builds an unsigned DMG (`release.yml`), publishes a GitHub Release, and updates the Homebrew tap (`update-homebrew-cask.yml`, requires the `HOMEBREW_TAP_TOKEN` secret and the `vajahath/homebrew-vocamac-lite` tap repo — see [homebrew/README.md](homebrew/README.md)). The DMG is also downloadable as a workflow artifact from the Actions run.

## License

[AGPL-3.0](LICENSE). Forked from [jatinkrmalik/vocamac](https://github.com/jatinkrmalik/vocamac) — all credit for the original app, audio pipeline, and UX goes upstream.
