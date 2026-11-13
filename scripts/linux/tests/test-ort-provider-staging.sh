#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/linux/tests/fixture-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/fixture-common.sh"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/project/linux" "$work/project/cargokit/cmake" "$work/ort" "$work/third_party/OxidANT/crates/inference" \
  "$work/amdgpu/lib" "$work/no-module/lib"
# The CMake asks the pinned hub for the plugin module's name and place, as a build does.
ln -s "${ANTFRASTRUCTURE_DIR:-$root/third_party/ANTfrastructure}" "$work/third_party/ANTfrastructure"
cp "$root/rust_builder/linux/CMakeLists.txt" "$work/project/linux/CMakeLists.txt"
cp "$root/rust_builder/linux/ort-device.cmake" "$root/rust_builder/linux/oxidant-ort-devices.cmake" "$work/project/linux/"
printf '[package.metadata.kataglyphis]\n# Provider capabilities.\nort-devices = ["cuda", "migraphx", "directml"]\n' > "$work/third_party/OxidANT/crates/inference/Cargo.toml"
cat > "$work/project/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.10)
project(staging_test LANGUAGES CXX)
add_subdirectory(linux)
file(WRITE "${CMAKE_BINARY_DIR}/bundled.txt" "${oxidant_bundled_libraries}")
EOF
cat > "$work/project/cargokit/cmake/cargokit.cmake" <<'EOF'
function(apply_cargokit)
endfunction()
EOF
printf '/opt/onnxruntime/onnxruntime/core/\n' > "$work/ort/libonnxruntime.so"
printf 'shared\n' > "$work/ort/libonnxruntime_providers_shared.so"
printf 'cuda\n' > "$work/ort/libonnxruntime_providers_cuda.so"
printf 'plugin\n' > "$work/amdgpu/lib/libmigraphx-ep.so"
cat > "$work/x64-toolchain.cmake" <<'EOF'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
EOF

configure() {
  local -a toolchain=()
  # MIGraphX fixtures model x64 even when the test runs on ARM64.
  if [[ "$1" == migraphx ]]; then
    toolchain=(-D "CMAKE_TOOLCHAIN_FILE=$work/x64-toolchain.cmake")
  fi
  # Set in every case: the rocm image exports its own root, which would stand in for a missing fixture module.
  ORT_LIB_LOCATION="$work/ort" ORT_AMDGPU_EP_ROOT="${AMD_ROOT:-$work/amdgpu}" KATAGLYPHIS_ORT_PROVIDER="$1" \
    cmake -S "$work/project" -B "$work/build-$1" "${toolchain[@]}" > "$work/$1.log" 2>&1
}
configure cpu
test ! -e "$work/build-cpu/linux/libonnxruntime_providers_shared.so"
fixture_refuses 'CPU bundle unexpectedly contains a GPU provider' grep -q 'libonnxruntime_providers_' "$work/build-cpu/bundled.txt"
configure cuda
for name in libonnxruntime_providers_shared.so libonnxruntime_providers_cuda.so; do
  cmp "$work/ort/$name" "$work/build-cuda/linux/$name"
  grep -Fq "$work/build-cuda/linux/$name" "$work/build-cuda/bundled.txt"
done
fixture_refuses 'CUDA bundle unexpectedly contains the AMD plugin module' grep -q 'libmigraphx-ep' "$work/build-cuda/bundled.txt"
# An AMD build carries the image's plugin module and no in-tree provider, although the fixture runtime has two.
configure migraphx
cmp "$work/amdgpu/lib/libmigraphx-ep.so" "$work/build-migraphx/linux/libmigraphx-ep.so"
grep -Fq "$work/build-migraphx/linux/libmigraphx-ep.so" "$work/build-migraphx/bundled.txt"
fixture_refuses 'AMD bundle unexpectedly contains an in-tree provider' grep -q 'libonnxruntime_providers_' "$work/build-migraphx/bundled.txt"
rm -rf "$work/build-migraphx"
AMD_ROOT="$work/no-module" fixture_refuses 'An image without the plugin module unexpectedly configured' configure migraphx
grep -Fq 'provider is missing' "$work/migraphx.log"
rm "$work/third_party/ANTfrastructure"
fixture_refuses 'A hub without the plugin helper unexpectedly configured' configure migraphx
grep -Fq "plugin module's name and place" "$work/migraphx.log"
ln -s "${ANTFRASTRUCTURE_DIR:-$root/third_party/ANTfrastructure}" "$work/third_party/ANTfrastructure"
for provider in invalid off 0; do
  fixture_refuses "Unknown provider $provider unexpectedly succeeded" configure "$provider"
done
cat > "$work/check-device.cmake" <<'EOF'
include("${DEVICE_MODULE}")
omni_linux_ort_device(device "${OXIDANT_DIR}")
EOF
device_args=(-D "DEVICE_MODULE=$work/project/linux/ort-device.cmake" -D "OXIDANT_DIR=$work/third_party/OxidANT" -D CMAKE_SYSTEM_PROCESSOR=aarch64 -P "$work/check-device.cmake")
KATAGLYPHIS_ORT_PROVIDER=cpu cmake "${device_args[@]}" > "$work/arm-cpu.log" 2>&1
KATAGLYPHIS_ORT_PROVIDER=cuda cmake "${device_args[@]}" > "$work/arm-cuda.log" 2>&1
fixture_refuses_logged "$work/arm-amd.log" 'Linux AMD GPU builds are supported on x64 only' \
  'Linux ARM64 MIGraphX unexpectedly succeeded' env KATAGLYPHIS_ORT_PROVIDER=migraphx cmake "${device_args[@]}"
