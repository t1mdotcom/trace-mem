# trace-mem — Projektregeln für Claude

macOS-Menubar-App (Push-to-talk-Diktat, später Meeting-Transkription). Swift 6, SwiftPM, Apple-Frameworks only.

## Quelle der Wahrheit

`SPEC.md` (Caveman-Notation). Anforderungen, Invarianten (§V), Tasks (§T), Bugs (§B). Änderungen an der Spec nur über den `spec`-Skill, Implementierung über `build`. Der `build`-Skill flippt nur §T-Status.

## Bauen, testen, starten

```bash
swift test                 # Unit-Tests, muss vor jedem Commit grün sein
scripts/bundle.sh debug    # → build/trace-mem.app (signiert mit "trace-mem dev" oder ad-hoc)
scripts/run.sh             # bundle + open; vorher pkill -x trace-mem
```

Kein `.xcodeproj` anlegen. `Package.swift` ist Xcode-fähig.

## Regeln

- Target macOS 27+, Swift Language Mode 6 mit strikter Concurrency. UI-Klassen sind `@MainActor`. Globale C-Konstanten wie `kAXTrustedCheckOptionPrompt` sind nicht concurrency-safe, String-Literal nutzen.
- Reine Logik (Matcher, Capture, Settings, Pasteboard-Snapshot) bleibt AppKit-frei und bekommt einen Test in `Tests/TraceMemTests/`. Hardware-nahes (Tap, Mikrofon, Panel) wird manuell getestet.
- Keine neuen SPM-Dependencies ohne Eintrag in `SPEC.md §C`.
- Audio verlässt nie das Gerät (V1). Nur Text darf an `claude`/`codex` CLI gehen.
- Bei Fehlern: Grund in `lastError` setzen und `state = .blocked`, damit er in der Menü-Statuszeile steht (V4). Kein stilles Fehlschlagen.
- Deutsch für Nutzertexte in der UI, Englisch für Code, Kommentare und Commit-Subjects. Commit-Body deutsch.

## Signatur und TCC

Nach einem Rebuild verliert eine ad-hoc-signierte App die Bedienungshilfen-Freigabe. `scripts/bundle.sh` nutzt das Zertifikat `trace-mem dev` aus dem Login-Keychain, wenn vorhanden. Hängt die Freigabe trotzdem: `tccutil reset Accessibility dev.theinemann.trace-mem`.

## Git

GitHub Flow: Feature-Branch von `main`, ein Commit pro abgeschlossener §T-Task (`T<n>: <was>` + zitierte §V). Kein direkter Commit auf `main`. Remote ist GitHub, PR via `gh`.

## Logs

```bash
log show --last 5m --predicate 'subsystem == "dev.theinemann.trace-mem"' --style compact
```
