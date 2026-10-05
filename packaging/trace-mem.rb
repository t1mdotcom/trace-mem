cask "trace-mem" do
  version "0.2.0"
  sha256 "c0cb2c66fa2ba2c1467d6049723e4609265398864a6be8410bee00f2ffdb2a1d"

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
