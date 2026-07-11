cask "vocamac-lite" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # updated automatically on release

  url "https://github.com/vajahath/vocamac-lite/releases/download/v#{version}/VocaMac-#{version}-arm64.dmg",
      verified: "github.com/vajahath/vocamac-lite/"
  name "VocaMac Lite"
  desc "Menu-bar dictation that transcribes on your own remote Whisper server"
  homepage "https://github.com/vajahath/vocamac-lite"

  livecheck do
    url :url
    strategy :github_latest
  end

  conflicts_with cask: "vocamac"
  depends_on arch: :arm64
  depends_on macos: :ventura

  app "VocaMac.app"

  caveats <<~EOS
    VocaMac Lite is not code-signed with an Apple Developer ID.
    Install with --no-quarantine so macOS lets it launch:
      brew install --cask vocamac-lite --no-quarantine
    Or, if already installed:
      xattr -dr com.apple.quarantine /Applications/VocaMac.app
  EOS

  zap trash: [
    "~/Library/Application Support/VocaMac",
    "~/Library/Caches/com.vocamac.lite",
    "~/Library/Preferences/com.vocamac.lite.plist",
    "~/Library/Saved Application State/com.vocamac.lite.savedState",
  ]
end
