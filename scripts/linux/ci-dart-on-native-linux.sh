#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ci-common.sh"

use_docker() {
  case "${USE_DOCKER:-1}" in
    0|false|False|FALSE|no|No|NO)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

apply_dartdoc_theme_overrides() {
  local css_file="$1"
  local override_css_file="$2"

  if [[ ! -f "$override_css_file" || ! -f "$css_file" ]]; then
    return 0
  fi

  echo "Applying Sphinx-like theme overrides to dartdoc output"

  if grep -q "Sphinx press theme overrides for Dartdoc START" "$css_file"; then
    awk '/\/\* Sphinx press theme overrides for Dartdoc START \*\//{exit} {print}' "$css_file" > "${css_file}.tmp"
    mv "${css_file}.tmp" "$css_file"
  fi

  cat "$override_css_file" >> "$css_file"
}

set_dark_theme_as_default() {
  local docs_api_dir="$1"

  if [[ ! -d "$docs_api_dir" ]]; then
    return 0
  fi

  echo "Setting dark theme as default in generated HTML"
  find "$docs_api_dir" -type f -name "*.html" -print0 | while IFS= read -r -d '' html_file; do
    sed -i 's/class="light-theme"/class="dark-theme"/g' "$html_file"
  done
}

fix_doc_ownership_if_possible() {
  local workspace_dir="$1"
  local docs_dir="$2"

  if ! command -v stat >/dev/null 2>&1 || ! command -v chown >/dev/null 2>&1; then
    return 0
  fi

  if [[ ! -d "$workspace_dir" || ! -d "$docs_dir" ]]; then
    return 0
  fi

  local owner_uid
  local owner_gid
  owner_uid=$(stat -c "%u" "$workspace_dir")
  owner_gid=$(stat -c "%g" "$workspace_dir")
  echo "Fixing ownership of ${docs_dir} to ${owner_uid}:${owner_gid}"
  chown -R "${owner_uid}:${owner_gid}" "$docs_dir" || true
}

sync_doc_website_assets() {
  local docs_api_dir="$1"
  local project_images_dir="$2"

  if [[ ! -d "$docs_api_dir" ]]; then
    return 0
  fi

  if [[ -d "$project_images_dir" ]]; then
    echo "Copying website assets from ${project_images_dir} to ${docs_api_dir}/images"
    mkdir -p "${docs_api_dir}/images"
    cp -a "${project_images_dir}/." "${docs_api_dir}/images/"
  fi
}

STAGE="${1:-}"
if [[ -z "$STAGE" ]]; then
  echo "Usage: $0 <pull_container|setup_flutter|checks|build_linux|package|generate_docs>"
  exit 2
fi

if use_docker; then
  require_ci_env
elif [[ "$STAGE" != "generate_docs" ]]; then
  echo "Non-docker mode is only supported for generate_docs. Use USE_DOCKER=1 for stage: $STAGE"
  exit 2
fi

