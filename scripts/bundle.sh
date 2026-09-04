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
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
                            -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$APP/Contents/Info.plist"
fi

# Stable identity keeps TCC grants (Accessibility, Mic) across rebuilds. Ad-hoc = new cdhash per build.
# Create once: openssl self-signed cert CN="trace-mem dev" w/ codeSigning EKU, import into login keychain.
IDENTITY="$(security find-identity -v -p codesigning | grep -o '"trace-mem dev"' | head -1 | tr -d '"')"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "$APP"
