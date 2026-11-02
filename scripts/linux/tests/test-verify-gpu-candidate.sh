#!/usr/bin/env bash
# Finished-package fixture: match all three payloads and reject independent mutations.
set -euo pipefail
# shellcheck source=scripts/linux/tests/fixture-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/fixture-common.sh"
repo="$(fixture_root)"
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
for name in fixture_detector.onnx fixture_detector.LICENSE fixture_detector.NOTICE; do
  printf 'fixture %s\n' "$name" > "$work/bundle/data/resources/models/$name"
  printf '%s  %s  https://example.invalid/%s\n' \
    "$(sha256sum "$work/bundle/data/resources/models/$name" | cut -d ' ' -f1)" "$name" "$name" \
    >> "$fixture_repo/third_party/OxidANT/resources/models/models.lock"
done
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
if ORT_LIB_LOCATION="$work/bundle/lib" ORT_CHAIN_WHEEL_DIR="$work/wheels" \
  bash "$repo/scripts/linux/check-gpu-image-runtime.sh" cuda >/dev/null 2>&1; then
  echo 'changed image provider passed' >&2; exit 1
fi
cc -shared -fPIC -g "$work/fixture.c" -o "$work/bundle/lib/libonnxruntime_providers_cuda.so"
variant=omni-accelerant-nvidia
mkdir -p "$work/tar/$variant-bundle" "$work/deb/DEBIAN" "$work/deb/opt/$variant" "$work/appimage/usr/lib/$variant"
cp -a "$work/bundle/." "$work/tar/$variant-bundle/"
cp -a "$work/bundle/." "$work/deb/opt/$variant/"
cp -a "$work/bundle/." "$work/appimage/usr/lib/$variant/"
cat > "$work/deb/DEBIAN/control" <<'CONTROL'
Package: omni-accelerant-nvidia
Version: 1.0
Architecture: amd64
Maintainer: Fixture <fixture@example.invalid>
Description: Package verifier fixture
CONTROL
tar -C "$work/tar" -czf "$work/out/$variant-linux-x64.tar.gz" "$variant-bundle"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_amd64.deb" >/dev/null
fixture_stub "$work/out/$variant-1.0-x86_64.AppImage" <<'IMAGE'
[[ "$#" -ge 1 && "$#" -le 2 && "$1" == --appimage-extract ]]
mkdir squashfs-root
cp -a "$FIXTURE_APPDIR/." squashfs-root/
IMAGE
chmod +x "$work/out/$variant-1.0-x86_64.AppImage"
export FIXTURE_APPDIR="$work/appimage" ORT_CHAIN_WHEEL_DIR="$work/wheels"
cd "$work"
bash "$verifier" nvidia x64 >/dev/null
sed -i 's/^Architecture: amd64$/Architecture: arm64/' "$work/deb/DEBIAN/control"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_amd64.deb" >/dev/null
fixture_refuses_quiet 'DEB with wrong embedded architecture passed' bash "$verifier" nvidia x64
sed -i 's/^Architecture: arm64$/Architecture: amd64/; s/^Package: omni-accelerant-nvidia$/Package: omni-accelerant-amd/' "$work/deb/DEBIAN/control"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_amd64.deb" >/dev/null
fixture_refuses_quiet 'DEB with wrong embedded package identity passed' bash "$verifier" nvidia x64
sed -i 's/^Package: omni-accelerant-amd$/Package: omni-accelerant-nvidia/' "$work/deb/DEBIAN/control"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_amd64.deb" >/dev/null
rm "$work/tar/$variant-bundle/lib/libonnxruntime.so"
tar -C "$work/tar" -czf "$work/out/$variant-linux-x64.tar.gz" "$variant-bundle"
fixture_refuses_quiet 'missing tar ORT dynamic-load alias passed' bash "$verifier" nvidia x64
ln -s libonnxruntime.so.1 "$work/tar/$variant-bundle/lib/libonnxruntime.so"
tar -C "$work/tar" -czf "$work/out/$variant-linux-x64.tar.gz" "$variant-bundle"
rm "$work/deb/opt/$variant/lib/libonnxruntime.so"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_amd64.deb" >/dev/null
fixture_refuses_quiet 'missing DEB ORT dynamic-load alias passed' bash "$verifier" nvidia x64
ln -s libonnxruntime.so.1 "$work/deb/opt/$variant/lib/libonnxruntime.so"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_amd64.deb" >/dev/null
rm "$work/appimage/usr/lib/$variant/lib/libonnxruntime.so"
fixture_refuses_quiet 'missing AppImage ORT dynamic-load alias passed' bash "$verifier" nvidia x64
ln -s libonnxruntime.so.1 "$work/appimage/usr/lib/$variant/lib/libonnxruntime.so"
printf x >> "$work/tar/$variant-bundle/lib/libonnxruntime_providers_cuda.so"
tar -C "$work/tar" -czf "$work/out/$variant-linux-x64.tar.gz" "$variant-bundle"
fixture_refuses_quiet 'changed tar provider passed' bash "$verifier" nvidia x64
cp "$work/bundle/lib/libonnxruntime_providers_cuda.so" "$work/tar/$variant-bundle/lib/"
tar -C "$work/tar" -czf "$work/out/$variant-linux-x64.tar.gz" "$variant-bundle"
mv "$work/tar/$variant-bundle/licenses/onnxruntime" "$work/tar-notices"
ln -s "$work/bundle/licenses/onnxruntime" "$work/tar/$variant-bundle/licenses/onnxruntime"
tar -C "$work/tar" -czf "$work/out/$variant-linux-x64.tar.gz" "$variant-bundle"
fixture_refuses_quiet 'tar notice directory escaping package passed' bash "$verifier" nvidia x64
rm "$work/tar/$variant-bundle/licenses/onnxruntime"
mv "$work/tar-notices" "$work/tar/$variant-bundle/licenses/onnxruntime"
tar -C "$work/tar" -czf "$work/out/$variant-linux-x64.tar.gz" "$variant-bundle"
printf changed > "$work/deb/opt/$variant/licenses/onnxruntime/LICENSE"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_amd64.deb" >/dev/null
fixture_refuses_quiet 'changed DEB notice passed' bash "$verifier" nvidia x64
cp "$work/bundle/licenses/onnxruntime/LICENSE" "$work/deb/opt/$variant/licenses/onnxruntime/"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_amd64.deb" >/dev/null
printf bad > "$work/tar/$variant-bundle/data/resources/models/fixture_detector.onnx"
tar -C "$work/tar" -czf "$work/out/$variant-linux-x64.tar.gz" "$variant-bundle"
fixture_refuses_quiet 'changed tar model passed' bash "$verifier" nvidia x64
cp "$work/bundle/data/resources/models/fixture_detector.onnx" "$work/tar/$variant-bundle/data/resources/models/"
tar -C "$work/tar" -czf "$work/out/$variant-linux-x64.tar.gz" "$variant-bundle"
mv "$work/tar/$variant-bundle/data/resources/models" "$work/model-outside"
ln -s "$work/model-outside" "$work/tar/$variant-bundle/data/resources/models"
tar -C "$work/tar" -czf "$work/out/$variant-linux-x64.tar.gz" "$variant-bundle"
fixture_refuses_quiet 'tar model directory escaping package passed' bash "$verifier" nvidia x64
rm "$work/tar/$variant-bundle/data/resources/models"
mv "$work/model-outside" "$work/tar/$variant-bundle/data/resources/models"
tar -C "$work/tar" -czf "$work/out/$variant-linux-x64.tar.gz" "$variant-bundle"
rm "$work/deb/opt/$variant/data/resources/models/fixture_detector.NOTICE"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_amd64.deb" >/dev/null
fixture_refuses_quiet 'missing DEB model notice passed' bash "$verifier" nvidia x64
cp "$work/bundle/data/resources/models/fixture_detector.NOTICE" "$work/deb/opt/$variant/data/resources/models/"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_amd64.deb" >/dev/null
printf bad > "$work/appimage/usr/lib/$variant/data/resources/models/fixture_detector.LICENSE"
fixture_refuses_quiet 'changed AppImage model license passed' bash "$verifier" nvidia x64
cp "$work/bundle/data/resources/models/fixture_detector.LICENSE" "$work/appimage/usr/lib/$variant/data/resources/models/"
printf x >> "$work/appimage/usr/lib/$variant/lib/libonnxruntime_providers_cuda.so"
fixture_refuses_quiet 'changed AppImage provider passed' bash "$verifier" nvidia x64
fixture_refuses_quiet 'unsupported AMD arm64 passed' bash "$verifier" amd arm64
echo 'GPU candidate package verification fixtures passed'
