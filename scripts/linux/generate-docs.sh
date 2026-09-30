#!/usr/bin/env bash
set -euo pipefail

# Builds the dart doc site with the hub's dartdoc_build_main; only the configuration below is this repo's.

_generate_docs_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/container-steps.sh
source "${_generate_docs_dir}/lib/container-steps.sh"

# No PATH set-up: the image's ENV PATH already carries /opt/flutter/bin.

# /workspace is the container's bind mount; on a host the tree is the current directory.
if [[ -d "/workspace" ]]; then
	DARTDOC_BUILD_PROJECT_ROOT="/workspace"
else
	DARTDOC_BUILD_PROJECT_ROOT="$(pwd)"
fi
export DARTDOC_BUILD_PROJECT_ROOT

# flutter clean first: a stale .dart_tool from another build mode yields the wrong package graph.
# shellcheck disable=SC2034  # read by dartdoc-build.sh, sourced into this shell
DARTDOC_BUILD_CLEAN_CMD=(flutter clean)
# shellcheck disable=SC2034  # same
DARTDOC_BUILD_DOC_CMD=(dart doc)

# Keep the sheet's name and "Sphinx press theme" first line: upstream truncates earlier appends at that marker.
DARTDOC_BUILD_THEME_CSS="${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/_static/css/dartdoc-theme-overrides.css"
DARTDOC_BUILD_IMAGES_DIR="${DARTDOC_BUILD_PROJECT_ROOT}/images"

DARTDOC_BUILD_TITLE_SUFFIX="Kataglyphis Docs"
DARTDOC_BUILD_FOOTER_TITLE="Kataglyphis Docs"

# `<source markdown>|<slug>|<nav title>`; a slug is a published file name (guide-<slug>.html), so renaming moves a URL.
# shellcheck disable=SC2034  # read by dartdoc_build_stage_guides / _render_guides
DARTDOC_BUILD_GUIDES=(
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/INTRODUCTION.md|introduction|Introduction"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/README.md|docs-readme|Docs README"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/overview.md|overview|Overview"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/getting-started.md|getting-started|Getting Started"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/platforms.md|platforms|Platforms"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/camera-streaming.md|camera-streaming|Camera Streaming"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/readmes.md|readmes|Readmes"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/project-operations.md|project-operations|Project Operations"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/upgrade-guide.md|upgrade-guide|Upgrade Guide"
)

# `<label>|<url>`.
# shellcheck disable=SC2034  # read by dartdoc_build_render_guides
DARTDOC_BUILD_FOOTER_LINKS=(
	"Repository|https://github.com/Kataglyphis/OmniAccelerANT"
	"README|https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/README.md"
	"Guides|https://github.com/Kataglyphis/OmniAccelerANT/tree/develop/docs/source"
)

export DARTDOC_BUILD_THEME_CSS DARTDOC_BUILD_IMAGES_DIR \
	DARTDOC_BUILD_TITLE_SUFFIX DARTDOC_BUILD_FOOTER_TITLE

antfrastructure_source linux/scripts/lib/dartdoc-build.sh

dartdoc_build_main
