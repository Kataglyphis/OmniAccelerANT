#!/usr/bin/env bash
# Exercise all supported package routes and reject missing or misleading profile evidence.
set -euo pipefail
# shellcheck source=scripts/linux/tests/fixture-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/fixture-common.sh"
shopt -s nullglob
root="$(fixture_root)"
hub=${ANTFRASTRUCTURE_DIR:-"$root/third_party/ANTfrastructure"}
oxidant=${OXIDANT_DIR:-"$root/third_party/OxidANT"}
fixture_workdir
repo="$work/repo"
mkdir -p "$repo/scripts/linux/lib" "$repo/scripts/windows" "$repo/third_party/ANTfrastructure/shared/python" \
  "$repo/third_party/ANTfrastructure/linux/scripts/lib" "$repo/third_party/OxidANT/resources/models" \
  "$repo/third_party/OxidANT/crates/inference/tests/fixtures" "$work/bin" "$work/packages" "$work/runner"
cp "$root/scripts/linux/profile-gpu-candidate.sh" "$root/scripts/linux/profile-gpu-packages.sh" "$repo/scripts/linux/"
cp "$root/scripts/linux/preflight-profile-packages.py" "$repo/scripts/linux/"
cp "$root/scripts/linux/lib/verify-onnx-loader-trace.sh" "$root/scripts/linux/lib/gpu-script-common.sh" "$repo/scripts/linux/lib/"
cp "$root/scripts/windows/verify_detector_model.py" "$repo/scripts/windows/"
cp "$hub/shared/python/verify_ort_profile.py" "$hub/shared/python/compare_detector_parity.py" "$repo/third_party/ANTfrastructure/shared/python/"
cp "$hub/linux/scripts/lib/fetch-data-lock.py" "$hub/linux/scripts/lib/gpu-profile-env.sh" \
  "$hub/linux/scripts/lib/log-bootstrap.sh" "$repo/third_party/ANTfrastructure/linux/scripts/lib/"
cp "$oxidant/crates/inference/tests/fixtures/two_cats.jpg" "$repo/third_party/OxidANT/crates/inference/tests/fixtures/"
fixture_xvfb_stub "$work/bin"
REAL_PYTHON=$(command -v python3)
export REAL_PYTHON
cat > "$work/bin/python3" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == -I && ${2:-} == */preflight-profile-packages.py ]]; then
  shift 2
  operation=$1
  shift
  if [[ ${GPU_FAKE_PREFLIGHT_FAIL:-} == "$operation" ]]; then exit 44; fi
  if [[ $operation == create ]]; then
    while [[ $# -gt 0 ]]; do
      if [[ $1 == --plan ]]; then : > "$2"; break; fi
      shift 2
    done
  fi
  exit 0
fi
exec "$REAL_PYTHON" "$@"
EOF
chmod +x "$work/bin/python3"
export PATH="$work/bin:$PATH" RUNNER_TEMP="$work/runner" SEEN="$work/seen" LD_LIBRARY_PATH=/host-sdk-fixture
export KATAGLYPHIS_ONNX_MODEL=/wrong ORT_DYLIB_PATH=/wrong ORT_LIB_LOCATION=/wrong ONNX_ROOT=/wrong
export KATAGLYPHIS_ONNX_BACKEND=tract KATAGLYPHIS_ORT_DEVICE=wrong KATAGLYPHIS_DIRECTML_DEVICE_ID=99
export MIGRAPHX_SKIP_BENCHMARKING=poison ORT_MIGRAPHX_MODEL_CACHE_PATH=/wrong MIGRAPHX_UNKNOWN=poison
check="$repo/scripts/linux/profile-gpu-packages.sh"
for tuple in nvidia:x64:cuda nvidia:arm64:cuda amd:x64:migraphx; do
  IFS=: read -r vendor arch device <<< "$tuple"
  case "$arch" in x64) deb=amd64; machine=x86_64 ;; arm64) deb=arm64; machine=aarch64 ;; esac
  variant="omni-accelerant-$vendor"
  for format in tar deb image; do
    bundle="$work/$format bundle"
    mkdir -p "$bundle/data/resources/models" "$bundle/lib"
    fixture_write_models "$bundle/data/resources/models"
    : > "$bundle/lib/libonnxruntime.so"
    printf '%s' "$format" > "$bundle/format"
    cat > "$bundle/omni_accelerant" <<'EOF'
#!/usr/bin/env python3
import json, os, pathlib, sys
for name in ('LD_PRELOAD', 'LD_AUDIT', 'KATAGLYPHIS_DIRECTML_DEVICE_ID', 'KATAGLYPHIS_ONNX_MODEL',
             'ORT_DYLIB_PATH', 'ORT_LIB_LOCATION', 'ONNX_ROOT', 'MIGRAPHX_SKIP_BENCHMARKING',
             'ORT_MIGRAPHX_MODEL_CACHE_PATH', 'MIGRAPHX_UNKNOWN'):
    assert name not in os.environ, name
