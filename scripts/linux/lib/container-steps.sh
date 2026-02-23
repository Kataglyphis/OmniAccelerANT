#!/usr/bin/env bash

maybe_truthy() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

run_check_cmd() {
  local strict_mode="${STRICT_CHECKS:-0}"
  if maybe_truthy "$strict_mode"; then
    "$@"
  else
    "$@" || true
  fi
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
  run_check_cmd dart format --output=none --set-exit-if-changed .
  run_check_cmd dart analyze
  run_check_cmd flutter test
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

sanitize_package_name() {
  local input="${1:?package name required}"
  echo "$input" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | sed 's/[^a-z0-9.+-]/-/g'
}

detect_bundle_dir() {
  : "${MATRIX_ARCH:?MATRIX_ARCH is required (x64|arm64)}"
  echo "build/linux/${MATRIX_ARCH}/release/bundle"
}

detect_bundle_binary() {
  local bundle_dir="${1:?bundle_dir required}"
  if [[ ! -d "$bundle_dir" ]]; then
    echo "Error: bundle directory not found: $bundle_dir" >&2
    return 1
  fi

  local binary=""
  while IFS= read -r candidate; do
    local base
    base="$(basename "$candidate")"
    if [[ "$base" == *.so || "$base" == *.sh ]]; then
      continue
    fi
    binary="$base"
    break
  done < <(find "$bundle_dir" -mindepth 1 -maxdepth 1 -type f -executable | sort)

  if [[ -z "$binary" ]]; then
    echo "Error: could not detect executable in $bundle_dir" >&2
    return 1
  fi

  echo "$binary"
}

get_pubspec_version() {
  local pubspec_file="${1:-pubspec.yaml}"
  if [[ ! -f "$pubspec_file" ]]; then
    echo "0.0.0"
    return 0
  fi

  local version
  version="$(sed -n 's/^version:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$pubspec_file" | head -n1)"
  version="${version%%+*}"

  if [[ -z "$version" ]]; then
    version="0.0.0"
  fi

  echo "$version"
}

map_arch_to_deb() {
  case "${1:?arch required}" in
    x64|amd64|x86_64) echo "amd64" ;;
    arm64|aarch64) echo "arm64" ;;
    *)
      echo "Error: unsupported architecture for .deb: $1" >&2
      return 1
      ;;
  esac
}

map_arch_to_appimage() {
  case "${1:?arch required}" in
    x64|amd64|x86_64) echo "x86_64" ;;
    arm64|aarch64) echo "aarch64" ;;
    *)
      echo "Error: unsupported architecture for AppImage: $1" >&2
      return 1
      ;;
  esac
}

map_arch_to_flatpak() {
  case "${1:?arch required}" in
    x64|amd64|x86_64) echo "x86_64" ;;
    arm64|aarch64) echo "aarch64" ;;
    *)
      echo "Error: unsupported architecture for Flatpak: $1" >&2
      return 1
      ;;
  esac
}

detect_icon_file() {
  if [[ -f "web/icons/Icon-512.png" ]]; then
    echo "web/icons/Icon-512.png"
    return 0
  fi
  if [[ -f "assets/icons/kataglyphis_app_icon.png" ]]; then
    echo "assets/icons/kataglyphis_app_icon.png"
    return 0
  fi
  if [[ -f "assets/images/logo.png" ]]; then
    echo "assets/images/logo.png"
    return 0
  fi
  echo ""
}

create_desktop_file() {
  local file_path="${1:?desktop file path required}"
  local app_id="${2:?app id required}"
  local app_name="${3:?app name required}"
  local exec_name="${4:?exec name required}"
  local icon_name="${5:?icon name required}"

  cat > "$file_path" <<EOF
[Desktop Entry]
Type=Application
Name=${app_name}
Comment=Kataglyphis Inference Engine
Exec=${exec_name}
Icon=${icon_name}
Terminal=false
Categories=Utility;Development;
StartupNotify=true
StartupWMClass=${exec_name}
X-GNOME-UsesNotifications=true
EOF
}

package_linux_bundle_deb() {
  : "${MATRIX_ARCH:?MATRIX_ARCH is required (x64|arm64)}"
  : "${APP_NAME:?APP_NAME is required}"

  local bundle_dir version package_name arch deb_root binary_name app_id icon_file icon_name output_name
  bundle_dir="$(detect_bundle_dir)"
  version="$(get_pubspec_version)"
  package_name="$(sanitize_package_name "$APP_NAME")"
  arch="$(map_arch_to_deb "$MATRIX_ARCH")"
  binary_name="$(detect_bundle_binary "$bundle_dir")"
  app_id="org.kataglyphis.${package_name}"
  icon_file="$(detect_icon_file)"
  icon_name="$package_name"
  output_name="${package_name}_${version}_${arch}.deb"

  if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "Error: dpkg-deb not found. Install package 'dpkg' to build .deb files." >&2
    return 1
  fi

  rm -rf out/deb
  deb_root="out/deb"
  mkdir -p "$deb_root/DEBIAN"
  mkdir -p "$deb_root/opt/$package_name"
  mkdir -p "$deb_root/usr/bin"
  mkdir -p "$deb_root/usr/share/applications"
  mkdir -p "$deb_root/usr/share/icons/hicolor/512x512/apps"

  cp -a "$bundle_dir/." "$deb_root/opt/$package_name/"

  cat > "$deb_root/usr/bin/$package_name" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec /opt/${package_name}/${binary_name} "\$@"
EOF
  chmod 0755 "$deb_root/usr/bin/$package_name"

  create_desktop_file \
    "$deb_root/usr/share/applications/${package_name}.desktop" \
    "$app_id" \
    "$APP_NAME" \
    "$package_name" \
    "$icon_name"

  if [[ -n "$icon_file" ]]; then
    cp "$icon_file" "$deb_root/usr/share/icons/hicolor/512x512/apps/${package_name}.png"
  fi

  cat > "$deb_root/DEBIAN/control" <<EOF
Package: ${package_name}
Version: ${version}
Section: utils
Priority: optional
Architecture: ${arch}
Maintainer: Kataglyphis <dev@kataglyphis.local>
Depends: libc6, libstdc++6, libgtk-3-0
Description: ${APP_NAME}
 Kataglyphis inference engine desktop app.
EOF

  chmod 0755 "$deb_root/DEBIAN"
  dpkg-deb --build "$deb_root" "out/${output_name}"
  echo "Created: out/${output_name}"
}

