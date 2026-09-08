#!/usr/bin/env bash
set -euo pipefail

# The repo's lint gates — shellcheck, actionlint (+ CI image refs) and the
# gitleaks secret scan — in ONE command that CI and a developer both run.
#
#   bash scripts/linux/run-lint-gates.sh [<repo root>]
#
# THIS IS A WRAPPER. All three gates, the git-ls-files scope construction, the
# empty-scope vacuity guards and the run-all-three-then-fail-once accumulator
# live upstream in ContainerHub's linux/scripts/run-lint-gates.sh. Until now
# this repo had NO local entry point for any of them: they existed only as three
# `run:` blocks in .github/workflows/dart_on_native_linux.yml, so the gate that
# blocks a merge could not be reproduced on a dev box at all. That workflow job
# now calls this file, which is the whole point — one implementation, run by the
# owner and by CI.
#
# WHAT UPSTREAM ADDS over the three inline blocks it replaces:
#   * a gitleaks SELF-TEST — an empty tree must scan clean, and a planted PAT
#     must be reported AT THE PATH IT WAS GIVEN and must make the gate exit
#     non-zero. That is what separates "found nothing" from "never ran".
#   * a secret scope built from `git ls-files` instead of the whole workspace,
#     so the scan grades this repo and not the contents of third_party/.
#   * `git ls-files -z`, which survives the non-ASCII directory this repo has
#     at its root ("dummy_assetsä); the workflow's plain ls-files quoted it.
#   * all three gates run even after one fails, so one push shows one triage
#     list instead of three.
#
# WHAT IS NOT HERE, and why: the Sync-SharedConfig.ps1 -Check gate. It is
# PowerShell, and none of ContainerHub's Linux images ship pwsh, so it cannot
# join a bash aggregator. It stays a step of the same workflow job, on the
# hosted runner where pwsh is preinstalled.
#
# WHY --exclude third_party AND NOT rust_builder, although every other gate in
# this repo exempts rust_builder/cargokit/: upstream's --exclude drops a
# TOP-LEVEL directory, and cargokit is one level further down. Excluding
# rust_builder would also drop 13 tracked first-party files from the SECRET
# scope — including rust_builder/android/gradle.properties, which is precisely
# where an Android signing password lives. Losing secret coverage to spare a
# vendored file a shell lint is the wrong trade. Measured, not assumed: both
# vendored Cargokit scripts (build_pod.sh, run_build_tool.sh) pass this repo's
# shell gate today — 19 tracked *.sh, `-S error` clean. If a future Cargokit
# bump breaks that, the fix is an upstream --exclude that takes a path prefix,
# not a suppression here.
#
# (A comment line here may not START with the word after `#` that names the
# linter: it is read as a directive. SC1072 caught exactly that in this header.)

_run_lint_gates_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/containerhub.sh
source "${_run_lint_gates_dir}/lib/containerhub.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/linux/run-lint-gates.sh [<repo root>]

Runs ContainerHub's shellcheck, actionlint and gitleaks gates over this
repository. The root defaults to this checkout; CI passes $GITHUB_WORKSPACE.
EOF
}

REPO_ROOT_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$REPO_ROOT_ARG" ]]; then
        echo "Error: at most one repo root may be given (got '$REPO_ROOT_ARG' and '$1')" >&2
        exit 2
      fi
      REPO_ROOT_ARG="$1"
      shift
      ;;
  esac
done

TARGET_ROOT="${REPO_ROOT_ARG:-$KATAGLYPHIS_REPO_ROOT}"

# The root is passed explicitly and never inferred by the upstream script: it
# runs from INSIDE third_party/ContainerHub, where anything derived from its own
# location resolves to the submodule and every gate reports green over the wrong
# tree. That is the same bug that made lint-secrets.sh and lint-workflows.sh
# take a root in the first place.
if ! containerhub_path linux/scripts/run-lint-gates.sh >/dev/null; then
  echo "" >&2
  echo "The aggregator is missing from the pinned ContainerHub. The three gates it" >&2
  echo "drives (lint-shell.sh, lint-workflows.sh, lint-secrets.sh) are all present," >&2
  echo "so this is a pin that predates linux/scripts/run-lint-gates.sh, not a broken" >&2
  echo "checkout. Bump the submodule:" >&2
  echo "  git -C third_party/ContainerHub fetch origin && git -C third_party/ContainerHub checkout <sha>" >&2
  exit 1
fi

containerhub_exec linux/scripts/run-lint-gates.sh "$TARGET_ROOT" --exclude third_party