cpu = os.environ.get('KATAGLYPHIS_ORT_DEVICE') == 'cpu'
if cpu:
    assert os.environ.get('KATAGLYPHIS_ONNX_BACKEND') == 'ort' and 'LD_LIBRARY_PATH' not in os.environ
else:
    assert os.environ.get('KATAGLYPHIS_ONNX_BACKEND') == 'ort'
    assert os.environ.get('KATAGLYPHIS_ORT_DEVICE') == os.environ['EXPECTED_DEVICE']
    assert os.environ.get('LD_LIBRARY_PATH') == '/host-sdk-fixture'
assert len(sys.argv) == 6 and sys.argv[1] == '--onnx-profile-image'
kind = (pathlib.Path(__file__).parent / 'format').read_text()
scratch = list(pathlib.Path(os.environ['RUNNER_TEMP']).glob('omni-gpu-packages.*'))
assert len(scratch) == 1
if kind in ('deb', 'image'): assert not (scratch[0] / 'tar').exists()
if kind == 'image': assert not (scratch[0] / 'deb').exists()
runtime = pathlib.Path(__file__).parent / 'lib/libonnxruntime.so'
if os.environ.get('HOST_RUNTIME_FORMAT') == kind: runtime = pathlib.Path('/host/libonnxruntime.so')
if os.environ.get('MALFORMED_LOADER_FORMAT') == kind: runtime = pathlib.Path('libonnxruntime.so')
if os.environ.get('MISSING_LOADER_FORMAT') != kind:
    with open(os.environ['LD_DEBUG_OUTPUT'] + '.fixture', 'w', encoding='utf-8') as out:
        out.write('calling init: ' + str(runtime) + '\n')
        if os.environ.get('MIXED_RUNTIME_FORMAT') == kind: out.write('calling init: /host/libonnxruntime.so\n')
with open(os.environ['SEEN'], 'a', encoding='utf-8') as out: out.write(kind + (' cpu\n' if cpu else ' gpu\n'))
provider = 'CPUExecutionProvider' if cpu else os.environ['EXPECTED_PROVIDER']
if not cpu and os.environ.get('CPU_FORMAT') == kind: provider = 'CPUExecutionProvider'
second_provider = 'CPUExecutionProvider' if not cpu and os.environ.get('CPU_SECOND_FORMAT') == kind else provider
score = 0.2 if not cpu and os.environ.get('BAD_OUTPUT_FORMAT') == kind else 0.9
def result(path, value):
    with open(path, 'w', encoding='utf-8') as out:
        json.dump({'schema_version':1,'width':480,'height':659,'detections':[
            {'class':15,'score':value,'box':[0,250,450,640]},
            {'class':15,'score':0.8,'box':[0,0,250,200]}]}, out)
result(sys.argv[3], score)
result(sys.argv[4], 0.2 if not cpu and os.environ.get('BAD_REPEAT_FORMAT') == kind else score)
with open(sys.argv[5] + '_0.json', 'w', encoding='utf-8') as out:
    json.dump([{'cat':'Session','name':'model_run','ph':'X','pid':42,'ts':0,'dur':10},
      {'cat':'Node','ph':'X','pid':42,'ts':1,'dur':1,'args':{'provider':provider,'op_name':'Conv'}},
      {'cat':'Session','name':'model_run','ph':'X','pid':42,'ts':20,'dur':10},
      {'cat':'Node','ph':'X','pid':42,'ts':21,'dur':1,'args':{'provider':second_provider,'op_name':'Conv'}}], out)
EOF
    chmod +x "$bundle/omni_accelerant"
  done
  : > "$repo/third_party/OxidANT/resources/models/models.lock"
  fixture_lock_models "$work/tar bundle/data/resources/models" "$repo/third_party/OxidANT/resources/models/models.lock"
  mkdir -p "$work/tar-root" "$work/deb-root/DEBIAN" "$work/deb-root/opt"
  cp -a "$work/tar bundle" "$work/tar-root/$variant-bundle"
  cp -a "$work/deb bundle" "$work/deb-root/opt/$variant"
  cat > "$work/deb-root/DEBIAN/control" <<EOF
Package: $variant
Version: 1
Architecture: $deb
Maintainer: Test <test@example.invalid>
Description: GPU package routing fixture
EOF
  tar -czf "$work/packages/$variant-linux-$arch.tar.gz" -C "$work/tar-root" "$variant-bundle"
  dpkg-deb --root-owner-group --build "$work/deb-root" "$work/packages/${variant}_1_${deb}.deb" >/dev/null
  export FAKE_IMAGE_SOURCE="$work/image bundle" FAKE_VARIANT="$variant"
  fixture_stub "$work/packages/$variant-1-$machine.AppImage" <<'EOF'
if [[ ${1:-} = --appimage-extract ]]; then
  mkdir -p "squashfs-root/usr/lib/$FAKE_VARIANT"
  cp -a "$FAKE_IMAGE_SOURCE/." "squashfs-root/usr/lib/$FAKE_VARIANT/"
  exit 0
