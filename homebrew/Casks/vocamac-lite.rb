cask "vocamac-lite" do
  version "1.2.1"
  sha256 "929b03a85e579531d4e19cd99b87e8e4455ec77a962dd87bd96a0fd1d2efa086"

  url "https://github.com/vajahath/vocamac-lite/releases/download/v#{version}/VocaMac-#{version}-arm64.dmg"
  name "VocaMac Lite"
  desc "macOS dictation that does one thing: record your voice and send it to the speech-to-text server you choose — offload transcription to a GPU box and keep your Mac light. An efficiency-focused, sub-5 MB fork of VocaMac."
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
