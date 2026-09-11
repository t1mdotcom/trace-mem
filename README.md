# trace-mem

Push-to-talk-Diktat für macOS, vollständig on-device. Taste halten, sprechen, loslassen: der Text landet in der gerade fokussierten App. Vorbild ist Wispr Flow, nur ohne Cloud.

Zweiter Modus: Meeting-Transkription. Mikrofon und System-Audio werden parallel transkribiert und als Markdown-Datei gespeichert.

## Was es tut

1. Globaler Hotkey (frei wählbar, Modifier oder Tastenkombination, Halten- oder Umschalt-Modus) startet die Aufnahme.
2. Das Mikrofon geht direkt in Apples `SpeechAnalyzer` / `SpeechTranscriber`. Das Modell läuft lokal, Audio verlässt den Rechner nicht.
3. Ein kleines Panel unten in der Bildschirmmitte zeigt Pegel und Zwischentext.
4. Nach dem Loslassen wird der erkannte Text über die Zwischenablage und ein synthetisches ⌘V eingefügt. Der vorherige Inhalt der Zwischenablage wird danach wiederhergestellt.
5. Optionaler Text-Cleanup (Füllwörter, Interpunktion, gesprochene Befehle wie "neuer Absatz"). Standard ist Apples on-device Modell über das `FoundationModels`-Framework, alternativ `claude -p` oder `codex exec` als Subprozess mit dem bestehenden Abo-Login der CLI. Schlägt der Schritt fehl oder dauert er länger als das Timeout, wird der Rohtext eingefügt und der Grund steht in der Statuszeile.

## Meetings transkribieren

Menubar → **Meeting aufnehmen**. Zwei Quellen laufen parallel durch je einen eigenen on-device Transcriber:

| Quelle | Label | Technik |
|---|---|---|
| Mikrofon | `Ich` | `CaptureInputSequenceProvider` (wie beim Diktat) |
| System-Audio (Teams, Zoom, Browser…) | `Andere` | Core Audio Process Tap auf den gesamten Ausgabemix |

**Meeting beenden** schreibt `~/Documents/trace-mem/<YYYY-MM-DD_HH-mm>.md` fertig und öffnet die Datei. Während der Aufnahme wird jedes fertige Segment sofort angehängt, ein Absturz verliert höchstens die letzten Sekunden. Segmente werden nach Startzeit sortiert. Ist ein Cleanup-Provider gewählt, kommt am Ende ein Abschnitt "Zusammenfassung" dazu.

```
---
start: 2026-09-04T09:38:42Z
end: 2026-09-04T09:39:02Z
duration: 00:00:20
---

[00:00:00] Ich: Kurze Frage zum Release.
[00:00:06] Andere: Wir verschieben es auf nächste Woche.
```

Hinweise:

- Beim ersten Meeting fragt macOS nach **Systemaudio aufnehmen**. Die Freigabe steht unter Datenschutz & Sicherheit → Bildschirm- und Systemaudioaufnahme. Ohne Freigabe liefert macOS stumme Nullen statt eines Fehlers. Die App warnt nach 30 Sekunden Stille in der Statuszeile.
- Über Lautsprecher hört das Mikrofon auch die anderen Teilnehmer, dann tauchen Sätze doppelt auf. Mit Kopfhörern ist die Trennung sauber.
- Keine Sprecher-Erkennung innerhalb einer Quelle. Alle Gegenstellen heißen `Andere`.
- Sprache im Menü unter **Sprache** wählen. Die System-Locale ist der Standard.
- Zum Skripten: `notifyutil -p dev.theinemann.trace-mem.meeting` schaltet den Meeting-Modus um.

## Voraussetzungen

- macOS 27 oder neuer, Apple Silicon. Grund: `CaptureInputSequenceProvider` aus dem Speech-Framework gibt es erst ab 27.
- Xcode 27 (Beta reicht). `xcode-select -p` muss auf Xcode zeigen, sonst nutzt `scripts/bundle.sh` automatisch `/Applications/Xcode-beta.app`.
- Für den Cleanup-Schritt: Apple Intelligence aktiviert (Standard) oder `claude` bzw. `codex` CLI eingeloggt.

## Installation

```bash
brew install --cask t1mdotcom/tap/trace-mem
```

Die App ist selbstsigniert und nicht notarisiert, Gatekeeper blockt den ersten Start. Freigeben über Systemeinstellungen → Datenschutz & Sicherheit → „Trotzdem öffnen“, oder:

```bash
xattr -dr com.apple.quarantine /Applications/trace-mem.app
```

