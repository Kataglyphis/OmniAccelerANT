#!/usr/bin/env bash

# App-specific values only; the mechanics are upstream.
_packaging_common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_packaging_common_dir}/antfrastructure.sh"

export APP_PACKAGING_APP_ID_PREFIX="org.kataglyphis"
export APP_PACKAGING_COMMENT="OmniAccelerANT"
export APP_PACKAGING_MAINTAINER="Kataglyphis <dev@kataglyphis.local>"
export APP_PACKAGING_DESCRIPTION="Kataglyphis inference engine desktop app."
# The bundle carries glibc, libstdc++ and GStreamer; libepoxy dlopens EGL, GLES and GLX.
export APP_PACKAGING_DEB_DEPENDS="${APP_PACKAGING_DEB_DEPENDS:-libgtk-3-0, libegl1, libgles2, libgl1}"
APP_PACKAGING_ICON_FALLBACKS=("assets/icons/kataglyphis_app_icon.png")
# Flatpak has no --device=video, and the Stream page opens /dev/video*; set empty to drop it (owner, 2026-10-01).
export KATAGLYPHIS_FLATPAK_FINISH_ARGS="${KATAGLYPHIS_FLATPAK_FINISH_ARGS---device=all}"

antfrastructure_source linux/scripts/lib/app-packaging.sh
antfrastructure_source linux/scripts/06-packaging/ort-wheel-licenses.sh
source "${_packaging_common_dir}/flutter-package-license.sh"

package_with_project_license() {
  local format="${1:?format required}" arch="${2:?arch required}" app="${3:?app required}" version package mapped output prefix bundle
  "app_packaging_package_linux_bundle_${format}" "$arch" "$app" || return $?
  version="${APP_PACKAGING_VERSION:-$(app_packaging_get_pubspec_version)}"
  package="$(app_packaging_sanitize_package_name "$app")"
  bundle="$(app_packaging_detect_bundle_dir "$arch")"
  case "$format" in
    tar) output="out/${app}-linux-${arch}.tar.gz"; prefix="${app}-bundle" ;;
    deb) mapped="$(app_packaging_map_arch_to_deb "$arch")"; output="${APP_PACKAGING_OUT_DIR:-out}/${package}_${version}_${mapped}.deb"; prefix="opt/${package}" ;;
    flatpak) output="${APP_PACKAGING_OUT_DIR:-out}/${package}-${version}.flatpak"; prefix="files/lib/${package}" ;;
    appimage)
      mapped="$(app_packaging_map_arch_to_appimage "$arch")"
      output="${APP_PACKAGING_OUT_DIR:-out}/${package}-${version}-${mapped}.AppImage"
      verify_flutter_appimage_license "$output" "$arch" "usr/lib/${package}/data/flutter_assets/NOTICES.Z" || return $?
      verify_ort_wheel_appimage_licenses "$output" "$bundle" "$arch" "usr/lib/${package}"
      return $? ;;
    *) return 2 ;;
  esac
  verify_flutter_package_license "$output" '*flutter_assets/NOTICES.Z' || return $?
  verify_ort_wheel_package_licenses "$output" "$bundle" "$prefix"
}

package_tar_with_project_license() { package_with_project_license tar "$@"; }
package_deb_with_project_license() { package_with_project_license deb "$@"; }
package_appimage_with_project_license() { package_with_project_license appimage "$@"; }
