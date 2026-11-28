#!/usr/bin/env bash
# The native lane's plugin ELF gate: the spec it passes the hub gate, run on a hardened fixture and one per missing property.
set -uo pipefail

# shellcheck source=scripts/linux/tests/harness-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness-bootstrap.sh"
lane="${PLUGIN_ELF_LANE:-${KATAGLYPHIS_REPO_ROOT}/scripts/linux/ci/lane-native-linux.sh}"
gate="$(antfrastructure_path linux/scripts/06-packaging/verify-elf-hardening.sh)" || exit 1
t_workdir

t_case "the release gates run the hub's ELF gate on the bundled plugin"
spec="$(grep -oE '/libkataglyphis_native_inference_plugin\.so:[a-z:-]+"' "${lane}" | head -1 | tr -d '"')"
t_assert_eq "/libkataglyphis_native_inference_plugin.so:library:no-fortify" "${spec}"
t_assert_ok grep -qE 'run_gate "plugin ELF hardening" bash "\$\(antfrastructure_path linux/scripts/06-packaging/verify-elf-hardening\.sh\)"' "${lane}"

printf 'int f(int x) { char b[64]; __builtin_memset(b, x, sizeof b); return b[x & 63]; }\n' > "${work}/f.c"
# build <name> <flags...>: a shared library like the plugin, with exactly the given hardening flags.
build() { local name="$1"; shift; cc -shared -fPIC -O2 "$@" -o "${work}/${name}.so" "${work}/f.c"; }
build hardened -fstack-protector-all -Wl,-z,relro,-z,now || exit 1
build lazy -fstack-protector-all -Wl,-z,relro,-z,lazy || exit 1
build unprotected -fno-stack-protector -Wl,-z,relro,-z,now || exit 1
build norelro -fstack-protector-all -Wl,-z,norelro,-z,now || exit 1

t_case "the lane's spec passes a hardened library and refuses each missing property"
t_assert_ok bash "${gate}" "${work}/hardened.so${spec#*.so}"
t_assert_fails bash "${gate}" "${work}/lazy.so${spec#*.so}"
t_assert_fails bash "${gate}" "${work}/unprotected.so${spec#*.so}"
t_assert_fails bash "${gate}" "${work}/norelro.so${spec#*.so}"

t_summary
