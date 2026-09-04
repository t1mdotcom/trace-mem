#!/usr/bin/env bash
# Builds build/trace-mem.app from the SwiftPM executable and ad-hoc signs it.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/TraceMem"

APP=build/trace-mem.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/trace-mem"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# ponytail: ad-hoc signature changes every build → TCC (mic/accessibility) re-prompts.
# Upgrade path: self-signed "trace-mem dev" cert in login keychain, sign with it.
codesign --force --sign - "$APP"
echo "$APP"
