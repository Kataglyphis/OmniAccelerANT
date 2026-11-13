#!/usr/bin/env bash
# Fixture repos for the suite discovery and its one runner; it does not run the suites the real tree discovers.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/linux/tests/harness-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness-bootstrap.sh"
# shellcheck source=scripts/linux/lib/suite-inventory.sh
source "${SUITE_INVENTORY_LIB:-${repo}/scripts/linux/lib/suite-inventory.sh}"
work="$(mktemp -d)" || exit 1
trap 'rm -rf -- "${work}"' EXIT

fixture() {
  local dir="${work}/$1"
  mkdir -p "${dir}/scripts/linux/tests" "${dir}/scripts/linux/ci" "${dir}/scripts/windows/tests" "${dir}/scripts/licenses/tests"
  git -C "${dir}" init -q
  printf '%s\n' "${dir}"
}

track() {
  local dir="$1" path="$2" body="$3"
  printf '%s\n' "${body}" > "${dir}/${path}"
  git -C "${dir}" add -- "${path}"
}

# assert_report <dir> <rc> <text>...: the report's verdict and the lines an operator reads.
assert_report() {
  local out rc text
  out="$(suite_inventory_report "$1" 2>&1)" && rc=0 || rc=$?
  t_assert_eq "$2" "${rc}"
  for text in "${@:3}"; do t_assert_contains "${out}" "${text}"; done
}

t_case 'every undeclared suite runs here and a named runner counts as elsewhere'
ok="$(fixture ok)"
track "${ok}" scripts/linux/tests/test-a.sh $'#!/usr/bin/env bash\nexit 0'
track "${ok}" scripts/linux/tests/test-b.py $'#!/usr/bin/env python3\n# suite-runner: scripts/linux/ci/web.sh'
track "${ok}" scripts/windows/tests/test_c.py '"""c"""'
track "${ok}" scripts/licenses/tests/test_d.py '"""d"""'
track "${ok}" scripts/linux/ci/web.sh 'bash scripts/linux/tests/test-b.py'
track "${ok}" scripts/linux/tests/helper.sh 'not a suite'
assert_report "${ok}" 0 '4 discovered, 3 run by this lane, 1 run elsewhere, 0 unreferenced suites'
native="$(suite_inventory_native "${ok}")"
t_assert_eq $'scripts/licenses/tests/test_d.py\nscripts/linux/tests/test-a.sh\nscripts/windows/tests/test_c.py' "${native}"

t_case 'a declared runner that does not name the suite is unreferenced and fails'
bad="$(fixture bad)"
track "${bad}" scripts/linux/tests/test-a.sh $'#!/usr/bin/env bash\n# suite-runner: scripts/linux/ci/web.sh'
track "${bad}" scripts/linux/ci/web.sh 'bash scripts/linux/tests/test-other.sh'
assert_report "${bad}" 1 'UNREFERENCED scripts/linux/tests/test-a.sh' '1 discovered, 0 run by this lane, 0 run elsewhere, 1 unreferenced suites'
t_assert_eq '' "$(suite_inventory_native "${bad}")"

t_case 'a declared runner that does not exist is unreferenced'
gone="$(fixture gone)"
track "${gone}" scripts/linux/tests/test-a.sh $'#!/usr/bin/env bash\n# suite-runner: scripts/linux/ci/missing.sh'
assert_report "${gone}" 1 '1 unreferenced suites'

t_case 'discovering no suite fails'
empty="$(fixture empty)"
track "${empty}" scripts/linux/tests/helper.sh 'not a suite'
assert_report "${empty}" 1 '0 discovered'

t_case 'an untracked suite is not discovered'
untracked="$(fixture untracked)"
track "${untracked}" scripts/linux/tests/test-a.sh 'exit 0'
printf 'exit 0\n' > "${untracked}/scripts/linux/tests/test-b.sh"
t_assert_eq 'scripts/linux/tests/test-a.sh' "$(suite_inventory_discover "${untracked}")"

t_case 'a suite runs by its interpreter and its status is kept'
track "${ok}" scripts/linux/tests/test-fail.sh 'exit 3'
suite_inventory_run "${ok}" scripts/linux/tests/test-fail.sh >/dev/null 2>&1 && rc=0 || rc=$?
t_assert_eq 3 "${rc}"
suite_inventory_run "${ok}" scripts/linux/tests/test-b.py >/dev/null 2>&1 && rc=0 || rc=$?
t_assert_eq 0 "${rc}"

