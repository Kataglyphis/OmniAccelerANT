#!/usr/bin/env bash

_container_steps_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/containerhub.sh
source "${_container_steps_dir}/containerhub.sh"

containerhub_source linux/scripts/01-core/platform.sh
containerhub_source linux/scripts/01-core/logging.sh

# is_truthy plus a bare "y" and mixed case.
maybe_truthy() {
  local value="${1:-}"
  is_truthy "${value,,}" || [[ "${value,,}" == "y" ]]
}

run_check_cmd() {
  local strict_mode="${1:-0}"
  shift
  if maybe_truthy "$strict_mode"; then
    "$@"
  else
    "$@" || true
  fi
}

git_safe_dirs() {
  local flutter_dir="${1:-}"
  git config --global --add safe.directory /workspace || true
  if [[ -n "$flutter_dir" ]]; then
    git config --global --add safe.directory "$flutter_dir" || true
  fi
}

source_bashrc_and_add_flutter_to_path() {
  local flutter_dir="${1:-}"
  local original_flags="$-"
  set +u
  source ~/.bashrc 2>/dev/null || true
  if [[ "$original_flags" =~ u ]]; then set -u; fi
  if [[ -n "$flutter_dir" ]]; then
    export PATH="${flutter_dir}/bin:$PATH"
  fi
}

# Resolves FLUTTER_VERSION + its sha256 from ContainerHub versions.env.
# Call as a plain command, never in $(...) — see AGENTS.md § 4.
resolve_flutter_pin() {
  local versions_env pinned_version pinned_sha
  versions_env="$(containerhub_path linux/scripts/01-core/versions.env)" || return 1
  pinned_version="$(sed -n 's/^FLUTTER_VERSION=//p' "$versions_env")"
  pinned_sha="$(sed -n 's/^FLUTTER_SDK_SHA256=//p' "$versions_env")"

  if [[ -z "$pinned_version" || -z "$pinned_sha" ]]; then
    echo "Error: FLUTTER_VERSION/FLUTTER_SDK_SHA256 are not both pinned in" >&2
    echo "       ${versions_env}. ContainerHub owns this pin; if a key was" >&2
    echo "       renamed upstream, fix it here." >&2
    return 1
  fi

  if [[ -n "${FLUTTER_VERSION:-}" ]]; then
    # Deliberately leaves the sha unset — AGENTS.md § 4.
    return 0
  fi

  FLUTTER_VERSION="$pinned_version"
  export FLUTTER_SDK_SHA256="$pinned_sha"
  echo "[Info] Flutter ${FLUTTER_VERSION} (pinned in ${versions_env})." >&2
}

setup_flutter_sdk() {
  local flutter_version="${1:?flutter_version is required}"
  local flutter_dir="${2:?flutter_dir is required}"
  local matrix_arch="${3:?matrix_arch is required (x64|arm64)}"

  local setup_script
  if [[ "$matrix_arch" == "x64" ]]; then
    setup_script="$(containerhub_path linux/scripts/setup-flutter-x86-64.sh)" || return 1
  else
    setup_script="$(containerhub_path linux/scripts/setup-flutter-arm64.sh)" || return 1
  fi

  chmod +x "$setup_script"
  "$setup_script" "$flutter_version" "$(dirname "${flutter_dir}")"

  chmod -R u+rwX "${flutter_dir}/bin/cache" 2>/dev/null || true
  chmod -R u+rwX "${flutter_dir}" 2>/dev/null || true
}

# Lists tracked files rather than walking the tree — AGENTS.md § 3.
run_flutter_common_checks() {
  local strict_mode="${1:-0}" strict_flag
  shift || true
  if maybe_truthy "$strict_mode"; then strict_flag=true; else strict_flag=false; fi
  bash "$(containerhub_path linux/scripts/05-frameworks/flutter/flutter_checks.sh)" --strict "$strict_flag" "$@"
}

# AGENTS.md § 3.
setup_compiler_cache() {
  containerhub_source linux/scripts/01-core/compiler-cache.sh
  setup_sccache
  echo "[Info] SCCACHE_DIR=${SCCACHE_DIR:-<unset>}  RUSTC_WRAPPER=${RUSTC_WRAPPER:-<unset>}"
}

# The image ships the SDK but announces it nowhere — AGENTS.md § 3.
export_android_gstreamer_env() {
  if [ -n "${GSTREAMER_ROOT_ANDROID:-}" ] && [ -d "${GSTREAMER_ROOT_ANDROID}" ]; then
    return 0
  fi
  local candidate
  for candidate in /opt/android/gstreamer /opt/gstreamer-android; do
    if [ -d "$candidate" ]; then
      export GSTREAMER_ROOT_ANDROID="$candidate"
      echo "[Info] GSTREAMER_ROOT_ANDROID=$candidate"
      return 0
    fi
  done
  echo "[Warn] No Android GStreamer SDK found; the native plugin will not configure." >&2
  return 0
}

export_toolchain_env() {
  export CC=clang
  export CXX=clang++
  containerhub_source linux/scripts/01-core/cross-gcc.sh
  export_clang_gcc_toolchain_env
}
