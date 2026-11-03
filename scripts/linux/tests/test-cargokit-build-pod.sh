#!/usr/bin/env bash
# The podspecs run build_pod.sh with sh; this runs it under this host's sh, which may not be the macOS one.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/linux/tests/harness-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness-bootstrap.sh"
script="${BUILD_POD_SCRIPT:-${repo}/rust_builder/cargokit/build_pod.sh}"
t_workdir

# run_pod <exported-environment-dir>: the script in a scratch cargokit beside a run_build_tool.sh that records its view.
run_pod() {
  local pods="${work}/$1/Pods" kit="${work}/$1/cargokit" built="${work}/$1/built"
  mkdir -p "${pods}" "${kit}" "${built}"
  cp "${script}" "${kit}/build_pod.sh"
  printf 'printf "%%s\\n" "$FROM_FLUTTER" "$1" "$2" > "%s/saw"\n' "${work}/$1" > "${kit}/run_build_tool.sh"
  env PODS_ROOT="${pods}" PODS_TARGET_SRCROOT="${work}/$1" OBJROOT="${work}" BUILT_PRODUCTS_DIR="${built}" \
    EXECUTABLE_PATH=app FROM_FLUTTER=unset sh "${kit}/build_pod.sh" manifest crate >/dev/null
}

for layout in Flutter/ephemeral Flutter; do
  name="${layout//\//-}"
  mkdir -p "${work}/${name}/${layout}"
  printf 'FROM_FLUTTER=%s\n' "${layout}" > "${work}/${name}/${layout}/flutter_export_environment.sh"
  t_case "sh reads ${layout}'s exported environment and reaches the build tool"
  run_pod "${name}"
  t_assert_eq 0 "$?"
  t_assert_eq "${layout} build-pod manifest" "$(tr '\n' ' ' < "${work}/${name}/saw" | sed 's/ $//')"
  t_assert_ok test -L "${work}/${name}/built/cargokit_phony"
done

t_case "sh runs with no exported environment at all"
run_pod none
t_assert_eq 0 "$?"
t_assert_eq "unset build-pod manifest" "$(tr '\n' ' ' < "${work}/none/saw" | sed 's/ $//')"

t_summary
