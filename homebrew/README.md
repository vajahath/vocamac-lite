# VocaMac Lite Homebrew Tap

Homebrew cask for [VocaMac Lite](https://github.com/vajahath/vocamac-lite) — a lean macOS menu-bar dictation app that transcribes on your own remote Whisper server.

This directory is the source of truth for the cask. On every published release, the `update-homebrew-cask` workflow pushes the updated cask (new version + sha256) to the tap repo `vajahath/homebrew-vocamac-lite`.

## Installation

```bash
brew tap vajahath/vocamac-lite
brew trust vajahath/vocamac-lite
brew install --cask vocamac-lite
xattr -dr com.apple.quarantine "/Applications/VocaMac Lite.app"
```

The `xattr` step is required because VocaMac Lite ships unsigned (no Apple Developer ID) — it removes the quarantine flag so macOS lets the app launch. You can also right-click the app in Finder and choose Open.

VocaMac Lite installs as `VocaMac Lite.app` (bundle id `com.vocamac.lite`), so it coexists with the upstream `vocamac` cask — install both side by side without conflict.

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

1. Create a public repo `vajahath/homebrew-vocamac-lite` containing `Casks/vocamac-lite.rb` (copy from this directory). *(Already done.)*
2. Add a `HOMEBREW_TAP_TOKEN` secret to the **main repo** (`vajahath/vocamac-lite`), where the `update-homebrew-cask` workflow runs. The secret's value is a GitHub PAT whose permissions grant **write access to the tap repo** (`vajahath/homebrew-vocamac-lite`) — a fine-grained PAT scoped to only that repo with Contents: Read and write is ideal. Without it, the cask-update job skips cleanly and you update the cask by hand.
