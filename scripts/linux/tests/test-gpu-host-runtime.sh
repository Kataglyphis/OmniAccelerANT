#!/usr/bin/env bash
# Exercises the app's host-runtime integration; actual GPU inference needs hardware.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$root/scripts/linux/lib/antfrastructure.sh"
source "$root/scripts/linux/lib/bundle-runtime.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/cpu/lib" "$work/gpu/lib" "$work/old"
[[ "$(gpu_package_name omni-accelerant cuda)" == omni-accelerant-nvidia ]]
[[ "$(gpu_package_name omni-accelerant migraphx)" == omni-accelerant-amd ]]
[[ "$(gpu_package_name omni-accelerant-nvidia cuda)" == omni-accelerant-nvidia ]]
if gpu_package_name omni-accelerant unsupported >/dev/null; then
  echo 'An unknown GPU package name unexpectedly succeeded' >&2
  exit 1
fi

( export ANTFRASTRUCTURE_DIR="$work/old" KATAGLYPHIS_ORT_PROVIDER=cpu; prepare_gpu_host_runtime "$work/cpu" )
if ( export ANTFRASTRUCTURE_DIR="$work/old" KATAGLYPHIS_ORT_PROVIDER=cuda; prepare_gpu_host_runtime "$work/cpu" ) 2>/dev/null; then
  echo 'A missing requested GPU provider unexpectedly passed' >&2
  exit 1
fi
printf 'void fixture(void) {}\n' > "$work/fixture.c"
"${CC:-cc}" -shared -fPIC -Wl,-soname,libcuda.so.1 "$work/fixture.c" -o "$work/libcuda.so.1"
"${CC:-cc}" -shared -fPIC -Wl,--no-as-needed "$work/fixture.c" "$work/libcuda.so.1" \
  -o "$work/gpu/lib/libonnxruntime_providers_cuda.so"
: > "$work/gpu/lib/libonnxruntime_providers_shared.so"
if ( export ANTFRASTRUCTURE_DIR="$work/old" KATAGLYPHIS_ORT_PROVIDER=cuda; prepare_gpu_host_runtime "$work/gpu" ) 2>/dev/null; then
  echo 'A GPU bundle unexpectedly passed with an old hub' >&2
  exit 1
fi
: > "$work/gpu/lib/libonnxruntime_providers_migraphx.so"
if ( export KATAGLYPHIS_ORT_PROVIDER=; prepare_gpu_host_runtime "$work/gpu" ) 2>/dev/null; then
  echo 'A bundle containing both GPU providers unexpectedly passed' >&2
  exit 1
fi
rm "$work/gpu/lib/libonnxruntime_providers_migraphx.so"

cat > "$work/gpu/omni_accelerant" <<'EOF'
#!/bin/bash
external_library_path=""
export LD_LIBRARY_PATH="$here/lib${external_library_path}"
exec "$here/loader" --library-path "$here/lib/glibc:$here/lib${external_library_path}" "$@"
EOF
chmod +x "$work/gpu/omni_accelerant"
: > "$work/gpu/omni_accelerant.bin"
verify_gpu_host_launchers "$work/gpu"
sed -i 's/export LD_LIBRARY_PATH=/export BROKEN_PATH=/' "$work/gpu/omni_accelerant"
if verify_gpu_host_launchers "$work/gpu" 2>/dev/null; then
  echo 'A broken GPU launcher unexpectedly passed' >&2
  exit 1
fi
sed -i 's/export BROKEN_PATH=/export LD_LIBRARY_PATH=/' "$work/gpu/omni_accelerant"
printf '\177ELF' > "$work/gpu/unwrapped"
chmod +x "$work/gpu/unwrapped"
if verify_gpu_host_launchers "$work/gpu" 2>"$work/unwrapped.log"; then
  echo 'An unwrapped GPU bundle executable unexpectedly passed' >&2
  exit 1
fi
grep -Fq 'GPU bundle executable is not an external-runtime launcher' "$work/unwrapped.log"
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
  if ( export ANTFRASTRUCTURE_DIR="$hub" KATAGLYPHIS_ORT_PROVIDER=cuda; prepare_gpu_host_runtime "$work/gpu" ) 2>/dev/null; then
    echo 'A bundled host GPU runtime unexpectedly passed' >&2
    exit 1
  fi
  rm "$work/gpu/lib/libcuda.so.1"
  if ANTFRASTRUCTURE_DIR="$hub" KATAGLYPHIS_ORT_PROVIDER=cuda APP_PACKAGING_BUNDLE_DIR="$work/gpu" \
    bash "$root/scripts/linux/package-linux.sh" --arch x64 --app-name omni-accelerant --formats flatpak \
    > "$work/flatpak.log" 2>&1; then
    echo 'GPU packaging unexpectedly accepted Flatpak' >&2
    exit 1
  fi
  grep -Fq 'GPU packages require the host runtime and do not support Flatpak' "$work/flatpak.log"
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
    case "$ORT_TEST_REAL_PROVIDER" in cuda|migraphx) ;; *) echo 'Invalid real provider' >&2; exit 2 ;; esac
    real_dir="${ORT_TEST_REAL_DIR:?ORT_TEST_REAL_DIR is required}"
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