fi
[[ ${APPIMAGE_EXTRACT_AND_RUN:-} = 1 ]]
rm -rf -- "$TMPDIR/appimage_extracted_0123456789abcdef0123456789abcdef"
mkdir -p "$TMPDIR/appimage_extracted_0123456789abcdef0123456789abcdef/usr/lib/$FAKE_VARIANT"
cp -a "$FAKE_IMAGE_SOURCE/." "$TMPDIR/appimage_extracted_0123456789abcdef0123456789abcdef/usr/lib/$FAKE_VARIANT/"
exec "$TMPDIR/appimage_extracted_0123456789abcdef0123456789abcdef/usr/lib/$FAKE_VARIANT/omni_accelerant" "$@"
EOF
  chmod 0644 "$work/packages/$variant-1-$machine.AppImage"
  case "$device" in cuda) EXPECTED_PROVIDER=CUDAExecutionProvider ;; migraphx) EXPECTED_PROVIDER=MIGraphXExecutionProvider ;; esac
  export EXPECTED_PROVIDER EXPECTED_DEVICE="$device"
  : > "$SEEN"
  evidence="$work/evidence-$vendor-$arch"
  PROFILE_EVIDENCE_DIR="$evidence" bash "$check" "$work/packages" "$vendor" "$arch" "$device" >/dev/null
  scratch=("$work/runner"/omni-gpu-packages.*)
  [[ ${#scratch[@]} -eq 0 ]] || { echo 'Successful profile retained scratch' >&2; exit 1; }
  for format in tar deb appimage; do
    for mode in cpu gpu; do
      [[ -f "$evidence/$format/$mode-profile_0.json" && -f "$evidence/$format/$mode-1.json" && -f "$evidence/$format/$mode-2.json" && -f "$evidence/$format/$mode-loader.fixture" ]] || {
        echo "Missing durable $format $mode evidence" >&2; exit 1;
      }
    done
  done
  fixture_refuses_quiet 'Preflight failure was accepted' env GPU_FAKE_PREFLIGHT_FAIL=create PROFILE_EVIDENCE_DIR="$work/failed-evidence-$vendor-$arch" \
    bash "$check" "$work/packages" "$vendor" "$arch" "$device"
  scratch=("$work/runner"/omni-gpu-packages.*)
  [[ ${#scratch[@]} -eq 0 && -f "$evidence/tar/cpu-1.json" ]] || {
    echo 'Failure cleanup lost evidence or retained scratch' >&2; exit 1;
  }
  printf 'tar cpu\ntar gpu\ndeb cpu\ndeb gpu\nimage cpu\nimage gpu\n' > "$work/expected"
  cmp "$work/expected" "$SEEN"
  rm "$work/tar-root/$variant-bundle/lib/libonnxruntime.so"
  ln -s /etc/hosts "$work/tar-root/$variant-bundle/lib/libonnxruntime.so"
  tar -czf "$work/packages/$variant-linux-$arch.tar.gz" -C "$work/tar-root" "$variant-bundle"
  fixture_refuses_quiet 'Escaping runtime symlink accepted' bash "$check" "$work/packages" "$vendor" "$arch" "$device"
  rm "$work/tar-root/$variant-bundle/lib/libonnxruntime.so"
  : > "$work/tar-root/$variant-bundle/lib/libonnxruntime.so"
  tar -czf "$work/packages/$variant-linux-$arch.tar.gz" -C "$work/tar-root" "$variant-bundle"
  rm "$work/image bundle/lib/libonnxruntime.so"
  ln -s /etc/hosts "$work/image bundle/lib/libonnxruntime.so"
  fixture_refuses_quiet 'Escaping AppImage runtime symlink accepted' bash "$check" "$work/packages" "$vendor" "$arch" "$device"
  rm "$work/image bundle/lib/libonnxruntime.so"
  : > "$work/image bundle/lib/libonnxruntime.so"
  for format in tar deb image; do
    for fault in CPU_FORMAT CPU_SECOND_FORMAT BAD_OUTPUT_FORMAT BAD_REPEAT_FORMAT HOST_RUNTIME_FORMAT MISSING_LOADER_FORMAT MALFORMED_LOADER_FORMAT MIXED_RUNTIME_FORMAT; do
      fixture_refuses_quiet "$format accepted $fault" env "$fault=$format" bash "$check" "$work/packages" "$vendor" "$arch" "$device"
      scratch=("$work/runner"/omni-gpu-packages.*)
      [[ ${#scratch[@]} -eq 0 ]] || { echo 'Failed profile retained scratch' >&2; exit 1; }
    done
  done
  cp "$work/packages/$variant-1-$machine.AppImage" "$work/packages/$variant-2-$machine.AppImage"
  fixture_refuses_quiet 'Duplicate AppImages accepted' bash "$check" "$work/packages" "$vendor" "$arch" "$device"
  rm -rf -- "$work/tar bundle" "$work/deb bundle" "$work/image bundle" "$work/tar-root" "$work/deb-root" "$work/packages/"*
done
fixture_refuses_quiet 'Unsupported Linux ARM ROCm accepted' bash "$check" "$work/packages" amd arm64 migraphx
echo 'PASS: all supported package formats require CPU/GPU parity and two GPU profile runs'
