#!/usr/bin/env bash
# Exercises the app's host-runtime integration; actual GPU inference needs hardware.
set -euo pipefail
# shellcheck source=scripts/linux/tests/fixture-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/fixture-common.sh"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$root/scripts/linux/lib/antfrastructure.sh"
source "$root/scripts/linux/lib/bundle-runtime.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/cpu/lib" "$work/gpu/lib" "$work/old"
[[ "$(gpu_package_name omni-accelerant cuda)" == omni-accelerant-nvidia ]]
[[ "$(gpu_package_name omni-accelerant migraphx)" == omni-accelerant-amd ]]
[[ "$(gpu_package_name omni-accelerant-nvidia cuda)" == omni-accelerant-nvidia ]]
fixture_refuses 'An unknown GPU package name unexpectedly succeeded' gpu_package_name omni-accelerant unsupported >/dev/null

# host_runtime <hub> <provider> <bundle>: prepares in a subshell, so one case's exports and results stay out of the next.
host_runtime() { ( export ANTFRASTRUCTURE_DIR="$1" KATAGLYPHIS_ORT_PROVIDER="$2"; prepare_gpu_host_runtime "$3" ); }
host_runtime_quiet() { host_runtime "$@" 2>/dev/null; }
host_runtime "$work/old" cpu "$work/cpu"
fixture_refuses 'A missing requested GPU provider unexpectedly passed' host_runtime_quiet "$work/old" cuda "$work/cpu"
printf 'void fixture(void) {}\n' > "$work/fixture.c"
"${CC:-cc}" -shared -fPIC -Wl,-soname,libcuda.so.1 "$work/fixture.c" -o "$work/libcuda.so.1"
"${CC:-cc}" -shared -fPIC -Wl,--no-as-needed "$work/fixture.c" "$work/libcuda.so.1" \
  -o "$work/gpu/lib/libonnxruntime_providers_cuda.so"
: > "$work/gpu/lib/libonnxruntime_providers_shared.so"
fixture_refuses 'A GPU bundle unexpectedly passed with an old hub' host_runtime_quiet "$work/old" cuda "$work/gpu"
: > "$work/gpu/lib/libonnxruntime_providers_migraphx.so"
fixture_refuses 'A bundle containing both GPU providers unexpectedly passed' host_runtime_quiet "$ANTFRASTRUCTURE_DIR" '' "$work/gpu"
rm "$work/gpu/lib/libonnxruntime_providers_migraphx.so"

fixture_gpu_launcher "$work/gpu/omni_accelerant"
: > "$work/gpu/omni_accelerant.bin"
verify_gpu_host_launchers "$work/gpu"
sed -i 's/export LD_LIBRARY_PATH=/export BROKEN_PATH=/' "$work/gpu/omni_accelerant"
fixture_refuses 'A broken GPU launcher unexpectedly passed' verify_gpu_host_launchers "$work/gpu" 2>/dev/null
sed -i 's/export BROKEN_PATH=/export LD_LIBRARY_PATH=/' "$work/gpu/omni_accelerant"
printf '\177ELF' > "$work/gpu/unwrapped"
chmod +x "$work/gpu/unwrapped"
fixture_refuses_logged "$work/unwrapped.log" 'GPU bundle executable is not an external-runtime launcher' \
  'An unwrapped GPU bundle executable unexpectedly passed' verify_gpu_host_launchers "$work/gpu"
rm "$work/gpu/unwrapped"

hub="${ORT_TEST_SHARED_HUB:-$root/third_party/ANTfrastructure}"
helper="$hub/linux/scripts/06-packaging/ort-runtime-bundle.sh"
if [[ -f "$helper" ]] && grep -q '^ort_host_runtime_needed()' "$helper"; then
  ( export ANTFRASTRUCTURE_DIR="$hub" KATAGLYPHIS_ORT_PROVIDER=cuda
    prepare_gpu_host_runtime "$work/gpu"
    [[ "$GPU_RUNTIME_KIND" == cuda ]]
    [[ " ${GPU_RUNTIME_SONAMES[*]} " == *' libcuda.so.1 '* ]]
  )
  cp "$work/libcuda.so.1" "$work/gpu/lib/libcuda.so.1"
  fixture_refuses 'A bundled host GPU runtime unexpectedly passed' host_runtime_quiet "$hub" cuda "$work/gpu"
  rm "$work/gpu/lib/libcuda.so.1"
  fixture_refuses_logged "$work/flatpak.log" 'GPU packages require the host runtime and do not support Flatpak' \
    'GPU packaging unexpectedly accepted Flatpak' \
    env ANTFRASTRUCTURE_DIR="$hub" KATAGLYPHIS_ORT_PROVIDER=cuda APP_PACKAGING_BUNDLE_DIR="$work/gpu" \
    bash "$root/scripts/linux/package-linux.sh" --arch x64 --app-name omni-accelerant --formats flatpak
  mkdir -p "$work/actual/lib"
  cat > "$work/launcher.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
int main(void) { const char *path = getenv("LD_LIBRARY_PATH"); puts(path ? path : ""); return 0; }
EOF
  "${CC:-cc}" "$work/launcher.c" -o "$work/actual/omni_accelerant"
  bash "$hub/linux/scripts/06-packaging/bundle-loader.sh" --beside --external-library-path \
    "$work/actual" "$work/actual/lib" omni_accelerant >/dev/null
  verify_gpu_host_launchers "$work/actual"
  [[ "$(LD_LIBRARY_PATH=/sdk "$work/actual/omni_accelerant")" == "$work/actual/lib:/sdk" ]]
  [[ "$(KATAGLYPHIS_BUNDLED_GLIBC=1 LD_LIBRARY_PATH=/sdk "$work/actual/omni_accelerant")" == "$work/actual/lib:/sdk" ]]
  if [[ -n "${ORT_TEST_REAL_PROVIDER:-}" ]]; then
    real_dir="$(fixture_real_provider_dir)" || exit $?
    mkdir -p "$work/real/lib"
    cp "$real_dir/libonnxruntime_providers_shared.so" "$real_dir/libonnxruntime_providers_${ORT_TEST_REAL_PROVIDER}.so" "$work/real/lib/"
    ( export ANTFRASTRUCTURE_DIR="$hub" KATAGLYPHIS_ORT_PROVIDER="$ORT_TEST_REAL_PROVIDER"
      prepare_gpu_host_runtime "$work/real"
      [[ "$GPU_RUNTIME_KIND" == "$ORT_TEST_REAL_PROVIDER" && ${#GPU_RUNTIME_SONAMES[@]} -gt 0 ]]
    )
  fi
else
  echo 'Info: pinned hub lacks GPU host-runtime helpers; the missing-helper refusal was tested.'
fi
echo 'GPU host-runtime selection checks passed'
