#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -x trace-mem 2>/dev/null || true
APP="$(scripts/bundle.sh "${1:-debug}")"
open "$APP"
