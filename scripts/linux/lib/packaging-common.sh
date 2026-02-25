#!/usr/bin/env bash

packaging_run_privileged_cmd() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "Error: need root privileges for command: $*" >&2
    return 1
  fi
}

setup_local_appimagetool_for_container() {
  local matrix_arch="${1:?matrix_arch required}"
  mkdir -p .tools/bin

  local appimage_arch
  case "$matrix_arch" in
    x64) appimage_arch="x86_64" ;;
    arm64) appimage_arch="aarch64" ;;
    *)
      echo "Error: unsupported architecture for appimagetool bootstrap: $matrix_arch" >&2
      return 1
      ;;
  esac

  wget -q "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${appimage_arch}.AppImage" -O .tools/appimagetool
  chmod +x .tools/appimagetool
  ./.tools/appimagetool --appimage-extract >/dev/null
  rm -rf .tools/squashfs-root
  mv squashfs-root .tools/

  cat > .tools/bin/appimagetool <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/squashfs-root/AppRun" "$@"
EOF
  chmod +x .tools/bin/appimagetool
  export PATH="$PWD/.tools/bin:$PATH"
}

setup_packaging_dependencies_for_container() {
  local matrix_arch="${1:?matrix_arch required}"

  packaging_run_privileged_cmd apt-get update
  packaging_run_privileged_cmd apt-get install -y dpkg flatpak flatpak-builder libfuse2 dbus-user-session wget

  setup_local_appimagetool_for_container "$matrix_arch"

  export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"

  dbus-run-session -- flatpak --user remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  dbus-run-session -- flatpak --user install -y flathub org.freedesktop.Platform//23.08 org.freedesktop.Sdk//23.08
}

formats_include_flatpak() {
  local formats_csv="${1:-}"
  IFS=',' read -r -a _formats <<< "$formats_csv"
  for _raw in "${_formats[@]}"; do
    local _fmt
    _fmt="$(echo "$_raw" | xargs | tr '[:upper:]' '[:lower:]')"
    if [[ "$_fmt" == "flatpak" ]]; then
      return 0
    fi
  done

  return 1
}

run_command_with_packaging_runtime() {
  local formats_csv="${1:-}"
  shift

  if formats_include_flatpak "$formats_csv"; then
    dbus-run-session -- "$@"
  else
    "$@"
  fi
}

prepare_packaging_workspace() {
  local matrix_arch="${1:?matrix_arch is required (x64|arm64)}"
  rm -rf "build/linux/${matrix_arch}/release/obj" || true
  rm -rf ~/.pub-cache/hosted || true
}

package_bundle_outputs_tar() {
  local bundle_source_dir="${1:?bundle_source_dir is required}"
  local app_name="${2:?app_name is required}"
  local matrix_arch="${3:?matrix_arch is required (x64|arm64)}"

  if [[ ! -d "$bundle_source_dir" ]]; then
    echo "Error: bundle source directory not found: $bundle_source_dir" >&2
    return 1
  fi

  mkdir -p out
  local tar_name
  tar_name="${app_name}-linux-${matrix_arch}.tar.gz"
  rm -rf "out/${app_name}-bundle" || true

  cp -r "$bundle_source_dir" "out/${app_name}-bundle"
  tar -C out -czf "out/${tar_name}" "${app_name}-bundle"
  cp -f "out/${tar_name}" "${tar_name}"
}

package_linux_bundle_tar() {
  local matrix_arch="${1:?matrix_arch is required (x64|arm64)}"
  local app_name="${2:?app_name is required}"

  prepare_packaging_workspace "$matrix_arch"
  package_bundle_outputs_tar "build/linux/${matrix_arch}/release/bundle" "$app_name" "$matrix_arch"
}

sanitize_package_name() {
  local input="${1:?package name required}"
  echo "$input" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | sed 's/[^a-z0-9.+-]/-/g'
}

