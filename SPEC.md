# trace-mem — SPEC

## §G Goal

macOS-native voice input à la Wispr Flow. Hold hotkey → speak → text lands in focused app. Phase 2: meeting transcription (mic + system audio) → Markdown.

## §C Constraints

- Target: macOS ≥ 27, arm64 (`CaptureInputSequenceProvider` needs 27). Dev box: macOS 27, Xcode 27.0 beta @ `/Applications/Xcode-beta.app`, Swift 6.4. `xcode-select` currently → CLT ∴ scripts set `DEVELOPER_DIR` explicitly | user runs `sudo xcode-select -s /Applications/Xcode-beta.app`.
- STT ! on-device: Apple Speech `SpeechAnalyzer` + `SpeechTranscriber`. ⊥ Whisper, ⊥ cloud STT. Reason: Claude/Codex subs have no STT API.
- LLM cleanup ? optional. Providers: `apple` (FoundationModels `LanguageModelSession`, on-device, **default**) | `claude` (subprocess `claude -p --model haiku`) | `codex` (subprocess `codex exec`) | `none`. CLI providers use existing sub login. ⊥ API keys in app.
- Build: SwiftPM package (`Package.swift`, openable in Xcode directly) + `scripts/bundle.sh` → `.app` w/ Info.plist, ad-hoc codesign. ⊥ `.xcodeproj` (SwiftPM suffices; Xcode = editor/debugger).
- Menubar app (`NSStatusItem`), `LSUIElement=true`, ⊥ dock icon, ⊥ main window in v1.
- Langs: de + en. Locale auto | setting.
- Out of scope: diarization, custom vocab UI, App Store, Windows/Linux. Notarization ? later (needs Developer ID; swap signing identity only).
- Distribution: GitHub Releases + Homebrew cask. Release build local (GH runners lack Xcode 27). CI ? when runner image ships Xcode 27.
- Deps: Apple frameworks only (AppKit, Speech, AVFoundation, CoreAudio, FoundationModels). ⊥ SPM deps unless §T says.

## §I Interfaces

