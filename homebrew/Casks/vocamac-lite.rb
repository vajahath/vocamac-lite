cask "vocamac-lite" do
  version "1.0.0"
  sha256 "bc826e5d20ee80c497c0fb455f53b86e4d48ae440afacbb1da5378f4de292e2c"

  url "https://github.com/vajahath/vocamac-lite/releases/download/v#{version}/VocaMac-#{version}-arm64.dmg"
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
    VocaMac Lite is not code-signed with an Apple Developer ID, so macOS
    quarantines it. Allow it to launch by removing the quarantine flag:
      xattr -dr com.apple.quarantine /Applications/VocaMac.app
    (or right-click the app in Finder and choose Open).
  EOS

  zap trash: [
    "~/Library/Application Support/VocaMac",
    "~/Library/Caches/com.vocamac.lite",
    "~/Library/Preferences/com.vocamac.lite.plist",
    "~/Library/Saved Application State/com.vocamac.lite.savedState",
  ]
end
