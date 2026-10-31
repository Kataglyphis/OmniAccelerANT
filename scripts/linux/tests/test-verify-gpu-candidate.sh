#!/usr/bin/env bash
# Finished-package fixture: match all three payloads and reject independent mutations.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
verifier="$repo/scripts/linux/verify-gpu-candidate.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/out" "$work/wheels" "$work/bundle/lib" "$work/bundle/licenses/onnxruntime"
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
cat > "$work/out/$variant-1.0-x86_64.AppImage" <<'IMAGE'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" == 1 && "$1" == --appimage-extract ]]
mkdir squashfs-root
cp -a "$FIXTURE_APPDIR/." squashfs-root/
IMAGE
chmod +x "$work/out/$variant-1.0-x86_64.AppImage"
export FIXTURE_APPDIR="$work/appimage" ORT_CHAIN_WHEEL_DIR="$work/wheels"
cd "$work"
bash "$verifier" nvidia x64 >/dev/null
printf x >> "$work/tar/$variant-bundle/lib/libonnxruntime_providers_cuda.so"
tar -C "$work/tar" -czf "$work/out/$variant-linux-x64.tar.gz" "$variant-bundle"
if bash "$verifier" nvidia x64 >/dev/null 2>&1; then echo 'changed tar provider passed' >&2; exit 1; fi
cp "$work/bundle/lib/libonnxruntime_providers_cuda.so" "$work/tar/$variant-bundle/lib/"
tar -C "$work/tar" -czf "$work/out/$variant-linux-x64.tar.gz" "$variant-bundle"
mv "$work/tar/$variant-bundle/licenses/onnxruntime" "$work/tar-notices"
ln -s "$work/bundle/licenses/onnxruntime" "$work/tar/$variant-bundle/licenses/onnxruntime"
tar -C "$work/tar" -czf "$work/out/$variant-linux-x64.tar.gz" "$variant-bundle"
if bash "$verifier" nvidia x64 >/dev/null 2>&1; then echo 'tar notice directory escaping package passed' >&2; exit 1; fi
rm "$work/tar/$variant-bundle/licenses/onnxruntime"
mv "$work/tar-notices" "$work/tar/$variant-bundle/licenses/onnxruntime"
tar -C "$work/tar" -czf "$work/out/$variant-linux-x64.tar.gz" "$variant-bundle"
printf changed > "$work/deb/opt/$variant/licenses/onnxruntime/LICENSE"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_amd64.deb" >/dev/null
if bash "$verifier" nvidia x64 >/dev/null 2>&1; then echo 'changed DEB notice passed' >&2; exit 1; fi
cp "$work/bundle/licenses/onnxruntime/LICENSE" "$work/deb/opt/$variant/licenses/onnxruntime/"
dpkg-deb --build "$work/deb" "$work/out/${variant}_1.0_amd64.deb" >/dev/null
printf x >> "$work/appimage/usr/lib/$variant/lib/libonnxruntime_providers_cuda.so"
if bash "$verifier" nvidia x64 >/dev/null 2>&1; then echo 'changed AppImage provider passed' >&2; exit 1; fi
if bash "$verifier" amd arm64 >/dev/null 2>&1; then echo 'unsupported AMD arm64 passed' >&2; exit 1; fi
echo 'GPU candidate package verification fixtures passed'
