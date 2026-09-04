cask "trace-mem" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/t1mdotcom/trace-mem/releases/download/v#{version}/trace-mem-#{version}.zip"
  name "trace-mem"
  desc "On-device push-to-talk dictation for macOS"
  homepage "https://github.com/t1mdotcom/trace-mem"

  # LSMinimumSystemVersion in the bundle enforces macOS 27; Homebrew has no symbol for 27 yet.
  depends_on macos: ">= :tahoe"
  depends_on arch: :arm64

  app "trace-mem.app"

  zap trash: [
    "~/Library/Application Support/trace-mem",
  ]

  caveats <<~EOS
    trace-mem ist selbstsigniert und nicht notarisiert. Erster Start:
      Rechtsklick auf /Applications/trace-mem.app → Öffnen
    oder Quarantäne entfernen:
      xattr -dr com.apple.quarantine /Applications/trace-mem.app

    Danach im Menubar-Menü Mikrofon und Bedienungshilfen erlauben.
  EOS
end
