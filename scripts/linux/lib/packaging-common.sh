#!/usr/bin/env bash

# App-specific values only; the mechanics are upstream.
_packaging_common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_packaging_common_dir}/antfrastructure.sh"

export APP_PACKAGING_APP_ID_PREFIX="org.kataglyphis"
export APP_PACKAGING_COMMENT="OmniAccelerANT"
export APP_PACKAGING_MAINTAINER="Kataglyphis <dev@kataglyphis.local>"
export APP_PACKAGING_DESCRIPTION="Kataglyphis inference engine desktop app."
APP_PACKAGING_ICON_FALLBACKS=("assets/icons/kataglyphis_app_icon.png")
# Flatpak has no --device=video, and the Stream page opens /dev/video*; set empty to drop it (owner, 2026-10-01).
export KATAGLYPHIS_FLATPAK_FINISH_ARGS="${KATAGLYPHIS_FLATPAK_FINISH_ARGS---device=all}"

antfrastructure_source linux/scripts/lib/app-packaging.sh
