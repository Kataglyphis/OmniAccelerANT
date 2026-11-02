#!/usr/bin/env bash
# The untimed setup of quality-report.sh --perf-host inside :latest: the release bundle and its model, as the launch smoke runs them; it times nothing.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"
# The image's Flutter SDK belongs to its own user; this script runs as container root.
git config --global --add safe.directory '*'
# Rootless nerdctl maps too few ids for the owners in Flutter's cache archives.
export TAR_OPTIONS=--no-same-owner
flutter config --enable-linux-desktop
bash third_party/OxidANT/scripts/linux/fetch-models.sh
CARGO_INCREMENTAL=0 flutter build linux --release
bash scripts/linux/bundle-runtime-closure.sh --arch x64 --build-mode release
