#!/usr/bin/env bash
set -euo pipefail

# Fetches the pinned sqlite3.wasm into web/ so the app can run on Chrome.
#
#   bash scripts/setup-sqlite3-wasm.sh
#
# THIS IS A WRAPPER over ContainerHub's
# linux/scripts/05-frameworks/flutter/setup-sqlite3-wasm.sh. The 16 lines it
# replaces were a plain `curl -L --fail` with the version written into the
# script — the same 16 lines jotrockenmitlocken carries, already drifted apart
# (3.3.1 here, 3.2.0 there) on the only thing that mattered, and neither copy
# verified what it downloaded. An unauthenticated binary that then executes in
# every visitor's browser is exactly what download_verified_file exists for.
#
# The version is NOT a parameter and is not set here on purpose: SQLITE3_WASM_VERSION
# and its SQLITE3_WASM_SHA256 live in ContainerHub's 01-core/versions.env with
# every other pinned artifact in the fleet, and a tampered or truncated asset now
# fails at download time instead of in a browser. The pinned version is 3.3.1 —
# the same one this file used to hard-code, so adopting changes no bytes here.
# To move it, bump versions.env upstream, where the matching SHA lives.
#
# The verification is not theoretical. web/sqlite3.wasm IS tracked, and the blob
# that was committed (733662 bytes, sha256 c41558c7...) is NOT the 3.3.1 release
# asset this script has claimed to fetch since the version line was last bumped
# (744124 bytes, sha256 3c616bf0...). An unverified `curl -o` cannot tell those
# apart; download_verified_file cannot miss it.

_setup_sqlite3_wasm_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# containerhub.sh lives one level down, in linux/lib, and resolves the repo root
# from ITS own location — scripts/linux/lib -> root is three levels.
# shellcheck source=scripts/linux/lib/containerhub.sh
source "${_setup_sqlite3_wasm_dir}/linux/lib/containerhub.sh"

# The consumer root is mandatory upstream and never inferred: the script runs
# from inside third_party/ContainerHub, where a location-derived root would drop
# sqlite3.wasm into the submodule's own tree and the app would still not start.
containerhub_exec linux/scripts/05-frameworks/flutter/setup-sqlite3-wasm.sh \
	"$KATAGLYPHIS_REPO_ROOT"
