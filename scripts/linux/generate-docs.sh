#!/usr/bin/env bash
set -euo pipefail

# Builds this repo's `dart doc` site: generate, theme, dark-by-default, images,
# Markdown guides with sidebar navigation, then chown back to the host user in
# CI. THIS IS A WRAPPER over ANTfrastructure's linux/scripts/lib/dartdoc-build.sh
# and now calls its full pipeline, dartdoc_build_main; only the CONFIGURATION
# below is this repository's - the guide list, the brand strings, the theme
# sheet. Local invocation is the one the docs quote:
#   bash scripts/linux/generate-docs.sh
# CI reaches it through scripts/linux/run-native-linux.sh, same arguments.
# See docs/source/project-operations.md for the renderer fork this retired.

_generate_docs_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# This wrapper sits in scripts/linux/ because it is an executable, not a
# library; lib/ holds only sourced files.
# shellcheck source=scripts/linux/lib/container-steps.sh
source "${_generate_docs_dir}/lib/container-steps.sh"

# NO PATH SET-UP HERE. The comment that stood here said the image puts Flutter
# on PATH "through ~/.bashrc"; it does not - Dockerfile.package:268 sets ENV
# PATH with /opt/flutter/bin in it, which every shell inherits, login or not. On
# a host, `dart doc` comes from the developer's own PATH, as it always did.

# KEPT: /workspace is the container bind mount of this repo; on the host it does
# not exist and the tree is the current directory. Upstream derives doc/ from
# this root, so setting it reproduces the previous DOC_ROOT exactly.
if [[ -d "/workspace" ]]; then
	DARTDOC_BUILD_PROJECT_ROOT="/workspace"
else
	DARTDOC_BUILD_PROJECT_ROOT="$(pwd)"
fi
export DARTDOC_BUILD_PROJECT_ROOT

# `flutter clean` before `dart doc`: dartdoc reads .dart_tool, and a stale one
# from another build mode makes it emit pages for the wrong package graph.
# shellcheck disable=SC2034  # read by dartdoc-build.sh, sourced into this shell
DARTDOC_BUILD_CLEAN_CMD=(flutter clean)
# shellcheck disable=SC2034  # same
DARTDOC_BUILD_DOC_CMD=(dart doc)

# The brand override sheet. Its name and its first line still say "Sphinx press
# theme" because that first line is the marker upstream truncates a previous
# append at, so a rebuild replaces rather than stacks -- renaming either would
# make every rebuild stack instead. There is no Sphinx site any more; the
# scaffolding was deleted on 2026-09-15 and this sheet has one consumer.
DARTDOC_BUILD_THEME_CSS="${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/_static/css/dartdoc-theme-overrides.css"
DARTDOC_BUILD_IMAGES_DIR="${DARTDOC_BUILD_PROJECT_ROOT}/images"

DARTDOC_BUILD_TITLE_SUFFIX="Kataglyphis Docs"
DARTDOC_BUILD_FOOTER_TITLE="Kataglyphis Docs"

# `<source markdown>|<slug>|<nav title>`. The slug names both the staged
# doc/api/md/<slug>.md and the emitted doc/api/guide-<slug>.html, so these slugs
# are the file names the predecessor's hand-written map produced — the published
# URLs do not move. This array is now the ONLY copy of the list; it used to be
# maintained twice, once as a bash array and once as a Python list.
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

# `<label>|<url>`. These were a heredoc of literal <a> tags before.
# shellcheck disable=SC2034  # read by dartdoc_build_render_guides
DARTDOC_BUILD_FOOTER_LINKS=(
	"Repository|https://github.com/Kataglyphis/OmniAccelerANT"
	"README|https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/README.md"
	"Guides|https://github.com/Kataglyphis/OmniAccelerANT/tree/develop/docs/source"
)

export DARTDOC_BUILD_THEME_CSS DARTDOC_BUILD_IMAGES_DIR \
	DARTDOC_BUILD_TITLE_SUFFIX DARTDOC_BUILD_FOOTER_TITLE

antfrastructure_source linux/scripts/lib/dartdoc-build.sh

# The whole upstream pipeline, not seven of its eight steps. The eighth,
# dartdoc_build_render_guides, used to be re-implemented here against a local
# copy of upstream's renderer (lib/dartdoc-guides-local.py) because upstream's
# inject_sidebar_nav raised SystemExit on any page whose left sidebar is the
# JS-filled `dartdoc-sidebar-left-content` div - 1030 of this site's 1459 pages.
# ANTfrastructure took that tolerance, and the matching one for the 232
# `*-sidebar.html` fragments in inject_footer, plus the footer vacuity guard
# that keeps both honest. The fork and its config-writing block are gone.
dartdoc_build_main
