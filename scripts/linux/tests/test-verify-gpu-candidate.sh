#!/usr/bin/env bash
# Finished-package fixture: match all three payloads and reject independent mutations.
set -euo pipefail
# shellcheck source=scripts/linux/tests/fixture-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/fixture-common.sh"
repo="$(fixture_root)"
# The verifier refuses a foreign AppImage, so the fixture matches the host it runs on.
case "$(uname -m)" in
  x86_64) host_arch=x64 host_machine=x86_64 host_deb=amd64 other_deb=arm64 ;;
  aarch64) host_arch=arm64 host_machine=aarch64 host_deb=arm64 other_deb=amd64 ;;
  *) echo "No GPU candidates on $(uname -m)" >&2; exit 1 ;;
esac
fixture_workdir
fixture_repo="$work/repo"
verifier="$fixture_repo/scripts/linux/verify-gpu-candidate.sh"
mkdir -p "$work/out" "$work/wheels" "$work/bundle/lib" "$work/bundle/licenses/onnxruntime" \
  "$work/bundle/data/resources/models" "$fixture_repo/scripts/linux" "$fixture_repo/scripts/windows" \
  "$fixture_repo/third_party/OxidANT/resources/models"
mkdir -p "$fixture_repo/scripts/linux/lib"
cp "$repo/scripts/linux/lib/gpu-script-common.sh" "$fixture_repo/scripts/linux/lib/"
cp "$repo/scripts/linux/verify-gpu-candidate.sh" "$verifier"
cp "$repo/scripts/windows/verify_detector_model.py" "$fixture_repo/scripts/windows/"
export ANTFRASTRUCTURE_DIR="${ANTFRASTRUCTURE_DIR:-$repo/third_party/ANTfrastructure}"
fixture_write_models "$work/bundle/data/resources/models"
fixture_lock_models "$work/bundle/data/resources/models" "$fixture_repo/third_party/OxidANT/resources/models/models.lock"
printf 'int fixture(void) { return 17; }\n' > "$work/fixture.c"
for name in libonnxruntime.so.1 libonnxruntime_providers_shared.so libonnxruntime_providers_cuda.so; do
  cc -shared -fPIC -g "$work/fixture.c" -o "$work/bundle/lib/$name"
done
printf 'license\n' > "$work/bundle/licenses/onnxruntime/LICENSE"
printf 'notices\n' > "$work/bundle/licenses/onnxruntime/ThirdPartyNotices.txt"
python3 - "$work" <<'PY'
from pathlib import Path
import sys, zipfile
root = Path(sys.argv[1])
with zipfile.ZipFile(root / 'wheels/onnxruntime_fixture-1.whl', 'w') as wheel:
    for path in (root / 'bundle/lib').iterdir():
        wheel.write(path, 'onnxruntime/capi/' + path.name)
    for path in (root / 'bundle/licenses/onnxruntime').iterdir():
        wheel.write(path, 'onnxruntime/' + path.name)
PY
ln -s libonnxruntime.so.1 "$work/bundle/lib/libonnxruntime.so"
mkdir -p "$work/bundle/include"
touch "$work/bundle/include/onnxruntime_cxx_api.h"
ORT_LIB_LOCATION="$work/bundle/lib" ORT_CHAIN_WHEEL_DIR="$work/wheels" \
  bash "$repo/scripts/linux/check-gpu-image-runtime.sh" cuda >/dev/null
printf x >> "$work/bundle/lib/libonnxruntime_providers_cuda.so"
fixture_refuses_quiet 'changed image provider passed' env ORT_LIB_LOCATION="$work/bundle/lib" ORT_CHAIN_WHEEL_DIR="$work/wheels" \
  bash "$repo/scripts/linux/check-gpu-image-runtime.sh" cuda
