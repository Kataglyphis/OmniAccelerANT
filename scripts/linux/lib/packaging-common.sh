#!/usr/bin/env bash

# Arch maps, run_priv and FLATPAK_RUNTIME_VERSION come from ContainerHub.
_packaging_common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_packaging_common_dir}/containerhub.sh"
containerhub_source linux/scripts/01-core/platform.sh   # arch_normalize, arch_uname_name_for
containerhub_source linux/scripts/01-core/common.sh     # run_priv (+ versions.env via its loader)

# From ContainerHub's versions.env (loaded above); the default only guards the
# unlikely case where the loader did not set it.
: "${FLATPAK_RUNTIME_VERSION:=24.08}"

# run_priv, plus a `sudo -n true` probe the runtime image needs.
packaging_run_privileged_cmd() {
  if [[ "$(id -u)" -eq 0 ]]; then
    run_priv "$@"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    SUDO="sudo" run_priv "$@"
  else
    echo "Error: need root privileges for command: $*" >&2
    echo "       Running as uid $(id -u) and sudo cannot elevate here." >&2
    echo "       In the CI container this means a prerequisite is missing from" >&2
    echo "       the image - it cannot be installed at run time." >&2
    return 1
  fi
}

# "Created: …" used to be printed unconditionally, so a dpkg-deb or appimagetool
# that had already failed still reported success and the lane looked green with
# no artifact on disk. Every packaging function ends here now — AGENTS.md § 4.
packaging_assert_artifact() {
  local artifact="${1:?artifact path required}"
  if [ ! -s "$artifact" ]; then
    echo "Error: packaging reported success but ${artifact} is missing or empty" >&2
    return 1
  fi
  echo "Created: ${artifact} ($(du -h "$artifact" 2>/dev/null | cut -f1))"
}

# appimagetool comes from ContainerHub (pinned version + SHA256) — AGENTS.md § 2.
ensure_appimagetool_via_containerhub() {
  if command -v appimagetool >/dev/null 2>&1; then return 0; fi
  bash "$(containerhub_path linux/scripts/02-toolchain/packaging-deps.sh)" appimagetool || return 1
  # The provisioner's own PATH export dies with the child process.
  if ! command -v appimagetool >/dev/null 2>&1; then export PATH="${HOME:-}/.local/bin:$PATH"; fi
  command -v appimagetool >/dev/null 2>&1
}

setup_packaging_dependencies_for_container() {
  local matrix_arch="${1:?matrix_arch required}"

  # The CI image already ships these: ContainerHub's Dockerfile.base runs
  # linux/scripts/02-toolchain/packaging-deps.sh, whose
  # packaging_prerequisite_packages list is exactly dpkg / flatpak /
  # flatpak-builder / elfutils / libfuse2(t64) / dbus-user-session / wget.
  # Installing them again was not merely wasteful, it was impossible: the image
  # runs as the unprivileged `kataglyphis` and has no working sudo, so this
  # apt-get took the whole native-linux lane down on both arches.
  #
  # Probe instead of assume — if a future image drops one of them, apt-get is
  # still attempted and the failure names what is missing.
  local -a required_cmds=(dpkg flatpak flatpak-builder dbus-run-session wget)
  local -a missing_cmds=()
  local _cmd
  for _cmd in "${required_cmds[@]}"; do
    command -v "$_cmd" >/dev/null 2>&1 || missing_cmds+=("$_cmd")
  done

  if [[ ${#missing_cmds[@]} -eq 0 ]]; then
    echo "[Info] Packaging prerequisites already present in the image; skipping apt-get."
  else
    echo "[Info] Missing packaging prerequisites: ${missing_cmds[*]} — installing via apt-get."
    packaging_run_privileged_cmd apt-get update
    packaging_run_privileged_cmd apt-get install -y dpkg flatpak flatpak-builder elfutils libfuse2 dbus-user-session wget
  fi

  ensure_appimagetool_via_containerhub

  export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"

  # Map matrix_arch to Flatpak architecture format
  local flatpak_arch
  case "$matrix_arch" in
    x64|amd64|x86_64) flatpak_arch="x86_64" ;;
    arm64|aarch64) flatpak_arch="aarch64" ;;
    *)
      echo "Error: unsupported architecture for Flatpak runtime: $matrix_arch" >&2
      return 1
      ;;
  esac

  dbus-run-session -- flatpak --user remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  dbus-run-session -- flatpak --user install -y --arch="$flatpak_arch" flathub \
    "org.freedesktop.Platform//${FLATPAK_RUNTIME_VERSION}" \
    "org.freedesktop.Sdk//${FLATPAK_RUNTIME_VERSION}"
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
  if ! tar -C out -czf "out/${tar_name}" "${app_name}-bundle"; then
    echo "Error: tar failed for out/${tar_name}" >&2
    return 1
  fi
  packaging_assert_artifact "out/${tar_name}"
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
  local a="${1:?arch required}"
  case "$(arch_normalize "$a")" in
    amd64|arm64) arch_normalize "$a" ;;
    *)
      echo "Error: unsupported architecture for .deb: $1" >&2
      return 1
      ;;
  esac
}