Danach im Menubar-Menü Mikrofon und Bedienungshilfen erlauben.

## Bauen und starten

```bash
scripts/run.sh            # Debug-Build → build/trace-mem.app → open
scripts/bundle.sh release # nur bauen und signieren
swift test                # Unit-Tests
```

Das Projekt ist ein reines SwiftPM-Paket. `Package.swift` lässt sich direkt in Xcode öffnen, ein `.xcodeproj` gibt es absichtlich nicht.

### Code-Signatur und Berechtigungen

Die App braucht zwei Berechtigungen, beide werden im Menubar-Menü angezeigt und lassen sich dort anfordern:

| Berechtigung | Wofür |
|---|---|
| Mikrofon | Aufnahme |
| Bedienungshilfen | Globaler Hotkey (CGEvent-Tap) und Einfügen per ⌘V |
| Systemaudio aufnehmen | Meeting-Modus, wird beim ersten Meeting abgefragt |

macOS bindet die Freigabe für Bedienungshilfen an die Code-Signatur. Eine Ad-hoc-Signatur ändert sich bei jedem Build, die Freigabe wird dann still ungültig. `scripts/bundle.sh` signiert deshalb mit einem selbstsignierten Zertifikat namens `trace-mem dev`, wenn es im Login-Keychain liegt, sonst ad-hoc. Einmalig anlegen:

```bash
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
  -subj "/CN=trace-mem dev" -addext "keyUsage=digitalSignature" -addext "extendedKeyUsage=codeSigning"
openssl pkcs12 -export -out dev.p12 -inkey key.pem -in cert.pem -passout pass:x
security import dev.p12 -k ~/Library/Keychains/login.keychain-db -P x -T /usr/bin/codesign
rm key.pem dev.p12
```

Falls die Freigabe trotzdem hängt: `tccutil reset Accessibility dev.theinemann.trace-mem`, App neu starten, erneut erteilen.

Beim ersten Start lädt macOS das Sprachmodell für die eingestellte Sprache. Der Fortschritt steht in der Statuszeile des Menüs, bis dahin ist die Aufnahme blockiert.

## Bedienung

Alles läuft über das Menubar-Icon (Wellenform):

- **Statuszeile**: Bereit, Aufnahme, Transkribiere, Blockiert. Bei Fehlern steht der Grund dahinter.
- **Berechtigungen**: Häkchen wenn erteilt, sonst Klick zum Anfordern.
- **Hotkey ändern…**: öffnet ein Fenster "Taste drücken". Einzelner Modifier (z. B. rechte ⌥), Kombination (z. B. ⌥ Leertaste) oder eine Taste (z. B. F5). Esc bricht ab, ⌘Q und ⌘W sind gesperrt.
- **Modus**: Halten zum Sprechen oder Drücken für Start/Stopp.
- **Text-Cleanup**: Apple Intelligence (on-device), Claude CLI, Codex CLI oder Aus.
- **Meeting-Zusammenfassung**: eigener Provider oder "Wie Text-Cleanup".
- **Meeting aufnehmen / beenden**: siehe oben.
- **Sprache**: System, Deutsch oder English.
- **Mikrofon**: Automatisch (eingebautes Mikrofon bevorzugt) oder ein festes Gerät. Bluetooth-Mikros wie AirPods werden nie automatisch gewählt, weil sie sonst auf das schlechtere HFP-Profil umschalten und die Wiedergabe leidet.
- **Beenden**.

Standard-Hotkey bis zur ersten Änderung: rechte ⌥ halten.

## Einstellungen

`~/Library/Application Support/trace-mem/settings.json`, wird von der App geschrieben:

```json
{
  "provider": "apple",
  "summaryProvider": null,
  "model": null,
  "hotkey": { "keyCode": 61, "modifiers": 0, "isModifierKey": true, "mode": "hold" },
  "locale": null,
  "cleanupTimeoutMs": 3000,
  "inputDeviceUID": null
}
```

- `provider`: `apple` (Standard), `claude`, `codex` oder `none`. `model` gilt nur für die CLI-Provider.
- `summaryProvider`: Provider für die Meeting-Zusammenfassung, `null` = wie `provider`. Praktisch: Cleanup on-device, Zusammenfassung über Claude.
- `cleanupTimeoutMs`: gilt für Apple. CLI-Provider brauchen Prozessstart plus Netz und bekommen mindestens 15 s.
- `locale`: z. B. `de-DE` oder `en-US`. `null` nimmt die Systemsprache.
- `hotkey.keyCode`: macOS Virtual Keycode, `modifiers`: CGEventFlags-Maske.
- `inputDeviceUID`: `uniqueID` eines Audio-Eingabegeräts. `null` nimmt das eingebaute Mikrofon, sonst den System-Standard.

