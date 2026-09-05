#!/usr/bin/env bash

# App-specific values only; the mechanics are upstream.
_packaging_common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_packaging_common_dir}/containerhub.sh"

export APP_PACKAGING_APP_ID_PREFIX="org.kataglyphis"
export APP_PACKAGING_COMMENT="Kataglyphis Inference Engine"
export APP_PACKAGING_MAINTAINER="Kataglyphis <dev@kataglyphis.local>"
export APP_PACKAGING_DESCRIPTION="Kataglyphis inference engine desktop app."
APP_PACKAGING_ICON_FALLBACKS=("assets/icons/kataglyphis_app_icon.png")

containerhub_source linux/scripts/lib/app-packaging.sh

# Aliases for the upstream app_packaging_ names — see BACKLOG.md.
packaging_assert_artifact()                  { app_packaging_assert_artifact "$@"; }
packaging_run_privileged_cmd()               { app_packaging_run_privileged_cmd "$@"; }
setup_packaging_dependencies_for_container() { app_packaging_setup_dependencies_for_container "$@"; }
run_command_with_packaging_runtime()         { app_packaging_run_command_with_runtime "$@"; }
formats_include_flatpak()                    { app_packaging_formats_include_flatpak "$@"; }
prepare_packaging_workspace()                { app_packaging_prepare_workspace "$@"; }
package_linux_bundle_tar()                   { app_packaging_package_linux_bundle_tar "$@"; }
package_linux_bundle_deb()                   { app_packaging_package_linux_bundle_deb "$@"; }
package_linux_bundle_appimage()              { app_packaging_package_linux_bundle_appimage "$@"; }
package_linux_bundle_flatpak()               { app_packaging_package_linux_bundle_flatpak "$@"; }
package_bundle_outputs_tar()                 { app_packaging_package_bundle_outputs_tar "$@"; }
package_android_apk_outputs_tar()            { app_packaging_package_android_apk_outputs_tar "$@"; }
detect_bundle_dir()                          { app_packaging_detect_bundle_dir "$@"; }
detect_bundle_binary()                       { app_packaging_detect_bundle_binary "$@"; }
get_pubspec_version()                        { app_packaging_get_pubspec_version "$@"; }
sanitize_package_name()                      { app_packaging_sanitize_package_name "$@"; }