case "$STAGE" in
  pull_container)
    pull_container_with_retry 3
    docker system df || true
    ;;

  setup_flutter)
    run_container '
      set -e
      git config --global --add safe.directory /workspace || true
      git config --global --add safe.directory ${FLUTTER_DIR} || true

      if [ "$MATRIX_ARCH" = "x64" ]; then
        chmod +x ExternalLib/Kataglyphis-ContainerHub/linux/scripts/setup-flutter-x86-64.sh
        ./ExternalLib/Kataglyphis-ContainerHub/linux/scripts/setup-flutter-x86-64.sh $FLUTTER_VERSION $(dirname ${FLUTTER_DIR})
      else
        chmod +x ExternalLib/Kataglyphis-ContainerHub/linux/scripts/setup-flutter-arm64.sh
        ./ExternalLib/Kataglyphis-ContainerHub/linux/scripts/setup-flutter-arm64.sh $FLUTTER_VERSION $(dirname ${FLUTTER_DIR})
      fi
      chmod -R u+rwX ${FLUTTER_DIR}/bin/cache 2>/dev/null || true
      chmod -R u+rwX ${FLUTTER_DIR} 2>/dev/null || true
    '
    ;;

  checks)
    run_container '
      set -e
      git config --global --add safe.directory /workspace || true
      git config --global --add safe.directory ${FLUTTER_DIR} || true

      source ~/.bashrc
      export PATH="${FLUTTER_DIR}/bin:$PATH"

      flutter pub get
      dart format --output=none --set-exit-if-changed . || true
      dart analyze || true
      flutter test || true
      flutter config --enable-linux-desktop
    '
    ;;

  build_linux)
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

      if [ "$MATRIX_ARCH" = "x64" ]; then
        TMPDIR=/tmp/codeql
        mkdir -p $TMPDIR
        cd $TMPDIR

        wget -q https://github.com/github/codeql-cli-binaries/releases/latest/download/codeql-linux64.zip -O codeql.zip
        unzip -q codeql.zip -d /opt

        /opt/codeql/codeql resolve languages

        cd /workspace

        /opt/codeql/codeql pack download codeql/cpp-queries
        /opt/codeql/codeql pack download codeql/rust-queries

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
          "flutter build linux --release" \
          > /tmp/codeql-build.sh

        chmod +x /tmp/codeql-build.sh

        /opt/codeql/codeql database create /tmp/codeql-db-cluster \
          --db-cluster \
          --language=c \
          --language=cpp \
          --language=rust \
          --source-root=/workspace \
          --command=/tmp/codeql-build.sh

        mkdir -p /workspace/codeql-results

        /opt/codeql/codeql database analyze /tmp/codeql-db-cluster/cpp \
          --format=sarif-latest \
          --output=/workspace/codeql-results/cpp.sarif \
          codeql/cpp-queries:codeql-suites/cpp-security-and-quality.qls || true

        /opt/codeql/codeql database analyze /tmp/codeql-db-cluster/rust \
          --format=sarif-latest \
          --output=/workspace/codeql-results/rust.sarif \
          codeql/rust-queries:codeql-suites/rust-security-and-quality.qls || true

      else
        flutter clean
        flutter pub get
        flutter build linux --release
      fi
    '
    ;;

  package)
    run_container '
      set -e
      rm -rf build/linux/$MATRIX_ARCH/release/obj || true
      rm -rf ~/.pub-cache/hosted || true
      mkdir -p out
      cp -r build/linux/$MATRIX_ARCH/release/bundle out/${APP_NAME}-bundle
      tar -C out -czf ${APP_NAME}-linux-$MATRIX_ARCH.tar.gz ${APP_NAME}-bundle
    '
    ;;

  generate_docs)
    if use_docker; then
      run_container '
        set -e
        git config --global --add safe.directory /workspace || true
        git config --global --add safe.directory ${FLUTTER_DIR} || true

        source ~/.bashrc
        export PATH="${FLUTTER_DIR}/bin:$PATH"

        flutter clean
        dart doc

        DOC_API_DIR="/workspace/doc/api"
        DOC_CSS_FILE="${DOC_API_DIR}/static-assets/styles.css"
        OVERRIDE_CSS_FILE="/workspace/docs/source/_static/css/dartdoc-theme-overrides.css"
        PROJECT_IMAGES_DIR="/workspace/images"

        if [ -f "${OVERRIDE_CSS_FILE}" ] && [ -f "${DOC_CSS_FILE}" ]; then
          echo "Applying Sphinx-like theme overrides to dartdoc output"

          if grep -q "Sphinx press theme overrides for Dartdoc START" "${DOC_CSS_FILE}"; then
            awk '/\/\* Sphinx press theme overrides for Dartdoc START \*\//{exit} {print}' "${DOC_CSS_FILE}" > "${DOC_CSS_FILE}.tmp"
            mv "${DOC_CSS_FILE}.tmp" "${DOC_CSS_FILE}"
          fi

          cat "${OVERRIDE_CSS_FILE}" >> "${DOC_CSS_FILE}"

          echo "Setting dark theme as default in generated HTML"
          find "${DOC_API_DIR}" -type f -name "*.html" -print0 | while IFS= read -r -d "" html_file; do
            sed -i 's/class="light-theme"/class="dark-theme"/g' "$html_file"
          done
        fi

        if [ -d "${PROJECT_IMAGES_DIR}" ]; then
          echo "Copying website assets from ${PROJECT_IMAGES_DIR} to ${DOC_API_DIR}/images"
          mkdir -p "${DOC_API_DIR}/images"
          cp -a "${PROJECT_IMAGES_DIR}/." "${DOC_API_DIR}/images/"
        fi

        OWNER_UID=$(stat -c "%u" /workspace)
        OWNER_GID=$(stat -c "%g" /workspace)
        echo "Fixing ownership of doc/api to ${OWNER_UID}:${OWNER_GID}"
        chown -R ${OWNER_UID}:${OWNER_GID} /workspace/doc || true
      '
    else
      set -e

      if [[ -f "$HOME/.bashrc" ]]; then
        source "$HOME/.bashrc"
      fi

      if [[ -n "${FLUTTER_DIR:-}" && -d "${FLUTTER_DIR}/bin" ]]; then
        export PATH="${FLUTTER_DIR}/bin:$PATH"
      fi

      flutter clean
      dart doc

      DOC_API_DIR="doc/api"
      DOC_CSS_FILE="${DOC_API_DIR}/static-assets/styles.css"
      OVERRIDE_CSS_FILE="docs/source/_static/css/dartdoc-theme-overrides.css"
      PROJECT_IMAGES_DIR="images"

      apply_dartdoc_theme_overrides "$DOC_CSS_FILE" "$OVERRIDE_CSS_FILE"
      set_dark_theme_as_default "$DOC_API_DIR"
      sync_doc_website_assets "$DOC_API_DIR" "$PROJECT_IMAGES_DIR"
      fix_doc_ownership_if_possible "." "doc"
    fi
    ;;

  *)
    echo "Unknown stage: $STAGE"
    exit 2
    ;;
esac