## Aufbau

```
Sources/TraceMem/
  main.swift              NSApplication ohne Dock-Icon (LSUIElement)
  AppDelegate.swift       Menubar, Zustandsautomat, Pipeline hotkey → dictation → inject
  Permissions.swift       Mikrofon + Bedienungshilfen prüfen/anfordern, Settings-Links
  Settings.swift          Codable-Settings, JSON-Persistenz
  HotkeyMatcher.swift     reine Zustandsmaschine: Event → start/stop/none, testbar
  HotkeyTap.swift         CGEvent-Tap, ruft Matcher, re-enabled sich bei Timeout
  HotkeyCapture.swift     Zustandsmaschine für "Taste drücken", Anzeigenamen
  HotkeyCapturePanel.swift Fenster für die Hotkey-Aufnahme (lokaler NSEvent-Monitor)
  Dictation.swift         Mikrofon → SpeechAnalyzer → Text, Asset-Download
  IndicatorPanel.swift    Floating-HUD mit Pegel und Zwischentext
  Injector.swift          Pasteboard-Snapshot, ⌘V, Restore
  MicSelection.swift      Mikrofonwahl: Nutzer → eingebaut → Standard
  Cleanup.swift           Text-Cleanup und Meeting-Zusammenfassung: Apple FoundationModels / claude / codex
  SystemAudioTap.swift    Core Audio Process Tap → PCM-Chunks
  MeetingSession.swift    Mikrofon + System-Tap → zwei Transcriber → TranscriptWriter
  TranscriptWriter.swift  chronologisches, inkrementelles Markdown
  Diag.swift              Log nach ~/Library/Logs/trace-mem.log und Unified Logging
Tests/TraceMemTests/      Matcher, Capture, Settings, Pasteboard, Cleanup, TranscriptWriter, Buffer-Copy
Resources/Info.plist      Bundle-ID dev.theinemann.trace-mem, Usage-Descriptions
Resources/AppIcon.icns    App-Icon, erzeugt von scripts/make-icon.swift
scripts/bundle.sh         swift build → .app → codesign
scripts/run.sh            bundle + open
scripts/make-icon.swift   rendert das Icon neu (swift scripts/make-icon.swift, dann iconutil)
scripts/release.sh        Tag, GitHub-Release, Cask-Bump
packaging/trace-mem.rb    Homebrew-Cask
SPEC.md                   Ziel, Constraints, Interfaces, Invarianten, Tasks, Bugs
```

Die Logik, die sich ohne Hardware testen lässt (Hotkey-Matching, Capture, Settings, Pasteboard), ist von AppKit getrennt und hat Unit-Tests. Der Rest wird manuell getestet.

## Entwicklung

`SPEC.md` ist die Quelle für Anforderungen. Sie ist in einer verdichteten Notation geschrieben (§G Ziel, §C Constraints, §I Interfaces, §V Invarianten, §T Tasks mit Status, §B Bugs). Jede Aufgabe wird gegen die zitierten Invarianten gebaut und einzeln committed. Bugs bekommen einen Eintrag in §B und, wenn sinnvoll, eine neue Invariante in §V.

Logs: `~/Library/Logs/trace-mem.log` (Klartext, für Fehlerberichte) und Unified Logging unter dem Subsystem `dev.theinemann.trace-mem`.

## Release

```bash
scripts/release.sh 0.2.0 [../homebrew-tap]
```

Läuft nur auf sauberem, mit `origin/main` synchronem `main`. Schritte: Tests, Release-Build mit Version im Info.plist, Zip, Git-Tag, GitHub-Release mit generierten Notes, Cask-Bump in `packaging/trace-mem.rb`, Kopie nach `<tap>/Casks/` und Push. Der Tap ist das Repo `t1mdotcom/homebrew-tap`.

Release-Builds laufen lokal, weil GitHub-Runner noch kein Xcode 27 haben. Notarisierung fehlt, dafür wäre eine Apple Developer ID nötig. Dann nur die Signing-Identität in `scripts/bundle.sh` tauschen.

## Nicht im Umfang

Cloud-STT, Whisper, Sprecher-Diarization innerhalb einer Audioquelle, eigenes Vokabular, App-Store-Vertrieb, andere Plattformen.
