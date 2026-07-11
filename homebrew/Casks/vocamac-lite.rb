cask "vocamac-lite" do
  version "1.0.3"
  sha256 "e836efb81ff0dfb324ad1c8d34003dd5fee01ed39643e97119975de3a4b13e77"

  url "https://github.com/vajahath/vocamac-lite/releases/download/v#{version}/VocaMac-#{version}-arm64.dmg"
  name "VocaMac Lite"
  desc "Menu-bar dictation that transcribes on your own remote Whisper server"
  homepage "https://github.com/vajahath/vocamac-lite"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :ventura

  # Installs as "VocaMac Lite.app" with bundle id com.vocamac.lite, so it
  # coexists with the upstream "vocamac" cask (VocaMac.app / com.vocamac.app).
  app "VocaMac Lite.app"

  caveats <<~EOS
    VocaMac Lite is not code-signed with an Apple Developer ID, so macOS
    quarantines it. Allow it to launch by removing the quarantine flag:
      xattr -dr com.apple.quarantine "/Applications/VocaMac Lite.app"
    (or right-click the app in Finder and choose Open).
  EOS

  zap trash: [
    "~/Library/Application Support/VocaMac Lite",
    "~/Library/Caches/com.vocamac.lite",
    "~/Library/Preferences/com.vocamac.lite.plist",
    "~/Library/Saved Application State/com.vocamac.lite.savedState",
  ]
end
