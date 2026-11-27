#!/usr/bin/env bash
# The unwinder-order gate on executables linked against a stand-in for Flutter 3.50's engine, which exports _Unwind_RaiseException.
set -uo pipefail

# shellcheck source=scripts/linux/tests/harness-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness-bootstrap.sh"
gate="${KATAGLYPHIS_REPO_ROOT}/scripts/linux/check-unwinder-order.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

printf 'int _Unwind_RaiseException(void *e) { (void)e; return 5; }\n' > "${work}/engine.c"
cc -shared -fPIC -o "${work}/libengine.so" "${work}/engine.c" || exit 1
printf 'int main(void) { return 0; }\n' > "${work}/main.c"
link() {
  local out="$1"
  shift
  cc -o "${work}/${out}" "${work}/main.c" -L"${work}" -Wl,-rpath,"${work}" -Wl,--no-as-needed "$@" || exit 1
}
link engine-first -lengine -lgcc_s
link gcc-first -lgcc_s -lengine
link gcc-only -lgcc_s
printf 'int g(void) { return 1; }\n' > "${work}/gone.c"
cc -shared -fPIC -o "${work}/libgone.so" "${work}/gone.c" || exit 1
link unresolved -lgcc_s -lgone
rm -f "${work}/libgone.so"
# A relocatable bundle's launcher: a script, with the ELF it starts beside it as <name>.bin.
for name in good-launcher bad-launcher bare-launcher; do printf '#!/bin/sh\nexec "$0.bin" "$@"\n' > "${work}/${name}"; done
cp "${work}/gcc-first" "${work}/good-launcher.bin"
cp "${work}/engine-first" "${work}/bad-launcher.bin"

t_case "libgcc_s ahead of an engine that exports the unwinder"
t_assert_rc 0 bash "$gate" "${work}/gcc-first"
t_case "the engine's unwinder ahead of libgcc_s"
t_assert_rc 1 bash "$gate" "${work}/engine-first"
t_case "only libgcc_s defines the unwinder"
t_assert_rc 0 bash "$gate" "${work}/gcc-only"
t_case "an unresolved library is not graded on a partial list"
t_assert_rc 1 bash "$gate" "${work}/unresolved"
t_case "a launcher is graded by the .bin it starts"
t_assert_rc 0 bash "$gate" "${work}/good-launcher"
t_case "a launcher whose .bin loads the engine's unwinder first"
t_assert_rc 1 bash "$gate" "${work}/bad-launcher"
t_case "a launcher without its .bin"
t_assert_rc 1 bash "$gate" "${work}/bare-launcher"
t_case "a missing executable"
t_assert_rc 1 bash "$gate" "${work}/absent"
t_case "nothing to check"
t_assert_rc 2 bash "$gate"

t_summary
