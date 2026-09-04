#!/usr/bin/env bash
# Usage: scripts/release.sh 0.2.0 [path/to/homebrew-tap]
# Builds, tags, publishes a GitHub release and bumps the Homebrew cask.
set -euo pipefail
cd "$(dirname "$0")/.."

V="${1:?version required, e.g. 0.2.0}"
TAP="${2:-../homebrew-tap}"

# V14: clean tree on main only
[[ "$(git branch --show-current)" == main ]] || { echo "not on main"; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo "uncommitted changes"; exit 1; }
git fetch -q origin && [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "main not in sync with origin"; exit 1; }
git rev-parse "v$V" >/dev/null 2>&1 && { echo "tag v$V exists"; exit 1; }

swift test
APP="$(VERSION="$V" scripts/bundle.sh release | tail -1)"
ZIP="build/trace-mem-$V.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

git tag -a "v$V" -m "v$V"
git push origin "v$V"
gh release create "v$V" "$ZIP" --title "v$V" --generate-notes

# cask bump in this repo
sed -i '' -e "s/^  version \".*\"/  version \"$V\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" packaging/trace-mem.rb
git add packaging/trace-mem.rb
git commit -q -m "release: bump cask to v$V"
git push origin main

# publish cask to the tap
if [[ -d "$TAP/.git" ]]; then
    mkdir -p "$TAP/Casks"
    cp packaging/trace-mem.rb "$TAP/Casks/trace-mem.rb"
    git -C "$TAP" add Casks/trace-mem.rb
    git -C "$TAP" commit -q -m "trace-mem $V"
    git -C "$TAP" push
    echo "cask published: brew install --cask t1mdotcom/tap/trace-mem"
else
    echo "tap repo not found at $TAP – copy packaging/trace-mem.rb to <tap>/Casks/ manually"
fi
echo "released v$V ($SHA)"
