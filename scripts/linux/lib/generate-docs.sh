#!/usr/bin/env bash
set -euo pipefail

# Builds this repo's `dart doc` site: generate, theme, dark-by-default, images,
# Markdown guides with sidebar navigation, then chown back to the host user in
# CI.
#
# THIS IS A WRAPPER over ANTfrastructure's linux/scripts/lib/dartdoc-build.sh,
# whose header states the contract implemented below: "A wrapper sets the
# DARTDOC_BUILD_* variables, sources this file and calls dartdoc_build_main."
# What used to be here was a hand-written re-implementation of all eight steps —
# the same awk-to-marker CSS truncation, the same light->dark sed, the same
# `cp -a`, the same stat/chown — plus a 177-line inline Python heredoc. Seven of
# the eight steps are now the upstream ones, and only the CONFIGURATION is this
# repository's: the guide list, the brand strings, the theme sheet.
#
# WHY dartdoc_build_main IS NOT CALLED, and why one step stays local:
# upstream's dartdoc_build_render_guides drives lib/dartdoc-guides.py, whose
# inject_sidebar_nav() raises SystemExit on any page with no bare `<ol>` after
# `<div id="dartdoc-sidebar-left"`. That is not drift in dart doc's shell —
# dartdoc 9.0.4 emits TWO page shapes, and on this repo's tree 1030 of 1459
# pages are the second kind: their left sidebar is
# `<div id="dartdoc-sidebar-left-content"></div>`, filled at runtime from one of
# 232 `*-sidebar.html` fragments, so there is no static list to hang a nav on.
# Measured, not guessed: run against the upstream renderer this dies on the
# first such page (an AboutMeTable constructor page whose only `<ol>`s are
# `class="breadcrumbs"` and `class="parameter-list"`).
# The renderer below is therefore KEPT, with the tolerant per-page skip its
# predecessor had — plus the vacuity guard it did NOT have, so a run that
# navigates nothing fails instead of reporting success.
# RETIRE THIS BLOCK once ANTfrastructure's inject_sidebar_nav treats a JS-filled
# sidebar as a legitimate no-op: delete the heredoc and call
# dartdoc_build_render_guides. The config written for it is already upstream's
# exact tab-separated format, so nothing else has to change.
#
# Local invocation is unchanged and is the one the docs quote:
#   bash scripts/linux/lib/generate-docs.sh
# CI reaches it through scripts/linux/run-native-linux.sh, same arguments.

_generate_docs_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/container-steps.sh
source "${_generate_docs_dir}/container-steps.sh"

# KEPT, and not upstream's business: the image puts Flutter on PATH through
# ~/.bashrc, which a non-interactive `bash script.sh` never reads.
# dartdoc_build_generate runs `flutter clean` and `dart doc` as commands, so
# PATH has to be right before it is called.
source_bashrc_and_add_flutter_to_path

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
DARTDOC_BUILD_CLEAN_CMD=(flutter clean)
DARTDOC_BUILD_DOC_CMD=(dart doc)

# The Sphinx press-theme override sheet, shared with the Sphinx site so both
# render the same brand. Its first line is the marker upstream truncates a
# previous append at, so a rebuild replaces rather than stacks.
DARTDOC_BUILD_THEME_CSS="${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/_static/css/dartdoc-theme-overrides.css"
DARTDOC_BUILD_IMAGES_DIR="${DARTDOC_BUILD_PROJECT_ROOT}/images"

DARTDOC_BUILD_TITLE_SUFFIX="Kataglyphis Docs"
DARTDOC_BUILD_FOOTER_TITLE="Kataglyphis Docs"

# `<source markdown>|<slug>|<nav title>`. The slug names both the staged
# doc/api/md/<slug>.md and the emitted doc/api/guide-<slug>.html, so these slugs
# are the file names the predecessor's hand-written map produced — the published
# URLs do not move. This array is now the ONLY copy of the list; it used to be
# maintained twice, once as a bash array and once as a Python list.
DARTDOC_BUILD_GUIDES=(
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/INTRODUCTION.md|introduction|Introduction"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/README.md|docs-readme|Docs README"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/overview.md|overview|Overview"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/getting-started.md|getting-started|Getting Started"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/platforms.md|platforms|Platforms"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/camera-streaming.md|camera-streaming|Camera Streaming"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/readmes.md|readmes|Readmes"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/project-operations.md|project-operations|Project Operations"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/roadmap.md|roadmap|Roadmap"
	"${DARTDOC_BUILD_PROJECT_ROOT}/docs/source/upgrade-guide.md|upgrade-guide|Upgrade Guide"
)

# `<label>|<url>`. These were a heredoc of literal <a> tags before.
DARTDOC_BUILD_FOOTER_LINKS=(
	"Repository|https://github.com/Kataglyphis/OmniAccelerANT"
	"README|https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/README.md"
	"Guides|https://github.com/Kataglyphis/OmniAccelerANT/tree/develop/docs/source"
)

export DARTDOC_BUILD_THEME_CSS DARTDOC_BUILD_IMAGES_DIR \
	DARTDOC_BUILD_TITLE_SUFFIX DARTDOC_BUILD_FOOTER_TITLE

antfrastructure_source linux/scripts/lib/dartdoc-build.sh

dartdoc_build_generate
dartdoc_build_apply_theme
dartdoc_build_default_dark
dartdoc_build_copy_images
dartdoc_build_stage_guides
dartdoc_build_prepare_python_env

# --- the one local step, driven by upstream's own config format --------------
DOC_API_DIR="${DARTDOC_BUILD_PROJECT_ROOT}/doc/api"
RENDER_CONFIG="$(mktemp)"
trap 'rm -f "$RENDER_CONFIG"' EXIT
{
	printf 'title_suffix\t%s\n' "$DARTDOC_BUILD_TITLE_SUFFIX"
	printf 'footer_title\t%s\n' "$DARTDOC_BUILD_FOOTER_TITLE"
	for _entry in "${DARTDOC_BUILD_GUIDES[@]}"; do
		IFS='|' read -r _src _slug _title <<<"$_entry"
		printf 'guide\t%s\t%s\n' "$_slug" "$_title"
	done
	for _entry in "${DARTDOC_BUILD_FOOTER_LINKS[@]}"; do
		IFS='|' read -r _label _url <<<"$_entry"
		printf 'footer\t%s\t%s\n' "$_label" "$_url"
	done
} >"$RENDER_CONFIG"

"$DARTDOC_BUILD_PYTHON" "${_generate_docs_dir}/dartdoc-guides-local.py" \
	"$DOC_API_DIR" "$RENDER_CONFIG"

dartdoc_build_fix_ownership
echo "[Info] Dartdoc site build completed successfully"
