#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
check="$root/scripts/linux/check-packaged-onnx-runtime.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/bundle/lib" "$work/runner"
cat > "$work/bin/xvfb-run" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == -a ]] && shift
exec "$@"
STUB
cat > "$work/bundle/omni_accelerant" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 1 && "$1" == --onnx-check && ${KATAGLYPHIS_ORT_DEVICE:-} == cpu && ${KATAGLYPHIS_ONNX_BACKEND:-} == ort ]]
[[ -z ${LD_LIBRARY_PATH+x} && -z ${ORT_DYLIB_PATH+x} && -z ${ONNX_ROOT+x} ]]
runtime="${BASH_SOURCE[0]%/*}/lib/libonnxruntime.so"
[[ ${BAD_RUNTIME:-} != outside ]] || runtime=/host/libonnxruntime.so
[[ ${BAD_RUNTIME:-} != malformed ]] || runtime=libonnxruntime.so
if [[ ${BAD_RUNTIME:-} != missing ]]; then printf 'calling init: %s\n' "$runtime" > "$LD_DEBUG_OUTPUT.fixture"; fi
if [[ ${BAD_RUNTIME:-} == mixed ]]; then printf 'calling init: /host/libonnxruntime.so\n' >> "$LD_DEBUG_OUTPUT.fixture"; fi
STUB
cat > "$work/appimage" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 1 && "$1" == --onnx-check && ${APPIMAGE_EXTRACT_AND_RUN:-} == 1 ]]
runtime="$TMPDIR/appimage_extracted_0123456789abcdef0123456789abcdef/usr/lib/omni-accelerant-nvidia/lib/libonnxruntime.so"
[[ ${BAD_RUNTIME:-} != outside ]] || runtime=/host/libonnxruntime.so
[[ ${BAD_RUNTIME:-} != malformed ]] || runtime="$TMPDIR/appimage_extracted_invalid/usr/lib/omni-accelerant-nvidia/lib/libonnxruntime.so"
if [[ ${BAD_RUNTIME:-} != missing ]]; then printf 'calling init: %s\n' "$runtime" > "$LD_DEBUG_OUTPUT.fixture"; fi
if [[ ${BAD_RUNTIME:-} == mixed ]]; then printf 'calling init: /host/libonnxruntime.so\n' >> "$LD_DEBUG_OUTPUT.fixture"; fi
STUB
chmod +x "$work/bin/xvfb-run" "$work/bundle/omni_accelerant" "$work/appimage"
touch "$work/bundle/lib/libonnxruntime.so"
export PATH="$work/bin:$PATH" RUNNER_TEMP="$work/runner"
export LD_LIBRARY_PATH=/host-sdk ORT_DYLIB_PATH=/host/libonnxruntime.so ONNX_ROOT=/host
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
if bash "$check" bundle "$work/bundle" >/dev/null 2>&1; then echo 'Escaping runtime symlink accepted' >&2; exit 1; fi
rm "$work/bundle/lib/libonnxruntime.so"
rmdir "$work/bundle/lib"
mkdir "$work/external"
touch "$work/external/libonnxruntime.so"
ln -s "$work/external" "$work/bundle/lib"
if bash "$check" bundle "$work/bundle" >/dev/null 2>&1; then echo 'Escaping runtime directory accepted' >&2; exit 1; fi
echo 'Packaged ONNX Runtime loader checks passed'
