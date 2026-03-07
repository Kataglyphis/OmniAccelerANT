#!/usr/bin/env bash

maybe_truthy() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
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

setup_flutter_sdk() {
  local flutter_version="${1:?flutter_version is required}"
  local flutter_dir="${2:?flutter_dir is required}"
  local matrix_arch="${3:?matrix_arch is required (x64|arm64)}"

  if [[ "$matrix_arch" == "x64" ]]; then
    chmod +x ExternalLib/Kataglyphis-ContainerHub/linux/scripts/setup-flutter-x86-64.sh
    ./ExternalLib/Kataglyphis-ContainerHub/linux/scripts/setup-flutter-x86-64.sh "$flutter_version" "$(dirname "${flutter_dir}")"
  else
    chmod +x ExternalLib/Kataglyphis-ContainerHub/linux/scripts/setup-flutter-arm64.sh
    ./ExternalLib/Kataglyphis-ContainerHub/linux/scripts/setup-flutter-arm64.sh "$flutter_version" "$(dirname "${flutter_dir}")"
  fi

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

    export CFLAGS="--gcc-toolchain=${gcc_toolchain_root} ${CFLAGS:-}"
    export CXXFLAGS="--gcc-toolchain=${gcc_toolchain_root} ${CXXFLAGS:-}"

    if [[ -n "$gcc_toolchain_lib" ]]; then
      export LDFLAGS="-L${gcc_toolchain_lib} -Wl,-rpath,${gcc_toolchain_lib} --gcc-toolchain=${gcc_toolchain_root} ${LDFLAGS:-}"
    else
      export LDFLAGS="--gcc-toolchain=${gcc_toolchain_root} ${LDFLAGS:-}"
    fi
  fi
}