cc -shared -fPIC -g "$work/fixture.c" -o "$work/bundle/lib/libonnxruntime_providers_cuda.so"
variant=omni-accelerant-nvidia
mkdir -p "$work/tar/$variant-bundle" "$work/deb/DEBIAN" "$work/deb/opt/$variant" "$work/appimage/usr/lib/$variant"
cp -a "$work/bundle/." "$work/tar/$variant-bundle/"
cp -a "$work/bundle/." "$work/deb/opt/$variant/"
cp -a "$work/bundle/." "$work/appimage/usr/lib/$variant/"
cat > "$work/deb/DEBIAN/control" <<CONTROL
Package: omni-accelerant-nvidia
Version: 1.0
Architecture: ${host_deb}
Maintainer: Fixture <fixture@example.invalid>
Description: Package verifier fixture
CONTROL
tar -C "$work/tar" -czf "$work/out/$variant-linux-${host_arch}.tar.gz" "$variant-bundle"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_${host_deb}.deb" >/dev/null
fixture_stub "$work/out/$variant-1.0-${host_machine}.AppImage" <<'IMAGE'
[[ "$#" -ge 1 && "$#" -le 2 && "$1" == --appimage-extract ]]
mkdir squashfs-root
cp -a "$FIXTURE_APPDIR/." squashfs-root/
IMAGE
chmod +x "$work/out/$variant-1.0-${host_machine}.AppImage"
export FIXTURE_APPDIR="$work/appimage" ORT_CHAIN_WHEEL_DIR="$work/wheels"
cd "$work"
bash "$verifier" nvidia "$host_arch" >/dev/null
sed -i "s/^Architecture: ${host_deb}\$/Architecture: ${other_deb}/" "$work/deb/DEBIAN/control"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_${host_deb}.deb" >/dev/null
fixture_refuses_quiet 'DEB with wrong embedded architecture passed' bash "$verifier" nvidia "$host_arch"
sed -i "s/^Architecture: ${other_deb}\$/Architecture: ${host_deb}/; s/^Package: omni-accelerant-nvidia\$/Package: omni-accelerant-amd/" "$work/deb/DEBIAN/control"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_${host_deb}.deb" >/dev/null
fixture_refuses_quiet 'DEB with wrong embedded package identity passed' bash "$verifier" nvidia "$host_arch"
sed -i 's/^Package: omni-accelerant-amd$/Package: omni-accelerant-nvidia/' "$work/deb/DEBIAN/control"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_${host_deb}.deb" >/dev/null
rm "$work/tar/$variant-bundle/lib/libonnxruntime.so"
tar -C "$work/tar" -czf "$work/out/$variant-linux-${host_arch}.tar.gz" "$variant-bundle"
fixture_refuses_quiet 'missing tar ORT dynamic-load alias passed' bash "$verifier" nvidia "$host_arch"
ln -s libonnxruntime.so.1 "$work/tar/$variant-bundle/lib/libonnxruntime.so"
tar -C "$work/tar" -czf "$work/out/$variant-linux-${host_arch}.tar.gz" "$variant-bundle"
rm "$work/deb/opt/$variant/lib/libonnxruntime.so"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_${host_deb}.deb" >/dev/null
fixture_refuses_quiet 'missing DEB ORT dynamic-load alias passed' bash "$verifier" nvidia "$host_arch"
ln -s libonnxruntime.so.1 "$work/deb/opt/$variant/lib/libonnxruntime.so"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_${host_deb}.deb" >/dev/null
rm "$work/appimage/usr/lib/$variant/lib/libonnxruntime.so"
fixture_refuses_quiet 'missing AppImage ORT dynamic-load alias passed' bash "$verifier" nvidia "$host_arch"
ln -s libonnxruntime.so.1 "$work/appimage/usr/lib/$variant/lib/libonnxruntime.so"
printf x >> "$work/tar/$variant-bundle/lib/libonnxruntime_providers_cuda.so"
tar -C "$work/tar" -czf "$work/out/$variant-linux-${host_arch}.tar.gz" "$variant-bundle"
fixture_refuses_quiet 'changed tar provider passed' bash "$verifier" nvidia "$host_arch"
cp "$work/bundle/lib/libonnxruntime_providers_cuda.so" "$work/tar/$variant-bundle/lib/"
tar -C "$work/tar" -czf "$work/out/$variant-linux-${host_arch}.tar.gz" "$variant-bundle"
mv "$work/tar/$variant-bundle/licenses/onnxruntime" "$work/tar-notices"
ln -s "$work/bundle/licenses/onnxruntime" "$work/tar/$variant-bundle/licenses/onnxruntime"
tar -C "$work/tar" -czf "$work/out/$variant-linux-${host_arch}.tar.gz" "$variant-bundle"
fixture_refuses_quiet 'tar notice directory escaping package passed' bash "$verifier" nvidia "$host_arch"
rm "$work/tar/$variant-bundle/licenses/onnxruntime"
mv "$work/tar-notices" "$work/tar/$variant-bundle/licenses/onnxruntime"
tar -C "$work/tar" -czf "$work/out/$variant-linux-${host_arch}.tar.gz" "$variant-bundle"
printf changed > "$work/deb/opt/$variant/licenses/onnxruntime/LICENSE"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_${host_deb}.deb" >/dev/null
fixture_refuses_quiet 'changed DEB notice passed' bash "$verifier" nvidia "$host_arch"
cp "$work/bundle/licenses/onnxruntime/LICENSE" "$work/deb/opt/$variant/licenses/onnxruntime/"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_${host_deb}.deb" >/dev/null
printf bad > "$work/tar/$variant-bundle/data/resources/models/fixture_detector.onnx"
tar -C "$work/tar" -czf "$work/out/$variant-linux-${host_arch}.tar.gz" "$variant-bundle"
fixture_refuses_quiet 'changed tar model passed' bash "$verifier" nvidia "$host_arch"
cp "$work/bundle/data/resources/models/fixture_detector.onnx" "$work/tar/$variant-bundle/data/resources/models/"
tar -C "$work/tar" -czf "$work/out/$variant-linux-${host_arch}.tar.gz" "$variant-bundle"
mv "$work/tar/$variant-bundle/data/resources/models" "$work/model-outside"
ln -s "$work/model-outside" "$work/tar/$variant-bundle/data/resources/models"
tar -C "$work/tar" -czf "$work/out/$variant-linux-${host_arch}.tar.gz" "$variant-bundle"
fixture_refuses_quiet 'tar model directory escaping package passed' bash "$verifier" nvidia "$host_arch"
rm "$work/tar/$variant-bundle/data/resources/models"
mv "$work/model-outside" "$work/tar/$variant-bundle/data/resources/models"
tar -C "$work/tar" -czf "$work/out/$variant-linux-${host_arch}.tar.gz" "$variant-bundle"
rm "$work/deb/opt/$variant/data/resources/models/fixture_detector.NOTICE"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_${host_deb}.deb" >/dev/null
fixture_refuses_quiet 'missing DEB model notice passed' bash "$verifier" nvidia "$host_arch"
cp "$work/bundle/data/resources/models/fixture_detector.NOTICE" "$work/deb/opt/$variant/data/resources/models/"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_${host_deb}.deb" >/dev/null
printf bad > "$work/appimage/usr/lib/$variant/data/resources/models/fixture_detector.LICENSE"
fixture_refuses_quiet 'changed AppImage model license passed' bash "$verifier" nvidia "$host_arch"
cp "$work/bundle/data/resources/models/fixture_detector.LICENSE" "$work/appimage/usr/lib/$variant/data/resources/models/"
printf x >> "$work/appimage/usr/lib/$variant/lib/libonnxruntime_providers_cuda.so"
fixture_refuses_quiet 'changed AppImage provider passed' bash "$verifier" nvidia "$host_arch"
fixture_refuses_quiet 'unsupported AMD arm64 passed' bash "$verifier" amd arm64
# The image strips its CPU core: that twin of the wheel's library is right for AMD and wrong for NVIDIA, whose prefix holds the wheel's bytes.
cp "$work/bundle/lib/libonnxruntime_providers_cuda.so" "$work/appimage/usr/lib/$variant/lib/"
bash "$verifier" nvidia "$host_arch" >/dev/null
cp "$work/bundle/lib/libonnxruntime.so.1" "$work/stripped-core"
strip --strip-all "$work/stripped-core"
cp "$work/stripped-core" "$work/tar/$variant-bundle/lib/libonnxruntime.so.1"
tar -C "$work/tar" -czf "$work/out/$variant-linux-${host_arch}.tar.gz" "$variant-bundle"
fixture_refuses_logged "$work/stripped.log" 'expected one wheel' 'stripped NVIDIA core passed' bash "$verifier" nvidia "$host_arch"

