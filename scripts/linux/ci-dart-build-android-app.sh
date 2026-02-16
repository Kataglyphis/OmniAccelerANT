#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ci-common.sh"

STAGE="${1:-}"
if [[ -z "$STAGE" ]]; then
  echo "Usage: $0 <pull_container|setup_flutter|checks|build_android|package>"
  exit 2
fi

require_ci_env

case "$STAGE" in
  pull_container)
    pull_container_with_retry 3
    ;;

  setup_flutter)
    run_container '
      set -e
      git config --global --add safe.directory /workspace || true
      git config --global --add safe.directory ${FLUTTER_DIR} || true
      chmod +x ExternalLib/Kataglyphis-ContainerHub/linux/scripts/setup-flutter-x86-64.sh
      ./ExternalLib/Kataglyphis-ContainerHub/linux/scripts/setup-flutter-x86-64.sh $FLUTTER_VERSION $(dirname ${FLUTTER_DIR})
    '
    ;;

  checks)
    run_container '
      set -e
      export PATH="$PWD/flutter/bin:$PATH"
      git config --global --add safe.directory /workspace || true
      git config --global --add safe.directory ${FLUTTER_DIR} || true
      source ~/.bashrc
      export PATH="${FLUTTER_DIR}/bin:$PATH"

      flutter pub get
      dart format --output=none --set-exit-if-changed . || true
      dart analyze || true
      flutter test || true
      flutter config --enable-android
    '
    ;;

  build_android)
    run_container '
      set -e

      git config --global --add safe.directory /workspace || true
      git config --global --add safe.directory ${FLUTTER_DIR} || true

      export PATH="${FLUTTER_DIR}/bin:$PATH"
      source ~/.bashrc

      export CC=clang
      export CXX=clang++
      export CXXFLAGS="--gcc-toolchain=/opt/gcc-15.2.0 $CXXFLAGS"
      export LDFLAGS="-L/opt/gcc-15.2.0/lib64 -Wl,-rpath,/opt/gcc-15.2.0/lib64 --gcc-toolchain=/opt/gcc-15.2.0 $LDFLAGS"

      TMPDIR=/tmp/codeql
      mkdir -p $TMPDIR
      cd $TMPDIR

      wget -q https://github.com/github/codeql-cli-binaries/releases/latest/download/codeql-linux64.zip -O codeql.zip
      unzip -q codeql.zip -d /opt

      /opt/codeql/codeql resolve languages

      cd /workspace

      /opt/codeql/codeql pack download codeql/cpp-queries
      /opt/codeql/codeql pack download codeql/rust-queries
      /opt/codeql/codeql pack download codeql/java-queries

      printf "%s\n" \
        "#!/bin/bash -l" \
        "set -e" \
        "export CC=clang" \
        "export CXX=clang++" \
        "export CXXFLAGS=\"--gcc-toolchain=/opt/gcc-15.2.0 \$CXXFLAGS\"" \
        "export LDFLAGS=\"-L/opt/gcc-15.2.0/lib64 -Wl,-rpath,/opt/gcc-15.2.0/lib64 --gcc-toolchain=/opt/gcc-15.2.0 \$LDFLAGS\"" \
        "export PATH=\"\${FLUTTER_DIR}/bin:\$PATH\"" \
        "source ~/.bashrc 2>/dev/null || true" \
        "flutter clean" \
        "flutter pub get" \
        "flutter build apk --release" \
        > /tmp/codeql-build.sh

      chmod +x /tmp/codeql-build.sh

      /opt/codeql/codeql database create /tmp/codeql-db-cluster \
        --db-cluster \
        --language=cpp \
        --language=c \
        --language=rust \
        --language=java \
        --language=kotlin \
        --source-root=/workspace \
        --command=/tmp/codeql-build.sh

      mkdir -p /workspace/codeql-results

      /opt/codeql/codeql database analyze /tmp/codeql-db-cluster/cpp \
        --format=sarif-latest \
        --output=/workspace/codeql-results/cpp.sarif \
        codeql/cpp-queries:codeql-suites/cpp-security-and-quality.qls || true

      /opt/codeql/codeql database analyze /tmp/codeql-db-cluster/kotlin \
        --format=sarif-latest \
        --output=/workspace/codeql-results/kotlin.sarif \
        codeql/kotlin-queries:codeql-suites/kotlin-security-and-quality.qls || true

      /opt/codeql/codeql database analyze /tmp/codeql-db-cluster/rust \
        --format=sarif-latest \
        --output=/workspace/codeql-results/rust.sarif \
        codeql/rust-queries:codeql-suites/rust-security-and-quality.qls || true
    '
    ;;

  package)
    run_container '
      set -e
      rm -rf build/linux/$MATRIX_ARCH/release/obj || true
      rm -rf ~/.pub-cache/hosted || true
      mkdir -p out
      cp -r build/app/outputs/flutter-apk out/${APP_NAME}-bundle
      tar -C out -czf ${APP_NAME}-linux-$MATRIX_ARCH.tar.gz ${APP_NAME}-bundle
    '
    ;;

  *)
    echo "Unknown stage: $STAGE"
    exit 2
    ;;
esac
