#!/usr/bin/env bash
set -euo pipefail

# The repo's lint gates — shellcheck, actionlint (+ CI image refs) and the
# gitleaks secret scan — in ONE command that CI and a developer both run.
#
#   bash scripts/linux/run-lint-gates.sh [<repo root>]
#
# THIS IS A WRAPPER. All three gates, the git-ls-files scope construction, the
# empty-scope vacuity guards and the run-all-three-then-fail-once accumulator
# live upstream in ANTfrastructure's linux/scripts/run-lint-gates.sh. Until now
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
# THE SHARED-CONFIG DRIFT GATE IS NOW HERE TOO, and this paragraph used to say
# the opposite: "it is PowerShell, and none of ANTfrastructure's Linux images ship
# pwsh, so it cannot join a bash aggregator." The premise was right and the
# conclusion was wrong - ANTfrastructure ships a bash TWIN,
# shared/config/sync-shared-config.sh, which takes the same --repo-root and
# --check and is held to the same verdicts as the PowerShell half. Upstream's
# aggregator now runs it as a fifth gate, so a developer sees drift on the same
# local run as shellcheck, and a repo cannot go green over the shared files
# again just because pwsh was unavailable.
#
# It compares what .antfrastructure-shared.manifest at this repo's root DECLARES -
# .cmake-format.yaml, scripts/linux/lib/antfrastructure.sh and
# scripts/windows/Resolve-BuildModule.ps1. The four config names this Flutter
# app never took are undeclared and are never looked at.
#
# The workflow's separate hosted-runner `Sync-SharedConfig.ps1 -Check` step is
# now a DUPLICATE of this gate, kept deliberately: it is the only thing in CI
# that exercises the PowerShell half, and the two halves are required to agree.
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
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${_run_lint_gates_dir}/lib/antfrastructure.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/linux/run-lint-gates.sh [<repo root>]

Runs ANTfrastructure's shellcheck, actionlint and gitleaks gates over this
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
# runs from INSIDE third_party/ANTfrastructure, where anything derived from its own
# location resolves to the submodule and every gate reports green over the wrong
# tree. That is the same bug that made lint-secrets.sh and lint-workflows.sh
# take a root in the first place.
if ! antfrastructure_path linux/scripts/run-lint-gates.sh >/dev/null; then
  echo "" >&2
  echo "The aggregator is missing from the pinned ANTfrastructure. The three gates it" >&2
  echo "drives (lint-shell.sh, lint-workflows.sh, lint-secrets.sh) are all present," >&2
  echo "so this is a pin that predates linux/scripts/run-lint-gates.sh, not a broken" >&2
  echo "checkout. Bump the submodule:" >&2
  echo "  git -C third_party/ANTfrastructure fetch origin && git -C third_party/ANTfrastructure checkout <sha>" >&2
  exit 1
fi

antfrastructure_exec linux/scripts/run-lint-gates.sh "$TARGET_ROOT" --exclude third_party