# The AMD leg runs on every host: it asks the hub's AppImage verifier nothing, and the fixture image root stands in for the rocm image.
amd=omni-accelerant-amd
image_ep="$work/image-ep"
mkdir -p "$fixture_repo/third_party/OxidANT/scripts/linux/lib" "$image_ep/lib" "$image_ep/licenses/onnxruntime-ep-amdgpu" \
  "$image_ep/licenses/fmt" "$work/amd-bundle/lib" "$work/amd-bundle/licenses" "$work/cpu-prefix/lib" "$work/cpu-prefix/include"
cp "$repo/third_party/OxidANT/scripts/linux/lib/"{ort-runtime-bundle.sh,antfrastructure.sh,renovate-git-mode.sh,gpu-check-common.sh} \
  "$fixture_repo/third_party/OxidANT/scripts/linux/lib/"
printf 'int plugin(void) { return 23; }\n' > "$work/plugin.c"
cc -shared -fPIC "$work/plugin.c" -o "$image_ep/lib/libmigraphx-ep.so"
printf 'plugin license\n' > "$image_ep/licenses/onnxruntime-ep-amdgpu/LICENSE"
printf 'seed license\n' > "$image_ep/licenses/fmt/LICENSE"
printf 'onnxruntime-ep-amdgpu fixture\nsource-sha256 fixture\n' > "$image_ep/provenance.txt"
export ORT_AMDGPU_EP_ROOT="$image_ep"
cp "$work/stripped-core" "$work/cpu-prefix/lib/libonnxruntime.so.1"
touch "$work/cpu-prefix/include/onnxruntime_cxx_api.h"
ORT_LIB_LOCATION="$work/cpu-prefix/lib" bash "$repo/scripts/linux/check-gpu-image-runtime.sh" migraphx >/dev/null
mkdir -p "$work/no-plugin/lib"
fixture_refuses_logged "$work/no-plugin.log" 'This image has no MIGraphX plugin module' 'an image without the plugin module passed' \
  env ORT_LIB_LOCATION="$work/cpu-prefix/lib" ORT_AMDGPU_EP_ROOT="$work/no-plugin" bash "$repo/scripts/linux/check-gpu-image-runtime.sh" migraphx
