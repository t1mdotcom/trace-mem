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
    trace-mem ist selbstsigniert und nicht notarisiert. Gatekeeper blockt den ersten Start.
    Freigeben per Terminal:
      xattr -dr com.apple.quarantine /Applications/trace-mem.app
    oder Systemeinstellungen → Datenschutz & Sicherheit → „Trotzdem öffnen“.
    Alternativ ohne Quarantäne installieren: brew install --cask --no-quarantine trace-mem

    Danach im Menubar-Menü Mikrofon und Bedienungshilfen erlauben.
  EOS
end