detect_bundle_dir() {
  local matrix_arch="${1:?matrix_arch is required (x64|arm64)}"
  echo "build/linux/${matrix_arch}/release/bundle"
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

resolve_appimagetool() {
  local arch="${1:?appimage arch required}"

  if command -v appimagetool >/dev/null 2>&1; then
    echo "appimagetool"
    return 0
  fi

  local filename
  case "$arch" in
    x86_64)
      filename="appimagetool-x86_64.AppImage"
      ;;
    aarch64)
      filename="appimagetool-aarch64.AppImage"
      ;;
    *)
      echo "Error: unsupported architecture for appimagetool bootstrap: $arch" >&2
      return 1
      ;;
  esac

  local tools_dir tool_path url
  tools_dir="out/tools"
  tool_path="${tools_dir}/${filename}"
  url="https://github.com/AppImage/appimagetool/releases/download/continuous/${filename}"

  mkdir -p "$tools_dir"

  if [[ ! -x "$tool_path" ]]; then
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$url" -o "$tool_path"
    elif command -v wget >/dev/null 2>&1; then
      wget -qO "$tool_path" "$url"
    else
      echo "Error: neither curl nor wget found. Install one of them to fetch appimagetool." >&2
      return 1
    fi
    chmod +x "$tool_path"
  fi

  echo "$tool_path"
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
  local matrix_arch="${1:?matrix_arch is required (x64|arm64)}"
  local app_name="${2:?app_name is required}"

  local bundle_dir version package_name arch deb_root binary_name app_id icon_file icon_name output_name
  bundle_dir="$(detect_bundle_dir "$matrix_arch")"
  version="$(get_pubspec_version)"
  package_name="$(sanitize_package_name "$app_name")"
  arch="$(map_arch_to_deb "$matrix_arch")"
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
    "$app_name" \
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
Description: ${app_name}
 Kataglyphis inference engine desktop app.
EOF

  chmod 0755 "$deb_root/DEBIAN"
  dpkg-deb --build "$deb_root" "out/${output_name}"
  echo "Created: out/${output_name}"
}

package_linux_bundle_appimage() {
  local matrix_arch="${1:?matrix_arch is required (x64|arm64)}"
  local app_name="${2:?app_name is required}"

  local bundle_dir version package_name arch binary_name app_id icon_file icon_name appdir output_name appimagetool_cmd
  bundle_dir="$(detect_bundle_dir "$matrix_arch")"
  version="$(get_pubspec_version)"
  package_name="$(sanitize_package_name "$app_name")"
  arch="$(map_arch_to_appimage "$matrix_arch")"
  binary_name="$(detect_bundle_binary "$bundle_dir")"
  app_id="org.kataglyphis.${package_name}"
  icon_file="$(detect_icon_file)"
  icon_name="$package_name"
  appdir="out/${package_name}.AppDir"
  output_name="${package_name}-${version}-${arch}.AppImage"

  if ! appimagetool_cmd="$(resolve_appimagetool "$arch")"; then
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
    "$app_name" \
    "AppRun" \
    "$icon_name"

  if [[ -n "$icon_file" ]]; then
    cp "$icon_file" "$appdir/${icon_name}.png"
  fi

  APPIMAGE_EXTRACT_AND_RUN=1 NO_APPSTREAM=1 ARCH="$arch" "$appimagetool_cmd" "$appdir" "out/${output_name}"
  echo "Created: out/${output_name}"
}

package_linux_bundle_flatpak() {
  local matrix_arch="${1:?matrix_arch is required (x64|arm64)}"
  local app_name="${2:?app_name is required}"

  local bundle_dir version package_name app_id binary_name icon_file manifest_dir manifest_file repo_dir build_dir output_name flatpak_arch
  bundle_dir="$(detect_bundle_dir "$matrix_arch")"
  version="$(get_pubspec_version)"
  package_name="$(sanitize_package_name "$app_name")"
  app_id="org.kataglyphis.${package_name}"
  binary_name="$(detect_bundle_binary "$bundle_dir")"
  icon_file="$(detect_icon_file)"
  manifest_dir="out/flatpak"
  manifest_file="${manifest_dir}/${app_id}.yml"
  repo_dir="${manifest_dir}/repo"
  build_dir="${manifest_dir}/build-dir"
  output_name="out/${package_name}-${version}.flatpak"
  flatpak_arch="$(map_arch_to_flatpak "$matrix_arch")"

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
    "$app_name" \
    "$package_name" \
    "$app_id"

  if [[ -n "$icon_file" ]]; then
    cp "$icon_file" "$manifest_dir/files/${app_id}.png"
  fi

  cat > "$manifest_file" <<EOF
app-id: ${app_id}
runtime: org.freedesktop.Platform
runtime-version: '24.08'
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
  local matrix_arch="${1:?matrix_arch is required (x64|arm64)}"
  local app_name="${2:?app_name is required}"

  prepare_packaging_workspace "$matrix_arch"
  package_bundle_outputs_tar "build/app/outputs/flutter-apk" "$app_name" "$matrix_arch"
}
