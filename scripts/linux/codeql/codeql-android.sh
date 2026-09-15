#!/usr/bin/env bash

run_codeql_android() {
  local flutter_dir="${1:?flutter_dir is required}"
  local build_mode="${2:-release}"
  codeql_install_cli
  cd /workspace
  codeql_download_packs codeql/cpp-queries codeql/rust-queries
  codeql_write_build_script /tmp/codeql-build.sh "flutter build apk --${build_mode}" "$flutter_dir"
  # NO --language=java / --language=kotlin, and therefore no codeql_analyze_java.
  # CodeQL's Java extractor injects a Kotlin compiler plugin into the Gradle
  # build, and that plugin carries a hard upper bound on the Kotlin version it
  # understands. Against this repo's declared KGP the whole BUILD dies, not just
  # the scan -- run 34870931651 (2026-09-14), task
  # :kataglyphis_native_inference:compileReleaseKotlin:
  #   Kotlin version 2.4.20 is too recent. CodeQL currently supports versions
  #   below 2.4.20
  # and `database create` then reports "Exit status 1 from command:
  # [/tmp/codeql-build.sh]", so the android lane exits 2 with no APK and no
  # results at all. The KGP declaration in android/settings.gradle.kts:23 is what
  # lifts the classpath Kotlin over Flutter's 2.2.20 floor (AGP 9.4.0 bundles
  # 2.2.10), so lowering it to satisfy CodeQL would trade a working build for a
  # scan of 5 first-party Kotlin/Java glue files. Scanning cpp and rust -- where
  # this project's actual inference code lives -- costs nothing and keeps the
  # lane producing an APK. Restore both flags and the codeql_analyze_java call
  # (still defined in codeql-common.sh) once CodeQL's ceiling clears 2.4.20.
  codeql_create_db_cluster /tmp/codeql-build.sh --language=cpp --language=c --language=rust
  codeql_analyze_cpp
  codeql_analyze_rust
}
