# trace-mem

Push-to-talk-Diktat für macOS, vollständig on-device. Taste halten, sprechen, loslassen: der Text landet in der gerade fokussierten App. Vorbild ist Wispr Flow, nur ohne Cloud.

Phase 2 (in Arbeit, siehe `SPEC.md`): Meeting-Transkription aus Mikrofon und System-Audio als Markdown-Datei.

## Was es tut

1. Globaler Hotkey (frei wählbar, Modifier oder Tastenkombination, Halten- oder Umschalt-Modus) startet die Aufnahme.
2. Das Mikrofon geht direkt in Apples `SpeechAnalyzer` / `SpeechTranscriber`. Das Modell läuft lokal, Audio verlässt den Rechner nicht.
3. Ein kleines Panel unten in der Bildschirmmitte zeigt Pegel und Zwischentext.
4. Nach dem Loslassen wird der erkannte Text über die Zwischenablage und ein synthetisches ⌘V eingefügt. Der vorherige Inhalt der Zwischenablage wird danach wiederhergestellt.
5. Optionaler Text-Cleanup (Füllwörter, Interpunktion, gesprochene Befehle wie "neuer Absatz"). Standard ist Apples on-device Modell über das `FoundationModels`-Framework, alternativ `claude -p` oder `codex exec` als Subprozess mit dem bestehenden Abo-Login der CLI. Schlägt der Schritt fehl oder dauert er länger als das Timeout, wird der Rohtext eingefügt und der Grund steht in der Statuszeile.

## Voraussetzungen

- macOS 27 oder neuer, Apple Silicon. Grund: `CaptureInputSequenceProvider` aus dem Speech-Framework gibt es erst ab 27.
- Xcode 27 (Beta reicht). `xcode-select -p` muss auf Xcode zeigen, sonst nutzt `scripts/bundle.sh` automatisch `/Applications/Xcode-beta.app`.
- Für den Cleanup-Schritt: Apple Intelligence aktiviert (Standard) oder `claude` bzw. `codex` CLI eingeloggt.

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
- **Beenden**.

Standard-Hotkey bis zur ersten Änderung: rechte ⌥ halten.

## Einstellungen

`~/Library/Application Support/trace-mem/settings.json`, wird von der App geschrieben:

```json
{
  "provider": "apple",
  "model": null,
  "hotkey": { "keyCode": 61, "modifiers": 0, "isModifierKey": true, "mode": "hold" },
  "locale": null,
  "cleanupTimeoutMs": 3000
}
```

- `provider`: `apple` (Standard), `claude`, `codex` oder `none`. `model` gilt nur für die CLI-Provider.
- `locale`: z. B. `de-DE` oder `en-US`. `null` nimmt die Systemsprache.
- `hotkey.keyCode`: macOS Virtual Keycode, `modifiers`: CGEventFlags-Maske.

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
  Cleanup.swift           Text-Cleanup: Apple FoundationModels / claude / codex, Timeout, Fallback
Tests/TraceMemTests/      Matcher, Capture, Settings, Pasteboard-Snapshot, Cleanup
Resources/Info.plist      Bundle-ID dev.theinemann.trace-mem, Usage-Descriptions
scripts/bundle.sh         swift build → .app → codesign
scripts/run.sh            bundle + open
SPEC.md                   Ziel, Constraints, Interfaces, Invarianten, Tasks, Bugs
```

Die Logik, die sich ohne Hardware testen lässt (Hotkey-Matching, Capture, Settings, Pasteboard), ist von AppKit getrennt und hat Unit-Tests. Der Rest wird manuell getestet.

## Entwicklung

`SPEC.md` ist die Quelle für Anforderungen. Sie ist in einer verdichteten Notation geschrieben (§G Ziel, §C Constraints, §I Interfaces, §V Invarianten, §T Tasks mit Status, §B Bugs). Jede Aufgabe wird gegen die zitierten Invarianten gebaut und einzeln committed. Bugs bekommen einen Eintrag in §B und, wenn sinnvoll, eine neue Invariante in §V.

Logs:

```bash
log show --last 5m --predicate 'subsystem == "dev.theinemann.trace-mem"' --style compact
```

## Nicht im Umfang

Cloud-STT, Whisper, Sprecher-Diarization, eigenes Vokabular, App-Store-Vertrieb, andere Plattformen.
