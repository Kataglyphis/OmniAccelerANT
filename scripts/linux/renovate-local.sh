#!/usr/bin/env bash
set -euo pipefail

# Dependency upgrades for this repo, driven by Renovate run as a LOCAL CLI.
#
#   bash scripts/linux/renovate-local.sh                    # report what is behind
#   bash scripts/linux/renovate-local.sh --apply --dry-run  # show the plan
#   bash scripts/linux/renovate-local.sh --apply            # move the gitlinks
#   bash scripts/linux/renovate-local.sh --managers <csv>   # default: git-submodules
#   bash scripts/linux/renovate-local.sh --print-bin        # resolved renovate.js
#
# THIS IS A WRAPPER. The tool itself — the pinned Node/Renovate bootstrap, the
# JSON report parse and the git half of --apply — lives upstream in
# ContainerHub's linux/scripts/renovate-local.sh. This file exists so the family
# tool has a local entry point here, next to run-lint-gates.sh, rather than
# being a path into third_party/ that everyone retypes. It is NOT a gate:
# nothing in .github/workflows/ runs it and it blocks no commit.
#
# WHAT IT COVERS. Owner directive 2026-09-09: SUBMODULE upgrades go through this
# rather than by hand. It is not a rule for every dependency this repo has —
# --apply moves gitlinks and nothing else, so pubspec.yaml is still yours to
# edit. Widening --managers buys a REPORT for the other managers, never an
# apply.
#
# THE ONE THING TO KNOW: `--platform=local` CANNOT WRITE. Renovate forces dryRun
# there, so it DETECTS and nothing else; the upstream script owns both halves —
# Renovate decides what is behind, git applies it. A run that leaves the tree
# byte-identical is the report mode working, not a broken script.
#
# WHY THE DEFAULT SCOPE IS WORTH LEAVING ALONE. Upstream defaults to
# `--managers git-submodules`, which answers in about four seconds. An unscoped run
# walks every manager it can detect in this tree and takes minutes, and it reports
# dependencies --apply cannot move (pubspec.yaml is pub's). Widen --managers
# deliberately, one manager at a time.
#
# WHAT --apply WILL DO IN THIS REPO: all four gitlinks — ANThology, ContainerHub,
# OxidANT, AccelerANTgine — declare a `branch =` in .gitmodules, so all four are
# eligible and none are refused. That entry is what makes them eligible: upstream
# passes EXPLICIT paths and never a bare `git submodule update --remote`, which
# walks a branchless submodule to the remote's DEFAULT branch. Nothing is staged
# or committed; review `git submodule summary` and stage what you meant.
#
# ON THIS HOST, RUN IT FROM WSL. The bootstrap wants Node major 24 —
# RENOVATE_NODE_VERSION in the hub's linux/scripts/01-core/versions.env, a
# SEPARATE pin from the canonical NODE_VERSION because Renovate declares
# engines.node "^24.11.0" — and there is no node on the Windows side at all.
# The report half is read-only and safe from anywhere. --apply additionally
# needs the git that WROTE the working tree, and upstream handles that for you:
# a Windows checkout read by the WSL git shows every text file as modified, so
# it switches to git.exe when WSL can reach it and refuses up front when it
# cannot, instead of half-applying.
#
# Rationale, the pins and the GitHub-token variant — the hub owns all of it:
# third_party/ContainerHub/docs/dependency-updates.md

_renovate_local_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/containerhub.sh
source "${_renovate_local_dir}/lib/containerhub.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/linux/renovate-local.sh [--apply] [--dry-run] [--managers <csv>]
                                       [--print-bin] [<repo root>]

Reports which of this repo's dependencies are behind, per .github/renovate.json,
and with --apply moves the submodule gitlinks Renovate named. Options are passed
straight through to ContainerHub's renovate-local.sh; see
third_party/ContainerHub/docs/dependency-updates.md.

The root defaults to this checkout. Give an override as an ABSOLUTE path: this
wrapper runs from the repo root, so a relative one resolves against that.
EOF
}

# --help ANYWHERE, like the sibling wrappers' parse loops — but only SCANNED,
# never consumed: everything else is forwarded to upstream untouched.
for _arg in "$@"; do
  case "${_arg}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
done

if ! containerhub_path linux/scripts/renovate-local.sh >/dev/null; then
  echo "" >&2
  echo "The Renovate driver is missing from the pinned ContainerHub. It is a newer" >&2
  echo "addition than this pin, not a broken checkout. Bump the submodule:" >&2
  echo "  git -C third_party/ContainerHub fetch origin && git -C third_party/ContainerHub checkout <sha>" >&2
  exit 1
fi

# No root is passed: upstream defaults its target to $PWD, and pinning the cwd
# here means a run from a subdirectory still grades this repo instead of it. An
# explicit root given by the caller is forwarded below and still wins.
cd "$KATAGLYPHIS_REPO_ROOT"

containerhub_exec linux/scripts/renovate-local.sh "$@"
