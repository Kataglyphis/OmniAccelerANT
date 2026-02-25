#!/usr/bin/env bash

run_codeql_android() {
  local flutter_dir="${1:?flutter_dir is required}"
  local build_mode="${2:-release}"
  codeql_install_cli
  cd /workspace
  codeql_download_packs codeql/cpp-queries codeql/rust-queries codeql/java-queries
  codeql_write_build_script /tmp/codeql-build.sh "flutter build apk --${build_mode}" "$flutter_dir"
  codeql_create_db_cluster /tmp/codeql-build.sh --language=cpp --language=c --language=rust --language=java --language=kotlin
  codeql_analyze_cpp
  codeql_analyze_kotlin
  codeql_analyze_rust
}
