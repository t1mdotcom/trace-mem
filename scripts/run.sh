#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -x trace-mem 2>/dev/null || true
APP="$(scripts/bundle.sh "${1:-debug}" | tail -1)" # bundle.sh also prints swift build output; last line = path
open "$APP"
