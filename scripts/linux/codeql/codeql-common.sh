#!/usr/bin/env bash

codeql_install_cli() {
  local tmpdir="${1:-/tmp/codeql}"
  mkdir -p "$tmpdir"
  pushd "$tmpdir" >/dev/null
  wget -q https://github.com/github/codeql-cli-binaries/releases/latest/download/codeql-linux64.zip -O codeql.zip
  unzip -q codeql.zip -d /opt
  /opt/codeql/codeql resolve languages
  popd >/dev/null
}

codeql_download_packs() {
  for pack in "$@"; do
    /opt/codeql/codeql pack download "$pack"
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

  cat > "$build_script_path" <<EOF
#!/bin/bash -l
set -e
export CC=clang
export CXX=clang++
export CXXFLAGS="--gcc-toolchain=${gcc_root} \$CXXFLAGS"
export LDFLAGS="-L${gcc_root}/lib64 -Wl,-rpath,${gcc_root}/lib64 --gcc-toolchain=${gcc_root} \$LDFLAGS"
export PATH="${flutter_dir}/bin:\$PATH"
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

# Kotlin is covered by the Java extractor, hence java-queries.
codeql_analyze_java() {
  mkdir -p /workspace/codeql-results
  /opt/codeql/codeql database analyze /tmp/codeql-db-cluster/java \
    --format=sarif-latest \
    --output=/workspace/codeql-results/java.sarif \
    codeql/java-queries:codeql-suites/java-security-and-quality.qls || true
}
