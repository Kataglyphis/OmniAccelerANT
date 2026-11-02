#!/usr/bin/env bash
# Browser gates run from the repo root with the hub's HTTP wait loaded; it starts no server.
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/antfrastructure.sh"
antfrastructure_source linux/scripts/01-core/http-readiness.sh
cd "${KATAGLYPHIS_REPO_ROOT}" || exit