package_linux_bundle_appimage() {
  : "${MATRIX_ARCH:?MATRIX_ARCH is required (x64|arm64)}"
  : "${APP_NAME:?APP_NAME is required}"

  local bundle_dir version package_name arch binary_name app_id icon_file icon_name appdir output_name
  bundle_dir="$(detect_bundle_dir)"
  version="$(get_pubspec_version)"
  package_name="$(sanitize_package_name "$APP_NAME")"
  arch="$(map_arch_to_appimage "$MATRIX_ARCH")"
  binary_name="$(detect_bundle_binary "$bundle_dir")"
  app_id="org.kataglyphis.${package_name}"
  icon_file="$(detect_icon_file)"
  icon_name="$package_name"
  appdir="out/${package_name}.AppDir"
  output_name="${package_name}-${version}-${arch}.AppImage"

  if ! command -v appimagetool >/dev/null 2>&1; then
    echo "Error: appimagetool not found. Install it to build AppImage." >&2
    return 1
  fi

  rm -rf "$appdir"
  mkdir -p "$appdir/usr/lib/$package_name"

  cp -a "$bundle_dir/." "$appdir/usr/lib/$package_name/"

  cat > "$appdir/AppRun" <<EOF
#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
exec "\$SELF_DIR/usr/lib/${package_name}/${binary_name}" "\$@"
EOF
  chmod 0755 "$appdir/AppRun"

  create_desktop_file \
    "$appdir/${app_id}.desktop" \
    "$app_id" \
    "$APP_NAME" \
    "AppRun" \
    "$icon_name"

  if [[ -n "$icon_file" ]]; then
    cp "$icon_file" "$appdir/${icon_name}.png"
  fi

  appimagetool "$appdir" "out/${output_name}"
  echo "Created: out/${output_name}"
}

package_linux_bundle_flatpak() {
  : "${MATRIX_ARCH:?MATRIX_ARCH is required (x64|arm64)}"
  : "${APP_NAME:?APP_NAME is required}"

  local bundle_dir version package_name app_id binary_name icon_file manifest_dir manifest_file repo_dir build_dir output_name flatpak_arch
  bundle_dir="$(detect_bundle_dir)"
  version="$(get_pubspec_version)"
  package_name="$(sanitize_package_name "$APP_NAME")"
  app_id="org.kataglyphis.${package_name}"
  binary_name="$(detect_bundle_binary "$bundle_dir")"
  icon_file="$(detect_icon_file)"
  manifest_dir="out/flatpak"
  manifest_file="${manifest_dir}/${app_id}.yml"
  repo_dir="${manifest_dir}/repo"
  build_dir="${manifest_dir}/build-dir"
  output_name="out/${package_name}-${version}.flatpak"
  flatpak_arch="$(map_arch_to_flatpak "$MATRIX_ARCH")"

  if ! command -v flatpak >/dev/null 2>&1; then
    echo "Error: flatpak not found. Install 'flatpak' to build Flatpak bundles." >&2
    return 1
  fi
  if ! command -v flatpak-builder >/dev/null 2>&1; then
    echo "Error: flatpak-builder not found. Install 'flatpak-builder' to build Flatpak bundles." >&2
    return 1
  fi

  mkdir -p "$manifest_dir/files"
  rm -rf "$manifest_dir/files" "$repo_dir" "$build_dir"
  mkdir -p "$manifest_dir/files"

  cp -a "$bundle_dir/." "$manifest_dir/files/"

  create_desktop_file \
    "$manifest_dir/files/${app_id}.desktop" \
    "$app_id" \
    "$APP_NAME" \
    "$package_name" \
    "$app_id"

  if [[ -n "$icon_file" ]]; then
    cp "$icon_file" "$manifest_dir/files/${app_id}.png"
  fi

  cat > "$manifest_file" <<EOF
app-id: ${app_id}
runtime: org.freedesktop.Platform
runtime-version: '23.08'
sdk: org.freedesktop.Sdk
command: ${package_name}
finish-args:
  - --share=network
  - --socket=wayland
  - --socket=fallback-x11
  - --device=dri
modules:
  - name: ${package_name}
    buildsystem: simple
    build-commands:
      - mkdir -p /app/bin /app/lib /app/data
      - install -Dm755 ${binary_name} /app/bin/${package_name}
      - cp -a lib/. /app/lib/
      - cp -a data/. /app/data/
      - install -Dm644 ${app_id}.desktop /app/share/applications/${app_id}.desktop
      - install -Dm644 ${app_id}.png /app/share/icons/hicolor/512x512/apps/${app_id}.png
    sources:
      - type: dir
        path: files
EOF

  if ! flatpak-builder --force-clean --disable-rofiles-fuse --arch="$flatpak_arch" "$build_dir" "$manifest_file" --repo="$repo_dir"; then
    return 1
  fi

  if ! flatpak build-bundle "$repo_dir" "$output_name" "$app_id"; then
    return 1
  fi

  echo "Created: ${output_name}"
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