- hotkey: user-defined key | modifier (⌥, ⌃, fn, F-keys, any keycode) w/ optional modifier mask. Mode `hold` (press→record, release→stop) | `toggle` (press→start, press→stop). `CGEvent` tap on keyDown/keyUp/flagsChanged. Default until user sets one: right ⌥ hold. ⊥ hardcoded.
- hotkey capture: menu item "Hotkey ändern…" → small panel "Taste drücken" → next key/modifier event recorded → saved. Esc cancels.
- inject: `NSPasteboard` set text → `CGEvent` ⌘V → restore prior pasteboard after 200ms.
- cleanup apple: `LanguageModelSession(instructions: prompt).respond(to: raw).content`; `SystemLanguageModel.default.isAvailable` false → V2 fallback + status reason.
- cleanup cmd (claude): `claude -p --model haiku --output-format text <prompt>` w/ raw on stdin → stdout text
- cleanup cmd (codex): `codex exec --quiet <prompt+raw>` → stdout text
- cleanup prompt: remove fillers (ähm, also, halt) · fix punctuation · apply spoken cmds ("neuer Absatz"→`\n\n`, "Komma"→`,`, "Punkt"→`.`) · keep language · output text only.
- settings: `~/Library/Application Support/trace-mem/settings.json` → `{provider: "apple"|"claude"|"codex"|"none" (default apple), model?: string, hotkey: {keyCode: int, modifiers: int, isModifierKey: bool, mode: "hold"|"toggle"}, locale?: string, cleanupTimeoutMs: 3000, inputDeviceUID?: string}`
- indicator: floating `NSPanel`, non-activating, bottom-center, shows waveform level + partial transcript.
- menubar menu: status (idle/recording/transcribing/cleanup) · Mikrofon submenu (Automatisch + device list, rebuilt on open) · Hotkey ändern… (shows current binding) · hold/toggle mode · toggle cleanup · provider picker · permissions status w/ "open System Settings" links · quit.
- meeting out (P2): `~/Documents/trace-mem/<YYYY-MM-DD_HH-mm>.md` → frontmatter `{start, end, duration}` + lines `[HH:MM:SS] Ich|Andere: text` + `## Zusammenfassung` ? if cleanup provider set.
- system audio (P2): `CATapDescription` process tap (all processes, stereo mix) → `AVAudioEngine`-free `AudioUnit` HAL input → PCM buffer stream.
- cmd: `scripts/bundle.sh` → `build/trace-mem.app` (uses `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` if `xcode-select -p` is CLT); `scripts/run.sh` → bundle + open.
- release: `scripts/release.sh <semver>` → `swift test` · release bundle w/ `VERSION` in plist · `build/trace-mem-<v>.zip` (ditto) · tag `v<v>` · `gh release create` w/ notes · bump `packaging/trace-mem.rb` (version, sha256) · push cask to tap repo `t1mdotcom/homebrew-tap` (`Casks/trace-mem.rb`).
- install: `brew install --cask t1mdotcom/tap/trace-mem`. Not notarized → caveats: right-click open | `xattr -dr com.apple.quarantine`.
- Info.plist keys ! `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `LSUIElement`, `NSAudioCaptureUsageDescription` (P2).

## §V Invariants

- V1: audio bytes ⊥ leave device. Only text → `claude`/`codex` CLI stdin/argv.
- V2: cleanup fail | timeout (≥ `cleanupTimeoutMs`) → inject raw transcript. Raw text ⊥ lost.
- V3: ∀ inject → prior pasteboard contents restored after paste.
- V4: missing permission (mic, speech, accessibility, audio capture) → menubar icon state + menu item w/ fix link. ⊥ silent fail.
- V5: hotkey release during transcription → still finalize + inject. ⊥ dropped utterance.
- V6: STT model download (`AssetInventory`) triggered on first launch, progress visible in menu. Recording blocked w/ visible reason until installed.
- V7: cleanup output empty | > 3× raw length → treat as fail → V2.
- V8: hotkey tap lost (`CGEvent` tap disabled by system) → auto re-enable + log.
- V9: P2 meeting file written incrementally (append per final segment). Crash ⊥ lose transcript so far.
- V10: P2 mic + system stream timestamps from same monotonic clock; merge order by start time.
- V11: single recording session at a time. Hotkey ignored while meeting mode active.
- V12: hotkey capture ⊥ accepts bare Esc, ⌘Q, ⌘W (system-critical). Rejected → panel shows reason.
- V15: mic input = user-selected device (`inputDeviceUID`) | built-in mic | system default, in that order. Bluetooth mic ⊥ auto-picked (avoids A2DP→HFP downgrade).
- V14: release ⊥ from dirty tree | non-main branch. Tag, zip, cask sha ! consistent for same version.
- V13: hotkey event consumed (⊥ passed to focused app) only when binding matched. All other events pass through untouched.

## §T Tasks

id|status|task|cites
T1|x|SwiftPM pkg `trace-mem`, executable target, `scripts/bundle.sh` w/ Info.plist + ad-hoc sign, `scripts/run.sh`|§C,I.cmd
T2|x|Menubar app skeleton: `NSStatusItem`, menu w/ status + quit, `LSUIElement`|I.menubar
T3|x|Permissions module: check/request mic, speech, accessibility; menu shows state + settings links|V4
T4|x|Hotkey: `CGEvent` tap keyDown/keyUp/flagsChanged, match against settings binding, hold + toggle mode → start/stop callbacks, re-enable on timeout|I.hotkey,V8,V13
T5|x|Audio capture: `CaptureInputSequenceProvider.providerWithSession(from: mic)` (Speech fw, macOS 27 SDK) wrapped in own `AsyncStream<AnalyzerInput>` for controlled end-of-input; level via `AVCaptureAudioChannel.averagePowerLevel`|V1
T6|x|STT: `SpeechAnalyzer` + `SpeechTranscriber`, locale de/en, asset install w/ progress, partial + final results stream|V6,V1
T7|x|Indicator panel: floating `NSPanel`, level + partial text, show on record, hide after inject|I.indicator
T8|x|Inject: pasteboard save → set → ⌘V via `CGEvent` → restore|I.inject,V3
T9|x|End-to-end wire: hold → record → release → finalize → inject raw. Manual test in TextEdit + Claude Code terminal|V5,V11
T10|x|Settings: load/save json, defaults, provider/model/hotkey/locale|I.settings
T11|x|Cleanup: providers apple (FoundationModels) / claude / codex via `Process`, shared prompt, timeout, sanity check, fallback raw|I.cleanup,V2,V7
T12|x|Menu: provider picker (apple/claude/codex/aus), status per phase|I.menubar
T12a|x|Hotkey capture panel: "Taste drücken", record next key/modifier, validate, save to settings, live re-bind|I.hotkey capture,V12
T13|x|Self-check: `swift test` → cleanup fallback logic (timeout, empty, oversize), pasteboard restore, hotkey matcher (modifier-only, key+mods, toggle state machine)|V2,V3,V7,V13
T14|~|P2: system audio tap via `CATapDescription` → PCM stream, `NSAudioCaptureUsageDescription`|I.system audio,V1
T15|.|P2: meeting mode: menu start/stop, 2× `SpeechTranscriber` (mic, system), merge by timestamp, labels Ich/Andere|V10,V11
T17|x|Release: `scripts/release.sh`, `VERSION` env in bundle.sh, `packaging/trace-mem.rb` cask, README install section|I.release,I.install,V14
T18|.|Tap repo `t1mdotcom/homebrew-tap` public w/ `Casks/trace-mem.rb`; first release v0.1.0; verify `brew install --cask`|I.install
T16|.|P2: incremental Markdown writer to `~/Documents/trace-mem/`, frontmatter, ? summary via cleanup provider|I.meeting out,V9

## §B Bugs

id|date|cause|fix
B1|2026-09-04|`AVCaptureDevice.default(for: .audio)` picks AirPods mic → BT switches A2DP→HFP, playback quality drops|V15
