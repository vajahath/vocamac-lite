# VocaMac Lite Homebrew Tap

Homebrew cask for [VocaMac Lite](https://github.com/vajahath/vocamac-lite) — a lean macOS menu-bar dictation app that transcribes on your own remote Whisper server.

This directory is the source of truth for the cask. On every published release, the `update-homebrew-cask` workflow pushes the updated cask (new version + sha256) to the tap repo `vajahath/homebrew-vocamac-lite`.

## Installation

```bash
brew tap vajahath/vocamac-lite
brew trust vajahath/vocamac-lite
brew install --cask vocamac-lite
xattr -dr com.apple.quarantine /Applications/VocaMac.app
```

The `xattr` step is required because VocaMac Lite ships unsigned (no Apple Developer ID) — it removes the quarantine flag so macOS lets the app launch. You can also right-click the app in Finder and choose Open.

## Upgrade

```bash
brew upgrade --cask vocamac-lite
```

## Uninstall

```bash
brew uninstall --cask vocamac-lite
# Remove all app data too:
brew uninstall --zap --cask vocamac-lite
```

## Maintainer setup

1. Create a public repo `vajahath/homebrew-vocamac-lite` containing `Casks/vocamac-lite.rb` (copy from this directory).
2. Add a `HOMEBREW_TAP_TOKEN` secret (PAT with write access to the tap repo) to this repo so the release workflow can push cask updates.
