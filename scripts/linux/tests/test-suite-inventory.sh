#!/usr/bin/env bash
# Fixture repos for the native lane's suite discovery; it does not run the suites the real tree discovers.
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

t_case 'this tree discovers suites, leaves none unreferenced, and the native lane runs the discovered set'
# A mutation mirror carries no .git, so the tree's suites and runners are indexed in a scratch copy.
tree="${work}/tree"
mkdir -p "${tree}"
cp -R "${repo}/scripts" "${repo}/.github" "${repo}/.gitignore" "${tree}/"
git -C "${tree}" init -q && git -C "${tree}" add -A
assert_report "${tree}" 0 ' 0 unreferenced suites' 'scripts/windows/tests/test-ort-device.py runs in .github/workflows/windows-x64.yml'
lane="${repo}/scripts/linux/ci/lane-native-linux.sh"
t_assert_grep "${lane}" "^run_gate \"suite inventory\" suite_inventory_report \"\\\$REPO_ROOT\"\$"
t_assert_grep "${lane}" "^done < <\\(suite_inventory_native \"\\\$REPO_ROOT\"\\)\$"

t_summary
