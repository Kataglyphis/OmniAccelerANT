#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/linux/tests/fixture-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/fixture-common.sh"
root="$(fixture_root)"
check="$root/scripts/linux/check-packaged-onnx-runtime.sh"
fixture_xvfb_workdir
mkdir -p "$work/bundle/lib" "$work/runner"
fixture_stub "$work/bundle/omni_accelerant" <<'STUB'
[[ $# == 1 && "$1" == --onnx-check && ${KATAGLYPHIS_ORT_DEVICE:-} == cpu && ${KATAGLYPHIS_ONNX_BACKEND:-} == ort ]]
[[ -z ${LD_LIBRARY_PATH+x} && -z ${ORT_DYLIB_PATH+x} && -z ${ONNX_ROOT+x} && -z ${ORT_AMDGPU_EP_ROOT+x} ]]
runtime="${BASH_SOURCE[0]%/*}/lib/libonnxruntime.so"
[[ ${BAD_RUNTIME:-} != outside ]] || runtime=/host/libonnxruntime.so
[[ ${BAD_RUNTIME:-} != malformed ]] || runtime=libonnxruntime.so
if [[ ${BAD_RUNTIME:-} != missing ]]; then printf 'calling init: %s\n' "$runtime" > "$LD_DEBUG_OUTPUT.fixture"; fi
if [[ ${BAD_RUNTIME:-} == mixed ]]; then printf 'calling init: /host/libonnxruntime.so\n' >> "$LD_DEBUG_OUTPUT.fixture"; fi
STUB
fixture_stub "$work/appimage" <<'STUB'
[[ $# == 1 && "$1" == --onnx-check && ${APPIMAGE_EXTRACT_AND_RUN:-} == 1 ]]
runtime="$TMPDIR/appimage_extracted_0123456789abcdef0123456789abcdef/usr/lib/omni-accelerant-nvidia/lib/libonnxruntime.so"
[[ ${BAD_RUNTIME:-} != outside ]] || runtime=/host/libonnxruntime.so
[[ ${BAD_RUNTIME:-} != malformed ]] || runtime="$TMPDIR/appimage_extracted_invalid/usr/lib/omni-accelerant-nvidia/lib/libonnxruntime.so"
if [[ ${BAD_RUNTIME:-} != missing ]]; then printf 'calling init: %s\n' "$runtime" > "$LD_DEBUG_OUTPUT.fixture"; fi
if [[ ${BAD_RUNTIME:-} == mixed ]]; then printf 'calling init: /host/libonnxruntime.so\n' >> "$LD_DEBUG_OUTPUT.fixture"; fi
STUB
chmod +x "$work/bundle/omni_accelerant" "$work/appimage"
touch "$work/bundle/lib/libonnxruntime.so"
export PATH="$work/bin:$PATH" RUNNER_TEMP="$work/runner"
export LD_LIBRARY_PATH=/host-sdk ORT_DYLIB_PATH=/host/libonnxruntime.so ONNX_ROOT=/host ORT_AMDGPU_EP_ROOT=/host/plugin-root
bash "$check" bundle "$work/bundle"
bash "$check" appimage "$work/appimage" omni-accelerant-nvidia
for fault in outside malformed missing mixed; do
  if BAD_RUNTIME=$fault bash "$check" bundle "$work/bundle" >/dev/null 2>&1; then
    echo "Bundle accepted $fault runtime trace" >&2; exit 1
  fi
  if BAD_RUNTIME=$fault bash "$check" appimage "$work/appimage" omni-accelerant-nvidia >/dev/null 2>&1; then
    echo "AppImage accepted $fault runtime trace" >&2; exit 1
  fi
done
rm "$work/bundle/lib/libonnxruntime.so"
ln -s /etc/hosts "$work/bundle/lib/libonnxruntime.so"
fixture_refuses_quiet 'Escaping runtime symlink accepted' bash "$check" bundle "$work/bundle"
rm "$work/bundle/lib/libonnxruntime.so"
rmdir "$work/bundle/lib"
mkdir "$work/external"
touch "$work/external/libonnxruntime.so"
ln -s "$work/external" "$work/bundle/lib"
fixture_refuses_quiet 'Escaping runtime directory accepted' bash "$check" bundle "$work/bundle"

# An AMD package: after the CPU run, the named device must be refused through the package's own plugin module and auto must run.
# shellcheck source=scripts/linux/lib/gpu-script-common.sh
source "$root/scripts/linux/lib/gpu-script-common.sh"
# shellcheck source=/dev/null
source "${ANTFRASTRUCTURE_DIR:-$root/third_party/ANTfrastructure}/linux/scripts/06-packaging/ort-runtime-bundle.sh"
[[ "$GPU_AMD_PLUGIN_MODULE" == "$ORT_AMDGPU_EP_MODULE" ]] || { echo "The module name here is not the hub's" >&2; exit 1; }
mkdir -p "$work/amd/lib"
touch "$work/amd/lib/libonnxruntime.so" "$work/amd/lib/$GPU_AMD_PLUGIN_MODULE"
amd_stub() {
  fixture_stub "$1" <<STUB
lib="$2"
package_kind=$3
STUB
  cat >> "$1" <<'STUB'
[[ $# == 1 && "$1" == --onnx-check && ${KATAGLYPHIS_ONNX_BACKEND:-} == ort ]]
[[ -z ${LD_LIBRARY_PATH+x} && -z ${ORT_DYLIB_PATH+x} && -z ${ONNX_ROOT+x} && -z ${ORT_AMDGPU_EP_ROOT+x} ]]
[[ "$package_kind" == bundle ]] || lib="$TMPDIR/$lib"
printf '%s\n' "${KATAGLYPHIS_ORT_DEVICE:-}" >> "$DEVICES_SEEN"
case "${KATAGLYPHIS_ORT_DEVICE:-}" in
  migraphx)
    module="$lib/libmigraphx-ep.so"
    case "${BAD_PLUGIN:-}" in
      ran) exit 0 ;;
      silent) exit 1 ;;
      outside) module=/host/plugin-root/lib/libmigraphx-ep.so ;;
      probe) echo 'ONNX model inference failed: ProviderUnavailable: MIGraphX cannot run: a copy to the AMD GPU took over 30 seconds' >&2; exit 1 ;;
      absent) echo 'ONNX model inference failed: ProviderUnavailable: MIGraphX has no module libmigraphx-ep.so: tried nothing' >&2; exit 1 ;;
    esac
    echo "ONNX model inference failed: detect_persons_rgba failed: ProviderUnavailable: MIGraphX failed to register: $module: libmigraphx_c.so.3: cannot open shared object file" >&2
    exit 1
    ;;
  auto) [[ ${BAD_AUTO:-} != fails ]] ;;
  cpu) ;;
  *) exit 9 ;;