map_arch_to_appimage() {
  local a="${1:?arch required}"
  case "$(arch_normalize "$a")" in
    amd64|arm64) arch_uname_name_for "$a" ;;
    *)
      echo "Error: unsupported architecture for AppImage: $1" >&2
      return 1
      ;;
  esac
}

map_arch_to_flatpak() {
  local a="${1:?arch required}"
  case "$(arch_normalize "$a")" in
    amd64|arm64) arch_uname_name_for "$a" ;;
    *)
      echo "Error: unsupported architecture for Flatpak: $1" >&2
      return 1
      ;;
  esac
}

# Prints the command name; stdout stays clean because the provisioner logs to stderr.
resolve_appimagetool() {
  ensure_appimagetool_via_containerhub >&2 || return 1
  echo "appimagetool"
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

  # Staged container-native: dpkg-deb refuses a DEBIAN dir it cannot chmod to
  # 0755, and a bind-mounted host drive silently leaves it 777 — AGENTS.md § 4.
  deb_root="${KATAGLYPHIS_PACKAGING_WORKDIR:-/tmp/packaging-work}/deb"
  rm -rf "$deb_root"
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
  if ! dpkg-deb --build "$deb_root" "out/${output_name}"; then
    echo "Error: dpkg-deb failed for out/${output_name}" >&2
    return 1
  fi
  packaging_assert_artifact "out/${output_name}"
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
  # Container-native for the same reason as the deb root: appimagetool chmods
  # its AppDir, which a bind-mounted host drive refuses — AGENTS.md § 4.
  appdir="${KATAGLYPHIS_PACKAGING_WORKDIR:-/tmp/packaging-work}/${package_name}.AppDir"
  output_name="${package_name}-${version}-${arch}.AppImage"

  if ! appimagetool_cmd="$(resolve_appimagetool)"; then
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

  if ! APPIMAGE_EXTRACT_AND_RUN=1 NO_APPSTREAM=1 ARCH="$arch" \
      "$appimagetool_cmd" "$appdir" "out/${output_name}"; then
    echo "Error: appimagetool failed for out/${output_name}" >&2
    return 1
  fi
  packaging_assert_artifact "out/${output_name}"
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
  # Everything flatpak touches needs fchmod, which a bind-mounted host drive
  # refuses — manifest and files/ are staging, the repo and build tree are
  # intermediates. Only the finished bundle belongs in out/. See AGENTS.md § 4.
  local flatpak_work="${KATAGLYPHIS_FLATPAK_WORKDIR:-/tmp/flatpak-work}"
  manifest_dir="${flatpak_work}/manifest"
  manifest_file="${manifest_dir}/${app_id}.yml"
  repo_dir="${flatpak_work}/repo"
  build_dir="${flatpak_work}/build-dir"
  mkdir -p "$flatpak_work"
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
runtime-version: '${FLATPAK_RUNTIME_VERSION}'
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

  # KATAGLYPHIS_FLATPAK_VERBOSE=1 adds -v; the packaging failure on a Windows
  # host is not yet understood and the default output does not name the path.
  local -a fb_flags=()
  [ -n "${KATAGLYPHIS_FLATPAK_VERBOSE:-}" ] && fb_flags+=(-v)
  # The exit code is deliberately not the gate. flatpak-builder can export the
  # app completely and still fail afterwards in `Pruning cache` with
  # `fchmod: Operation not permitted` on a bind-mounted host drive. What decides
  # is whether the app is committed — see AGENTS.md § 4.
  local fb_rc=0
  flatpak-builder "${fb_flags[@]}" --force-clean --disable-rofiles-fuse --arch="$flatpak_arch" \
    --state-dir="${flatpak_work}/state" "$build_dir" "$manifest_file" --repo="$repo_dir" || fb_rc=$?

  if ! ostree --repo="$repo_dir" refs 2>/dev/null | grep -q "^app/${app_id}/"; then
    echo "Error: flatpak-builder exited ${fb_rc} and ${app_id} is not in ${repo_dir}" >&2
    return 1
  fi
  if [ "$fb_rc" -ne 0 ]; then
    echo "[Warn] flatpak-builder exited ${fb_rc}, but ${app_id} is committed; continuing to build-bundle." >&2
  fi

  # build-bundle chmods the file it writes, which a bind-mounted host drive
  # refuses — the failure reads as `error: fchmod: Operation not permitted` and
  # looks like it came from the `Pruning cache` line above it. Write it
  # container-native, then copy the finished bundle out.
  local staged_bundle="${flatpak_work}/$(basename "$output_name")"
  if ! flatpak build-bundle "$repo_dir" "$staged_bundle" "$app_id"; then
    return 1
  fi
  mkdir -p "$(dirname "$output_name")"
  cp -f "$staged_bundle" "$output_name"

  packaging_assert_artifact "${output_name}"
}

package_android_apk_outputs_tar() {
  local matrix_arch="${1:?matrix_arch is required (x64|arm64)}"
  local app_name="${2:?app_name is required}"

  prepare_packaging_workspace "$matrix_arch"
  package_bundle_outputs_tar "build/app/outputs/flutter-apk" "$app_name" "$matrix_arch"
}
