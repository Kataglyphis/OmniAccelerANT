#!/usr/bin/env bash
set -euo pipefail

VERSION="3.1.5"
OUT_DIR="web"
OUT_FILE="${OUT_DIR}/sqlite3.wasm"

mkdir -p "${OUT_DIR}"

URL="https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-${VERSION}/sqlite3.wasm"

echo "Downloading ${URL} -> ${OUT_FILE}"

curl -L --fail --retry 3 --retry-delay 1 -o "${OUT_FILE}" "${URL}"

echo "Done. You can now run: flutter run -d chrome"
