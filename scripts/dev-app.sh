#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/scripts/build-app.sh"
osascript -e 'tell application id "local.waid.app" to quit' >/dev/null 2>&1 || true
sleep 1
open "$ROOT_DIR/dist/Waid.app"
