#!/usr/bin/env bash

run_codeql_android() {
  local flutter_dir="${1:?flutter_dir is required}"
  local build_mode="${2:-release}"
  codeql_install_cli
  cd /workspace
  codeql_download_packs codeql/cpp-queries codeql/rust-queries
  codeql_write_build_script /tmp/codeql-build.sh "flutter build apk --${build_mode} --target-platform android-arm64" "$flutter_dir"
  # No java/kotlin (nor codeql_analyze_java): CodeQL's Kotlin plugin rejects KGP 2.4.20 and kills the build.
  codeql_create_db_cluster /tmp/codeql-build.sh --language=cpp --language=c --language=rust
  codeql_analyze_cpp
  codeql_analyze_rust
}