mv "$image_ep/provenance.txt" "$work/provenance.keep"
fixture_refuses_logged "$work/no-texts.log" 'no licence texts or provenance' 'an image without the plugin provenance passed' \
  env ORT_LIB_LOCATION="$work/cpu-prefix/lib" bash "$repo/scripts/linux/check-gpu-image-runtime.sh" migraphx
mv "$work/provenance.keep" "$image_ep/provenance.txt"
# The CPU prefix is no CUDA runtime, and a stripped core is not the GPU wheel's bytes.
fixture_refuses_quiet 'the CPU prefix passed as a CUDA runtime' env ORT_LIB_LOCATION="$work/cpu-prefix/lib" bash "$repo/scripts/linux/check-gpu-image-runtime.sh" cuda

cp "$work/stripped-core" "$work/amd-bundle/lib/libonnxruntime.so.1"
cp "$work/stripped-core" "$work/amd-bundle/lib/libonnxruntime.so"
cp "$image_ep/lib/libmigraphx-ep.so" "$work/amd-bundle/lib/"
cp -a "$work/bundle/licenses/onnxruntime" "$work/amd-bundle/licenses/"
cp -a "$work/bundle/data" "$work/amd-bundle/"
mkdir -p "$work/amd-bundle/licenses/onnxruntime-ep-amdgpu"
cp -R "$image_ep/licenses/." "$work/amd-bundle/licenses/onnxruntime-ep-amdgpu/"
cp "$image_ep/provenance.txt" "$work/amd-bundle/licenses/onnxruntime-ep-amdgpu/"
mkdir -p "$work/amd-tar" "$work/amd-deb/DEBIAN" "$work/amd-deb/opt" "$work/amd-appimage/usr/lib"
amd_tar="$work/amd-tar/$amd-bundle" amd_deb="$work/amd-deb/opt/$amd" amd_image="$work/amd-appimage/usr/lib/$amd"
# amd_pack: rebuilds the three AMD candidates from their trees; the stub AppImage copies its tree when asked to extract.
amd_pack() {
  tar -C "$work/amd-tar" -czf "$work/out/$amd-linux-x64.tar.gz" "$amd-bundle"
  dpkg-deb --root-owner-group --build "$work/amd-deb" "$work/out/${amd}_1.0_amd64.deb" >/dev/null
}
# amd_reset: every tree is the clean bundle again, so each case below plants one fault only.
amd_reset() {
  local tree
  for tree in "$amd_tar" "$amd_deb" "$amd_image"; do
    rm -rf "$tree"
    cp -a "$work/amd-bundle" "$tree"
  done
  amd_pack
}
cat > "$work/amd-deb/DEBIAN/control" <<CONTROL
Package: $amd
Version: 1.0
Architecture: amd64
Maintainer: Fixture <fixture@example.invalid>
Description: Package verifier fixture
CONTROL
fixture_stub "$work/out/$amd-1.0-x86_64.AppImage" <<'IMAGE'
[[ "$#" -ge 1 && "$#" -le 2 && "$1" == --appimage-extract ]]
mkdir squashfs-root
cp -a "$FIXTURE_AMD_APPDIR/." squashfs-root/
IMAGE
export FIXTURE_AMD_APPDIR="$work/amd-appimage"
amd_reset
bash "$verifier" amd x64 >/dev/null
# As the lane calls it, with no hub named: OxidANT's text helper must still read this repo's hub, never a nested one.
ln -s "$ANTFRASTRUCTURE_DIR" "$fixture_repo/third_party/ANTfrastructure"
env -u ANTFRASTRUCTURE_DIR -u KATAGLYPHIS_REPO_ROOT bash "$verifier" amd x64 >/dev/null
# amd_refuses <needle> <message>: the verifier must fail and say needle; the trees are clean again afterwards.
amd_refuses() {
  amd_pack
  fixture_refuses_logged "$work/amd.log" "$1" "$2" bash "$verifier" amd x64
  amd_reset
}
printf x >> "$amd_tar/lib/libmigraphx-ep.so"
amd_refuses "is not the image's" 'a patched tar plugin module passed'
rm "$amd_deb/lib/libmigraphx-ep.so"
amd_refuses 'missing or linked plugin MIGraphX EP' 'a DEB without the plugin module passed'
printf x >> "$amd_image/lib/libmigraphx-ep.so"
amd_refuses "is not the image's" 'a patched AppImage plugin module passed'
printf changed > "$amd_image/licenses/onnxruntime-ep-amdgpu/fmt/LICENSE"
amd_refuses "MIGraphX plugin texts are not the image's" 'a changed AppImage plugin text passed'
rm "$amd_tar/licenses/onnxruntime-ep-amdgpu/provenance.txt"
amd_refuses "MIGraphX plugin texts are not the image's" 'a tar without the plugin provenance passed'
cp "$work/bundle/lib/libonnxruntime_providers_shared.so" "$amd_deb/lib/"
amd_refuses 'An AMD package carries an in-tree ONNX Runtime provider' 'an AMD DEB with an in-tree provider passed'
cp "$image_ep/lib/libmigraphx-ep.so" "$amd_tar/lib/libamdhip64.so.7"
amd_refuses 'host GPU runtime library was bundled' 'an AMD tar with a bundled ROCm library passed'
printf x >> "$amd_deb/lib/libonnxruntime.so.1"
amd_refuses 'expected one wheel' 'a changed AMD core passed'
# Set but pointing elsewhere, as a host's own root would: the package must still be compared with the image named here.
mkdir -p "$work/other-ep/lib"
printf 'other\n' > "$work/other-ep/lib/libmigraphx-ep.so"
fixture_refuses_logged "$work/amd.log" "is not the image's" 'a package passed against another plugin root' \
  env ORT_AMDGPU_EP_ROOT="$work/other-ep" bash "$verifier" amd x64
echo 'GPU candidate package verification fixtures passed'
