#!/usr/bin/env bash

maybe_truthy() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

git_safe_dirs() {
  git config --global --add safe.directory /workspace || true
  if [[ -n "${FLUTTER_DIR:-}" ]]; then
    git config --global --add safe.directory "${FLUTTER_DIR}" || true
  fi
}

source_bashrc_and_add_flutter_to_path() {
  source ~/.bashrc 2>/dev/null || true
  if [[ -n "${FLUTTER_DIR:-}" ]]; then
    export PATH="${FLUTTER_DIR}/bin:$PATH"
  fi
}

setup_flutter_sdk() {
  : "${FLUTTER_VERSION:?FLUTTER_VERSION is required}"
  : "${FLUTTER_DIR:=/workspace/flutter}"
  : "${MATRIX_ARCH:?MATRIX_ARCH is required (x64|arm64)}"

  if [[ "$MATRIX_ARCH" == "x64" ]]; then
    chmod +x ExternalLib/Kataglyphis-ContainerHub/linux/scripts/setup-flutter-x86-64.sh
    ./ExternalLib/Kataglyphis-ContainerHub/linux/scripts/setup-flutter-x86-64.sh "$FLUTTER_VERSION" "$(dirname "${FLUTTER_DIR}")"
  else
    chmod +x ExternalLib/Kataglyphis-ContainerHub/linux/scripts/setup-flutter-arm64.sh
    ./ExternalLib/Kataglyphis-ContainerHub/linux/scripts/setup-flutter-arm64.sh "$FLUTTER_VERSION" "$(dirname "${FLUTTER_DIR}")"
  fi

  chmod -R u+rwX "${FLUTTER_DIR}/bin/cache" 2>/dev/null || true
  chmod -R u+rwX "${FLUTTER_DIR}" 2>/dev/null || true
}

run_flutter_common_checks() {
  flutter pub get
  dart format --output=none --set-exit-if-changed . || true
  dart analyze || true
  flutter test || true
}

export_toolchain_env() {
  export CC=clang
  export CXX=clang++
  export CXXFLAGS="--gcc-toolchain=/opt/gcc-15.2.0 ${CXXFLAGS:-}"
  export LDFLAGS="-L/opt/gcc-15.2.0/lib64 -Wl,-rpath,/opt/gcc-15.2.0/lib64 --gcc-toolchain=/opt/gcc-15.2.0 ${LDFLAGS:-}"
}

codeql_install_cli() {
  local tmpdir="${1:-/tmp/codeql}"
  mkdir -p "$tmpdir"
  cd "$tmpdir"
  wget -q https://github.com/github/codeql-cli-binaries/releases/latest/download/codeql-linux64.zip -O codeql.zip
  unzip -q codeql.zip -d /opt
  /opt/codeql/codeql resolve languages
}

codeql_download_packs() {
  for pack in "$@"; do
    /opt/codeql/codeql pack download "$pack"
  done
}

codeql_write_build_script() {
  local build_script_path="$1"
  local flutter_build_cmd="$2"

  cat > "$build_script_path" <<EOF
#!/bin/bash -l
set -e
export CC=clang
export CXX=clang++
export CXXFLAGS="--gcc-toolchain=/opt/gcc-15.2.0 \$CXXFLAGS"
export LDFLAGS="-L/opt/gcc-15.2.0/lib64 -Wl,-rpath,/opt/gcc-15.2.0/lib64 --gcc-toolchain=/opt/gcc-15.2.0 \$LDFLAGS"
export PATH="${FLUTTER_DIR}/bin:\$PATH"
source ~/.bashrc 2>/dev/null || true
flutter clean
flutter pub get
$flutter_build_cmd
EOF

  chmod +x "$build_script_path"
}

codeql_create_db_cluster() {
  local build_script_path="$1"
  shift

  /opt/codeql/codeql database create /tmp/codeql-db-cluster \
    --db-cluster \
    "$@" \
    --source-root=/workspace \
    --command="$build_script_path"
}

codeql_analyze_cpp() {
  mkdir -p /workspace/codeql-results
  /opt/codeql/codeql database analyze /tmp/codeql-db-cluster/cpp \
    --format=sarif-latest \
    --output=/workspace/codeql-results/cpp.sarif \
    codeql/cpp-queries:codeql-suites/cpp-security-and-quality.qls || true
}

codeql_analyze_rust() {
  mkdir -p /workspace/codeql-results
  /opt/codeql/codeql database analyze /tmp/codeql-db-cluster/rust \
    --format=sarif-latest \
    --output=/workspace/codeql-results/rust.sarif \
    codeql/rust-queries:codeql-suites/rust-security-and-quality.qls || true
}

codeql_analyze_kotlin() {
  mkdir -p /workspace/codeql-results
  /opt/codeql/codeql database analyze /tmp/codeql-db-cluster/kotlin \
    --format=sarif-latest \
    --output=/workspace/codeql-results/kotlin.sarif \
    codeql/kotlin-queries:codeql-suites/kotlin-security-and-quality.qls || true
}

package_linux_bundle_tar() {
  : "${MATRIX_ARCH:?MATRIX_ARCH is required (x64|arm64)}"
  : "${APP_NAME:?APP_NAME is required}"

  rm -rf "build/linux/${MATRIX_ARCH}/release/obj" || true
  rm -rf ~/.pub-cache/hosted || true
  mkdir -p out
  cp -r "build/linux/${MATRIX_ARCH}/release/bundle" "out/${APP_NAME}-bundle"
  tar -C out -czf "${APP_NAME}-linux-${MATRIX_ARCH}.tar.gz" "${APP_NAME}-bundle"
}

package_android_apk_outputs_tar() {
  : "${MATRIX_ARCH:?MATRIX_ARCH is required (x64|arm64)}"
  : "${APP_NAME:?APP_NAME is required}"

  rm -rf "build/linux/${MATRIX_ARCH}/release/obj" || true
  rm -rf ~/.pub-cache/hosted || true
  mkdir -p out
  cp -r build/app/outputs/flutter-apk "out/${APP_NAME}-bundle"
  tar -C out -czf "${APP_NAME}-linux-${MATRIX_ARCH}.tar.gz" "${APP_NAME}-bundle"
}

generate_dart_docs_and_fix_ownership() {
  flutter clean
  dart doc

  local owner_uid owner_gid
  owner_uid=$(stat -c "%u" /workspace)
  owner_gid=$(stat -c "%g" /workspace)
  echo "Fixing ownership of doc/api to ${owner_uid}:${owner_gid}"
  chown -R "${owner_uid}:${owner_gid}" /workspace/doc || true
}
