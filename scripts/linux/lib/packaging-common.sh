#!/usr/bin/env bash

# App-specific values only; the mechanics are upstream.
_packaging_common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_packaging_common_dir}/antfrastructure.sh"

export APP_PACKAGING_APP_ID_PREFIX="org.kataglyphis"
export APP_PACKAGING_COMMENT="OmniAccelerANT"
export APP_PACKAGING_MAINTAINER="Kataglyphis <dev@kataglyphis.local>"
export APP_PACKAGING_DESCRIPTION="Kataglyphis inference engine desktop app."
APP_PACKAGING_ICON_FALLBACKS=("assets/icons/kataglyphis_app_icon.png")

antfrastructure_source linux/scripts/lib/app-packaging.sh

# Aliases for the upstream app_packaging_ names — see BACKLOG.md.
setup_packaging_dependencies_for_container() { app_packaging_setup_dependencies_for_container "$@"; }
run_command_with_packaging_runtime()         { app_packaging_run_command_with_runtime "$@"; }
package_linux_bundle_tar()                   { app_packaging_package_linux_bundle_tar "$@"; }
package_linux_bundle_deb()                   { app_packaging_package_linux_bundle_deb "$@"; }
package_linux_bundle_appimage()              { app_packaging_package_linux_bundle_appimage "$@"; }
package_linux_bundle_flatpak()               { app_packaging_package_linux_bundle_flatpak "$@"; }
package_android_apk_outputs_tar()            { app_packaging_package_android_apk_outputs_tar "$@"; }
