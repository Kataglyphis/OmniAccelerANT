#!/usr/bin/env bash
# Bash twin of scripts/windows/Resolve-BuildModule.ps1: the one file that finds
# the Kataglyphis-ContainerHub submodule, so every other script can source
# upstream libraries by name instead of re-implementing them.
#
# Bash consumers have no bootstrap problem the way PowerShell does — they source
# by relative path — but they DO have a working-directory problem: the relative
# paths used before only resolved when the caller happened to be in the repo
# root. This resolves from ${BASH_SOURCE[0]}, so it works from anywhere, and
# fails loudly with the `git submodule update` hint when the submodule is not
# checked out.

[ -n "${_KATAGLYPHIS_CONTAINERHUB_SH_LOADED:-}" ] && return 0
_KATAGLYPHIS_CONTAINERHUB_SH_LOADED=1

_containerhub_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts/linux/lib -> repo root
KATAGLYPHIS_REPO_ROOT="${KATAGLYPHIS_REPO_ROOT:-$(cd "${_containerhub_lib_dir}/../../.." && pwd)}"
CONTAINERHUB_DIR="${CONTAINERHUB_DIR:-${KATAGLYPHIS_REPO_ROOT}/ExternalLib/Kataglyphis-ContainerHub}"
export KATAGLYPHIS_REPO_ROOT CONTAINERHUB_DIR

# Absolute path of a file inside the submodule, or a hard failure naming it.
containerhub_path() {
  local relative_path="${1:?relative path required}"
  local resolved="${CONTAINERHUB_DIR}/${relative_path}"
  if [[ ! -e "$resolved" ]]; then
    echo "Error: ContainerHub file not found: ${resolved}" >&2
    echo "       The submodule is probably not checked out:" >&2
    echo "       git submodule update --init --recursive ExternalLib/Kataglyphis-ContainerHub" >&2
    return 1
  fi
  printf '%s' "$resolved"
}

# Source a ContainerHub shell library, e.g.
#   containerhub_source linux/scripts/01-core/logging.sh
# Upstream libraries are load-guarded, so sourcing one twice is free.
containerhub_source() {
  local resolved
  resolved="$(containerhub_path "${1:?relative path required}")" || return 1
  # shellcheck disable=SC1090
  source "$resolved"
}