mkdir -p "$work/gpu/lib" "$work/gpu/include" "$work/wrong"
touch "$work/gpu/lib/libonnxruntime.so" "$work/gpu/include/onnxruntime_cxx_api.h"
cat > "$work/check-root.cmake" <<'EOF'
include("${DEVICE_MODULE}")
omni_linux_ort_root("${PROVIDER}")
file(WRITE "${RESULT}" "${ONNXRUNTIME_ROOT}")
EOF
root_args=(-D "DEVICE_MODULE=$work/project/linux/ort-device.cmake" -D PROVIDER=cuda -D "RESULT=$work/root.txt" -P "$work/check-root.cmake")
env -u ORT_LIB_LOCATION cmake -D "DEVICE_MODULE=$work/project/linux/ort-device.cmake" -D PROVIDER=cpu \
  -D "ONNXRUNTIME_ROOT=$work/wrong" -D "RESULT=$work/cpu-root.txt" -P "$work/check-root.cmake" > "$work/cpu-root.log" 2>&1
test "$(cat "$work/cpu-root.txt")" = "$work/wrong"
ORT_LIB_LOCATION="$work/gpu/lib" cmake "${root_args[@]}" > "$work/root.log" 2>&1
test "$(cat "$work/root.txt")" = "$work/gpu"
fixture_refuses_logged "$work/root-conflict.log" 'ONNXRUNTIME_ROOT conflicts' \
  'A conflicting AccelerANTgine ONNX Runtime root unexpectedly succeeded' \
  env ORT_LIB_LOCATION="$work/gpu/lib" cmake -D "ONNXRUNTIME_ROOT=$work/wrong" "${root_args[@]}"
fixture_refuses_logged "$work/root-missing.log" 'ORT_LIB_LOCATION must name' \
  'An incomplete GPU runtime unexpectedly succeeded' env ORT_LIB_LOCATION="$work/wrong" cmake "${root_args[@]}"
printf '[package]\nname = "kataglyphis_inference"\n' > "$work/third_party/OxidANT/crates/inference/Cargo.toml"
rm -rf "$work/build-migraphx"
fixture_refuses 'MIGraphX without an OxidANT capability marker unexpectedly succeeded' configure migraphx
grep -Fq 'OxidANT pin advertising AMD provider selection' "$work/migraphx.log"
printf '[package.metadata.kataglyphis]\nort-devices = ["cuda"]\n[unrelated]\nort-devices = ["migraphx"]\n' > "$work/third_party/OxidANT/crates/inference/Cargo.toml"
fixture_refuses 'MIGraphX in an unrelated metadata section unexpectedly succeeded' configure migraphx
printf '[package.metadata.kataglyphis]\n# Provider capabilities.\nort-devices = ["cuda", "migraphx", "directml"]\n' > "$work/third_party/OxidANT/crates/inference/Cargo.toml"
if [[ -n "${ORT_TEST_REAL_OXIDANT:-}" ]]; then
  KATAGLYPHIS_ORT_PROVIDER=migraphx cmake -D "DEVICE_MODULE=$work/project/linux/ort-device.cmake" \
    -D "OXIDANT_DIR=$ORT_TEST_REAL_OXIDANT" -D CMAKE_SYSTEM_PROCESSOR=x86_64 \
    -P "$work/check-device.cmake" > "$work/real-oxidant.log" 2>&1 || {
      cat "$work/real-oxidant.log" >&2
      exit 1
    }
fi
rm "$work/ort/libonnxruntime_providers_cuda.so"
rm -rf "$work/build-cuda"
fixture_refuses 'Missing provider unexpectedly succeeded' configure cuda
if [[ -n "${ORT_TEST_REAL_PROVIDER:-}" ]]; then
  real_dir="$(fixture_real_provider_dir)" || exit $?
  ORT_LIB_LOCATION="$real_dir" KATAGLYPHIS_ORT_PROVIDER="$ORT_TEST_REAL_PROVIDER" \
    cmake -S "$work/project" -B "$work/build-real" > "$work/real.log" 2>&1
  case "$ORT_TEST_REAL_PROVIDER" in
    cuda) real_modules=("$real_dir/libonnxruntime_providers_shared.so" "$real_dir/libonnxruntime_providers_cuda.so") ;;
    migraphx) real_modules=("${ORT_AMDGPU_EP_ROOT:?the real plugin root is required}/lib/libmigraphx-ep.so") ;;
  esac
  for module in "${real_modules[@]}"; do
    cmp "$module" "$work/build-real/linux/${module##*/}"
    grep -Fq "$work/build-real/linux/${module##*/}" "$work/build-real/bundled.txt"
  done
  ORT_LIB_LOCATION="$real_dir" cmake "${root_args[@]}" > "$work/real-root.log" 2>&1 || {
    cat "$work/real-root.log" >&2
    exit 1
  }
  test "$(cat "$work/root.txt")" = "$(dirname "$(readlink -f "$real_dir")")"
fi
echo 'ONNX Runtime provider staging checks passed'
