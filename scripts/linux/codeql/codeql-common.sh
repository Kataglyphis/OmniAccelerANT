#!/usr/bin/env bash

# /opt is not writable for the unprivileged container user. Installing there
# left every codeql call as "No such file or directory" — and since
# `database create` wraps the build, the app was never built either.
: "${CODEQL_INSTALL_DIR:=/tmp/codeql-cli}"
CODEQL="${CODEQL_INSTALL_DIR}/codeql/codeql"

codeql_install_cli() {
  local tmpdir="${1:-/tmp/codeql}"
  mkdir -p "$tmpdir"
  pushd "$tmpdir" >/dev/null
  wget -q https://github.com/github/codeql-cli-binaries/releases/latest/download/codeql-linux64.zip -O codeql.zip
  mkdir -p "$CODEQL_INSTALL_DIR"
  unzip -q codeql.zip -d "$CODEQL_INSTALL_DIR"
  if [ ! -x "$CODEQL" ]; then
    echo "Error: codeql CLI not installed at $CODEQL (unzip target not writable?)" >&2
    return 1
  fi
  "$CODEQL" resolve languages
  popd >/dev/null
}

codeql_download_packs() {
  for pack in "$@"; do
    "$CODEQL" pack download "$pack"
  done
}

codeql_write_build_script() {
  local build_script_path="$1"
  local flutter_build_cmd="$2"
  local flutter_dir="$3"

  # GCC path from ContainerHub cross-gcc.sh; resolved here (heredoc is unquoted).
  local gcc_root
  containerhub_source linux/scripts/01-core/cross-gcc.sh
  gcc_root="${MYPROJECT_GCC_TOOLCHAIN_PATH:-$(gcc_toolchain_prefix)}"

  # Same for the SDK: CodeQL runs this script under preload_tracer, where the
  # `source ~/.bashrc` below is a no-op because bashrc returns early for a
  # non-interactive shell.
  local android_home android_exports=""
  if android_home="$(resolve_android_sdk_home)"; then
    android_exports="export ANDROID_HOME=\"${android_home}\"
export ANDROID_SDK_ROOT=\"${android_home}\""
  fi

  cat > "$build_script_path" <<EOF
#!/bin/bash -l
set -e
export CC=clang
export CXX=clang++
export CXXFLAGS="--gcc-toolchain=${gcc_root} \$CXXFLAGS"
export LDFLAGS="-L${gcc_root}/lib64 -Wl,-rpath,${gcc_root}/lib64 --gcc-toolchain=${gcc_root} \$LDFLAGS"
export PATH="${flutter_dir}/bin:\$PATH"
${android_exports}
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

  "$CODEQL" database create /tmp/codeql-db-cluster \
    --db-cluster \
    "$@" \
    --source-root=/workspace \
    --command="$build_script_path"
}

codeql_analyze_cpp() {
  mkdir -p /workspace/codeql-results
  "$CODEQL" database analyze /tmp/codeql-db-cluster/cpp \
    --format=sarif-latest \
    --output=/workspace/codeql-results/cpp.sarif \
    codeql/cpp-queries:codeql-suites/cpp-security-and-quality.qls || true
}

codeql_analyze_rust() {
  mkdir -p /workspace/codeql-results
  "$CODEQL" database analyze /tmp/codeql-db-cluster/rust \
    --format=sarif-latest \
    --output=/workspace/codeql-results/rust.sarif \
    codeql/rust-queries:codeql-suites/rust-security-and-quality.qls || true
}

# Kotlin is covered by the Java extractor, hence java-queries.
codeql_analyze_java() {
  mkdir -p /workspace/codeql-results
  "$CODEQL" database analyze /tmp/codeql-db-cluster/java \
    --format=sarif-latest \
    --output=/workspace/codeql-results/java.sarif \
    codeql/java-queries:codeql-suites/java-security-and-quality.qls || true
}