t_case 'this tree discovers suites, leaves none unreferenced, and the native lane runs them through the file of the push hook'
# A mutation mirror carries no .git, so the tree's suites and runners are indexed in a scratch copy.
tree="${work}/tree"
mkdir -p "${tree}"
cp -R "${repo}/scripts" "${repo}/.github" "${repo}/.gitignore" "${tree}/"
git -C "${tree}" init -q && git -C "${tree}" add -A
assert_report "${tree}" 0 ' 0 unreferenced suites' 'scripts/windows/tests/test-ort-device.py runs in .github/workflows/windows-x64.yml'
lane="${repo}/scripts/linux/ci/lane-native-linux.sh"
t_assert_grep "${lane}" '^run_gate "script suites" bash scripts/linux/pre-push-checks\.sh --lane$'

# run_checks <dir> [flag]: the fixture tree's own copy of the runner, under a lane's exported root, which it must not grade; sets out and rc.
mkdir "${work}/elsewhere"
run_checks() { out="$(KATAGLYPHIS_REPO_ROOT="${work}/elsewhere" bash "$1/scripts/linux/pre-push-checks.sh" "${@:2}" 2>&1)" && rc=0 || rc=$?; }

t_case 'pre-push-checks.sh runs every suite of its own tree that names no other runner'
checks="$(fixture checks)"
mkdir -p "${checks}/scripts/linux/lib" "${checks}/third_party"
cp "${repo}/scripts/linux/pre-push-checks.sh" "${checks}/scripts/linux/"
cp "${repo}/scripts/linux/lib/antfrastructure.sh" "${repo}/scripts/linux/lib/renovate-git-mode.sh" \
  "${SUITE_INVENTORY_LIB:-${repo}/scripts/linux/lib/suite-inventory.sh}" "${checks}/scripts/linux/lib/"
ln -s "${ANTFRASTRUCTURE_DIR}" "${checks}/third_party/ANTfrastructure"
track "${checks}" scripts/linux/tests/test-a.sh $'#!/usr/bin/env bash\necho ran-a'
track "${checks}" scripts/linux/tests/test-b.py 'print("ran-b")'
track "${checks}" scripts/linux/tests/test-elsewhere.sh $'#!/usr/bin/env bash\n# suite-runner: scripts/linux/ci/web.sh\necho ran-elsewhere'
track "${checks}" scripts/linux/ci/web.sh 'bash scripts/linux/tests/test-elsewhere.sh'
track "${checks}" scripts/linux/tests/test-image.sh $'#!/usr/bin/env bash\n# suite-lane-only: a tool only the image has\necho ran-image'
run_checks "${checks}" --lane
t_assert_eq 0 "${rc}" "${out}"
t_assert_contains "${out}" '4 discovered, 3 run by this lane, 1 run elsewhere, 0 unreferenced suites'
t_assert_contains "${out}" 'ran-a'
t_assert_contains "${out}" 'ran-b'
t_assert_contains "${out}" 'ran-image' "the lane runs a lane-only suite"
t_assert_eq '' "$(printf '%s\n' "${out}" | grep -F 'ran-elsewhere')" "a suite with another runner is not this file's"

t_case 'without --lane, as the push hook calls it, a lane-only suite is skipped with its reason and the rest still decide'
t_assert_eq 'a tool only the image has' "$(suite_inventory_lane_only "${checks}/scripts/linux/tests/test-image.sh")"
t_assert_eq '' "$(suite_inventory_lane_only "${checks}/scripts/linux/tests/test-a.sh")"
run_checks "${checks}"
t_assert_eq 0 "${rc}" "${out}"
t_assert_contains "${out}" 'suite test-image.sh: SKIPPED (the lane runs it: it needs a tool only the image has)'
t_assert_eq '' "$(printf '%s\n' "${out}" | grep -Fx 'ran-image')" "skipped means not run"
t_assert_contains "${out}" 'ran-a'
run_checks "${checks}" --all
t_assert_eq 2 "${rc}" "an unknown flag is a usage error, never a run of fewer suites"

t_case 'one failing suite fails it after the others ran, and so does an unreferenced suite'
track "${checks}" scripts/linux/tests/test-0-fail.sh 'exit 3'
run_checks "${checks}"
t_assert_eq 1 "${rc}" "${out}"
t_assert_contains "${out}" 'suite test-0-fail.sh: FAILED (exit 3)'
t_assert_contains "${out}" 'ran-a' "the suites after the failing one still ran"
git -C "${checks}" rm -q -f --cached scripts/linux/tests/test-0-fail.sh
track "${checks}" scripts/linux/ci/web.sh 'bash scripts/linux/tests/test-other.sh'
run_checks "${checks}"
t_assert_eq 1 "${rc}" "${out}"
t_assert_contains "${out}" 'suite inventory: FAILED'

t_summary
