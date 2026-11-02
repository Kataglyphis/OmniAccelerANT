#!/usr/bin/env bash
# Argument and target checks the Linux GPU candidate scripts share; they prove nothing about GPU execution.

GPU_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export GPU_SCRIPT_DIR

# gpu_die <status> <message>: stops the whole script, so call it in the main shell and not inside a substitution.
gpu_die() {
  echo "$2" >&2
  exit "$1"
}

# gpu_require_argc <count> <min> <max> <usage>: a wrong call stops with exit 2 before anything is touched.
gpu_require_argc() {
  if (($1 < $2 || $1 > $3)); then
    echo "usage: $4" >&2
    exit 2
  fi
}

# gpu_target_facts <vendor> <arch>: prints machine, DEB architecture and provider; an unsupported pair fails.
gpu_target_facts() {
  case "$1:$2" in
    nvidia:x64) echo 'x86_64 amd64 cuda' ;;
    nvidia:arm64) echo 'aarch64 arm64 cuda' ;;
    amd:x64) echo 'x86_64 amd64 migraphx' ;;
    *) echo 'Unsupported GPU candidate' >&2; return 2 ;;
  esac
}

# gpu_deb_field_is <deb> <field> <expected>
gpu_deb_field_is() {
  if [[ "$(dpkg-deb --field "$1" "$2")" == "$3" ]]; then return 0; fi
  return 1
}