esac
printf 'calling init: %s\n' "$lib/libonnxruntime.so" > "$LD_DEBUG_OUTPUT.fixture"
STUB
}
amd_stub "$work/amd/omni_accelerant" "$work/amd/lib" bundle
amd_stub "$work/amd.AppImage" appimage_extracted_0123456789abcdef0123456789abcdef/usr/lib/omni-accelerant-amd/lib appimage
export DEVICES_SEEN="$work/devices"
bash "$check" bundle "$work/amd" > "$work/amd-bundle.log"
[[ "$(tr '\n' ' ' < "$DEVICES_SEEN")" == 'cpu migraphx auto ' ]] || { echo 'The AMD bundle was not asked for cpu, migraphx and auto' >&2; exit 1; }
grep -Fq 'refused by name through the packaged plugin module' "$work/amd-bundle.log"
: > "$DEVICES_SEEN"
bash "$check" appimage "$work/amd.AppImage" omni-accelerant-amd >/dev/null
[[ "$(tr '\n' ' ' < "$DEVICES_SEEN")" == 'cpu migraphx auto ' ]] || { echo 'The AMD AppImage was not asked for cpu, migraphx and auto' >&2; exit 1; }
for fault in ran silent outside probe absent; do
  fixture_refuses_quiet "AMD bundle accepted a $fault plugin refusal" env BAD_PLUGIN=$fault bash "$check" bundle "$work/amd"
  fixture_refuses_quiet "AMD AppImage accepted a $fault plugin refusal" env BAD_PLUGIN=$fault bash "$check" appimage "$work/amd.AppImage" omni-accelerant-amd
done
fixture_refuses_quiet 'AMD bundle accepted a failing auto run' env BAD_AUTO=fails bash "$check" bundle "$work/amd"
fixture_refuses_quiet 'AMD AppImage accepted a failing auto run' env BAD_AUTO=fails bash "$check" appimage "$work/amd.AppImage" omni-accelerant-amd
# A package without the module is asked for the CPU only: its launcher has no named device to refuse.
: > "$DEVICES_SEEN"
rm "$work/amd/lib/$GPU_AMD_PLUGIN_MODULE"
bash "$check" bundle "$work/amd" >/dev/null
[[ "$(tr '\n' ' ' < "$DEVICES_SEEN")" == 'cpu ' ]] || { echo 'A bundle without the plugin module was asked for a GPU device' >&2; exit 1; }
echo 'Packaged ONNX Runtime loader checks passed'
