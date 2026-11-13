#!/usr/bin/env bash
# Tracked test suites the native lane runs or sees named elsewhere; it does not prove a named runner executes a suite on push.

SUITE_INVENTORY_GLOBS=(
  'scripts/linux/tests/test-*.sh'
  'scripts/linux/tests/test-*.py'
  'scripts/windows/tests/test[-_]*.py'
  'scripts/licenses/tests/test_*.py'
)

# suite_inventory_discover <root>: the tracked suites, one repo-relative path per line.
suite_inventory_discover() {
  local root="${1:?repo root required}"
  git -C "${root}" ls-files -- "${SUITE_INVENTORY_GLOBS[@]}"
}

# suite_inventory_runner <file>: the `# suite-runner: <path>` a suite declares in its first 15 lines, or nothing.
suite_inventory_runner() {
  sed -n '1,15{/^# suite-runner: [^[:space:]]*$/{s/^# suite-runner: //;p;q;}}' "${1:?suite file required}"
}

# suite_inventory_lane_only <file>: why a suite needs the lane's image, from `# suite-lane-only: <why>` in its first 15 lines, or nothing.
suite_inventory_lane_only() {
  sed -n '1,15{/^# suite-lane-only: ./{s/^# suite-lane-only: //;p;q;}}' "${1:?suite file required}"
}

# suite_inventory_native <root>: the discovered suites that declare no other runner, so this lane runs them.
suite_inventory_native() {
  local root="${1:?repo root required}" listing suite
  listing="$(suite_inventory_discover "${root}")" || return 2
  while IFS= read -r suite; do
    if [ -n "${suite}" ] && [ -z "$(suite_inventory_runner "${root}/${suite}")" ]; then
      printf '%s\n' "${suite}"
    fi
  done <<< "${listing}"
  return 0
}

# suite_inventory_report <root>: counts every suite; fails when none is found or a declared runner does not name it.
suite_inventory_report() {
  local root="${1:?repo root required}" listing suite runner
  local discovered=0 here=0 elsewhere=0 unreferenced=0
  listing="$(suite_inventory_discover "${root}")" || {
    printf 'suite inventory: git ls-files failed in %s\n' "${root}" >&2
    return 2
  }
  while IFS= read -r suite; do
    [ -n "${suite}" ] || continue
    discovered=$((discovered + 1))
    runner="$(suite_inventory_runner "${root}/${suite}")"
    if [ -z "${runner}" ]; then
      here=$((here + 1))
    elif [ -f "${root}/${runner}" ] && grep -qF -e "${suite##*/}" "${root}/${runner}"; then
      elsewhere=$((elsewhere + 1))
      printf 'suite inventory: %s runs in %s\n' "${suite}" "${runner}"
    else
      unreferenced=$((unreferenced + 1))
      printf 'suite inventory: UNREFERENCED %s (its runner %s does not name it)\n' "${suite}" "${runner}" >&2
    fi
  done <<< "${listing}"
  printf 'suite inventory: %d discovered, %d run by this lane, %d run elsewhere, %d unreferenced suites\n' \
    "${discovered}" "${here}" "${elsewhere}" "${unreferenced}"
  if [ "${discovered}" -eq 0 ]; then
    printf 'suite inventory: no tracked suite matches %s\n' "${SUITE_INVENTORY_GLOBS[*]}" >&2
    return 1
  fi
  if [ "${unreferenced}" -gt 0 ]; then
    return 1
  fi
  return 0
}

# suite_inventory_run <root> <suite>: one suite, by its interpreter.
suite_inventory_run() {
  local root="${1:?repo root required}" suite="${2:?suite required}"
  case "${suite}" in
    *.py) python3 -I "${root}/${suite}" ;;
    *.sh) bash "${root}/${suite}" ;;
    *)
      printf 'suite inventory: no interpreter for %s\n' "${suite}" >&2
      return 2
      ;;
  esac
}
