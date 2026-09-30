#!/usr/bin/env bash
set -euo pipefail

# Wraps the hub's Renovate CLI runner. See docs/source/project-operations.md § Dependency upgrades, in detail

_renovate_local_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${_renovate_local_dir}/lib/antfrastructure.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/linux/renovate-local.sh [--apply] [--dry-run] [--managers <csv>]
                                       [--print-bin] [<repo root>]

Reports which of this repo's dependencies are behind, per .github/renovate.json,
and with --apply moves the submodule gitlinks Renovate named. Options are passed
straight through to ANTfrastructure's renovate-local.sh; see
third_party/ANTfrastructure/docs/dependency-updates.md.

The root defaults to this checkout. Give an override as an ABSOLUTE path: this
wrapper runs from the repo root, so a relative one resolves against that.
EOF
}

# --help is only scanned, never consumed: everything else goes to upstream untouched.
for _arg in "$@"; do
  case "${_arg}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
done

if ! antfrastructure_path linux/scripts/renovate-local.sh >/dev/null; then
  echo "" >&2
  echo "The Renovate driver is missing from the pinned ANTfrastructure. It is a newer" >&2
  echo "addition than this pin, not a broken checkout. Bump the submodule:" >&2
  echo "  git -C third_party/ANTfrastructure fetch origin && git -C third_party/ANTfrastructure checkout <sha>" >&2
  exit 1
fi

# Upstream targets $PWD, so a run from a subdirectory still grades this repo; an explicit root still wins.
cd "$KATAGLYPHIS_REPO_ROOT"

antfrastructure_exec linux/scripts/renovate-local.sh "$@"
