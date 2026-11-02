#!/usr/bin/env bash
# Argument and target checks the Linux GPU candidate scripts share; they prove nothing about GPU execution.

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
