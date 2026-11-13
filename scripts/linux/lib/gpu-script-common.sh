#!/usr/bin/env bash
# Argument and target checks the Linux GPU candidate scripts share; they prove nothing about GPU execution.

GPU_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export GPU_SCRIPT_DIR
# The hub's ORT_AMDGPU_EP_MODULE, repeated because the clean-host job checks out no hub; test-check-packaged-onnx-runtime.sh compares the two.
GPU_AMD_PLUGIN_MODULE=libmigraphx-ep.so
export GPU_AMD_PLUGIN_MODULE

# gpu_die <status> <message>: stops the whole script, so call it in the main shell and not inside a substitution.
gpu_die() {
  echo "$2" >&2
  exit "$1"
}

# gpu_assert_inside <path> <dir> <message>: a resolved path outside dir means the package loads someone else's bytes.
gpu_assert_inside() {
  case "$1" in "$2"/*) ;; *) gpu_die 1 "$3" ;; esac
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

# gpu_source_plugin_texts: OxidANT owns the AMD plugin's licence texts until the hub does; the exports keep its resolver on this repo's hub pin.
gpu_source_plugin_texts() {
  local repo
  repo="$(cd "$GPU_SCRIPT_DIR/../.." && pwd)" || return 1
  export KATAGLYPHIS_REPO_ROOT="$repo" ANTFRASTRUCTURE_DIR="${ANTFRASTRUCTURE_DIR:-$repo/third_party/ANTfrastructure}"
  # shellcheck source=third_party/OxidANT/scripts/linux/lib/ort-runtime-bundle.sh
  source "$repo/third_party/OxidANT/scripts/linux/lib/ort-runtime-bundle.sh"
}
