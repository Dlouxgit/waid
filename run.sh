#!/usr/bin/env bash

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Waid only runs on macOS."
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required."
  echo "Install Node.js, then run ./run.sh again."
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc was not found."
  echo "Install Apple's Command Line Tools with: xcode-select --install"
  exit 1
fi

echo "Starting Waid on http://127.0.0.1:4312"
echo "The first launch can take around 20 seconds while the macOS helper is compiled."

exec node server.js
