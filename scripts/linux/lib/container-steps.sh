#!/usr/bin/env bash

_container_steps_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/containerhub.sh
source "${_container_steps_dir}/containerhub.sh"

# Canonical boolean predicate (is_truthy) and info/warn/err logging come from
# ContainerHub instead of being redefined here.
containerhub_source linux/scripts/01-core/platform.sh
containerhub_source linux/scripts/01-core/logging.sh

maybe_truthy() {
  # Thin alias over upstream's is_truthy(), the same delegation pattern
  # ContainerHub's own _bool_truthy() uses. It keeps the two extra spellings
  # this repo has always accepted and is_truthy does not — a bare "y", and
  # mixed case such as "True" — so no call site changes meaning.
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

# ContainerHub's versions.env pins FLUTTER_VERSION (:323) and FLUTTER_SDK_SHA256
# (:700) as ONE pin. Resolve BOTH from that one file so they cannot disagree,
# and export the sha: ContainerHub's setup-flutter.sh only falls back to the
# copy baked into the image (/opt/scripts/core/versions.env, Dockerfile.sdk:111)
# when the sha is unset in the environment, and that copy tracks a floating
# image tag rather than our submodule pointer. The native/android lanes already
# export it via packaging-common.sh -> common.sh; the web lane does not, which
# is why it alone used to read the image's copy.
#
# Single-key sed, not load_versions_env: that loader exports all ~174 keys, and
# setup-flutter.sh reads these same two keys exactly this way.
#
# Sets FLUTTER_VERSION when it is empty. Call it as a plain command, never in
# $(...) — a command-substitution subshell would discard the export.
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
    # An explicit --flutter-version is a deliberate one-off. Do NOT export the
    # pinned sha for it: it belongs to ${pinned_version}, and leaving it unset
    # lets setup-flutter.sh report the mismatch by name instead of emitting a
    # bare "Checksum verification FAILED".
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

  # Resolved absolutely (containerhub_path), so this no longer silently depends
  # on the caller's working directory being the repo root.
  chmod +x "$setup_script"
  "$setup_script" "$flutter_version" "$(dirname "${flutter_dir}")"

  chmod -R u+rwX "${flutter_dir}/bin/cache" 2>/dev/null || true
  chmod -R u+rwX "${flutter_dir}" 2>/dev/null || true
}

run_flutter_common_checks() {
  local strict_mode="${1:-0}"
  flutter pub get
  run_check_cmd "$strict_mode" dart format --output=none --set-exit-if-changed .
  run_check_cmd "$strict_mode" dart analyze
  run_check_cmd "$strict_mode" flutter test
}

export_toolchain_env() {
  export CC=clang
  export CXX=clang++

  local gcc_toolchain_root="${MYPROJECT_GCC_TOOLCHAIN_PATH:-/opt/gcc-15.2.0}"
  local gcc_toolchain_lib=""

  if [[ -d "$gcc_toolchain_root" ]]; then
    if [[ -d "$gcc_toolchain_root/lib64" ]]; then
      gcc_toolchain_lib="$gcc_toolchain_root/lib64"
    elif [[ -d "$gcc_toolchain_root/lib" ]]; then
      gcc_toolchain_lib="$gcc_toolchain_root/lib"
    fi

    export CFLAGS_x86_64_unknown_linux_gnu="--gcc-toolchain=${gcc_toolchain_root} ${CFLAGS:-}"
    export CFLAGS_aarch64_unknown_linux_gnu="--gcc-toolchain=${gcc_toolchain_root} ${CFLAGS:-}"
    export CFLAGS="--gcc-toolchain=${gcc_toolchain_root} ${CFLAGS:-}"
    export CXXFLAGS_x86_64_unknown_linux_gnu="--gcc-toolchain=${gcc_toolchain_root} ${CXXFLAGS:-}"
    export CXXFLAGS_aarch64_unknown_linux_gnu="--gcc-toolchain=${gcc_toolchain_root} ${CXXFLAGS:-}"
    export CXXFLAGS="--gcc-toolchain=${gcc_toolchain_root} ${CXXFLAGS:-}"

    if [[ -n "$gcc_toolchain_lib" ]]; then
      export LDFLAGS="-L${gcc_toolchain_lib} -Wl,-rpath,${gcc_toolchain_lib} --gcc-toolchain=${gcc_toolchain_root} ${LDFLAGS:-}"
    else
      export LDFLAGS="--gcc-toolchain=${gcc_toolchain_root} ${LDFLAGS:-}"
    fi
  fi
}
