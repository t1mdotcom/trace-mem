cask "trace-mem" do
  version "0.1.0"
  sha256 "686dee8aead98d0adb19f2c3b83b28b034315cb08b3b03f24e4dd400e3c412a4"

  url "https://github.com/t1mdotcom/trace-mem/releases/download/v#{version}/trace-mem-#{version}.zip"
  name "trace-mem"
  desc "On-device push-to-talk dictation for macOS"
  homepage "https://github.com/t1mdotcom/trace-mem"

  depends_on macos: :golden_gate
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
