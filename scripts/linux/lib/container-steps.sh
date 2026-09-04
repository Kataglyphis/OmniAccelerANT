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

# Delegates to ContainerHub; its format gate lists tracked files, so it does not
# reformat the SDK that the lanes install at $PWD/flutter — AGENTS.md § 2.
run_flutter_common_checks() {
  local strict_mode="${1:-0}" strict_flag
  shift || true
  if maybe_truthy "$strict_mode"; then strict_flag=true; else strict_flag=false; fi
  bash "$(containerhub_path linux/scripts/05-frameworks/flutter/flutter_checks.sh)" --strict "$strict_flag" "$@"
}

# The image's RUSTUP_HOME is root-owned while the container runs as uid 1001,
# so rustup cannot write its temp files — AGENTS.md § 3. Hardlinks, so this
# costs nothing; a no-op once the image ships a writable rustup home.
ensure_writable_rustup_home() {
  local src="${RUSTUP_HOME:-/usr/local/rustup}"
  [ -d "$src" ] || return 0
  [ -w "$src/tmp" ] && return 0
  local dst="${KATAGLYPHIS_RUSTUP_HOME:-/tmp/rustup-home}"
  if [ ! -d "$dst" ]; then
    cp -al "$src" "$dst" 2>/dev/null || cp -a "$src" "$dst" || return 1
  fi
  export RUSTUP_HOME="$dst"
  echo "[Info] RUSTUP_HOME -> $dst (image copy is not writable for uid $(id -u))"
}

# The image ships the SDK at /opt/android-sdk but exports no ANDROID_HOME, and
# `flutter build apk` then reports "No Android SDK found" — AGENTS.md § 3.
resolve_android_sdk_home() {
  if [ -n "${ANDROID_HOME:-}" ] && [ -d "${ANDROID_HOME}" ]; then
    printf '%s' "$ANDROID_HOME"; return 0
  fi
  local d
  for d in "${ANDROID_SDK_ROOT:-}" /opt/android-sdk /usr/lib/android-sdk; do
    [ -n "$d" ] && [ -d "$d/platform-tools" ] && { printf '%s' "$d"; return 0; }
  done
  return 1
}

export_android_sdk_env() {
  local sdk
  sdk="$(resolve_android_sdk_home)" || {
    echo "[Warn] No Android SDK found; leaving ANDROID_HOME unset." >&2
    return 0
  }
  export ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="$sdk"
  echo "[Info] ANDROID_HOME=$sdk"
}

export_toolchain_env() {
  export CC=clang
  export CXX=clang++
  containerhub_source linux/scripts/01-core/cross-gcc.sh
  export_clang_gcc_toolchain_env
}
