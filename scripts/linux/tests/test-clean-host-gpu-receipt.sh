#!/usr/bin/env bash
# Exercise the pinned shared clean-host receipt helper without installing packages.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
hub=${ANTFRASTRUCTURE_DIR:-"$repo/third_party/ANTfrastructure"}
helper="$hub/.github/actions/clean-host-package-check/clean-host-gpu-receipt.sh"
receipt="$hub/shared/python/gpu_artifact_receipt.py"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export GITHUB_REPOSITORY=Kataglyphis/OmniAccelerANT GITHUB_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export GITHUB_RUN_ID=123 GITHUB_RUN_ATTEMPT=2 GPU_ARTIFACT_ID=456 GPU_CHECK_NAME=clean-host-inference
export GPU_MAX_BYTES=100000 GPU_MAX_RATIO=1000 GPU_RECEIPT="$work/receipt.json"
export GPU_PACKAGES_DIR="$work/packages" GPU_BEFORE_RECEIPT="$work/before.json"
export GPU_ARCHIVE_DIR="$work/archive" RUNNER_TEMP="$work"
export DEB_GLOB='*.deb' TARBALL_GLOB='*.tar.gz' APPIMAGE_GLOB='*.AppImage'
export DEB_COMMAND=true TARBALL_COMMAND=true APPIMAGE_COMMAND=true PACKAGE_SUBDIR=
mkdir "$GPU_ARCHIVE_DIR"

for tuple in nvidia:x64 nvidia:arm64 amd:x64; do
  IFS=: read -r GPU_VENDOR GPU_ARCH <<< "$tuple"
  export GPU_VENDOR GPU_ARCH
  if [[ "$GPU_ARCH" == x64 ]]; then deb=amd64; machine=x86_64; else deb=arm64; machine=aarch64; fi
  prefix="omni-accelerant-$GPU_VENDOR"
  tarball="$prefix-linux-$GPU_ARCH.tar.gz"
  debfile="${prefix}_1_${deb}.deb"
  appimage="$prefix-1-$machine.AppImage"
  GPU_ARTIFACT_FILES=$(printf '%s\n%s\n%s' "$tarball" "$debfile" "$appimage")
  export GPU_ARTIFACT_FILES
  python3 - "$GPU_ARCHIVE_DIR/candidate.zip" "$tarball" "$debfile" "$appimage" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as archive:
    for name in sys.argv[2:]:
        archive.writestr(name, name.encode())
PY
  GPU_ARTIFACT_DIGEST=$(sha256sum "$GPU_ARCHIVE_DIR/candidate.zip" | cut -d' ' -f1)
  export GPU_ARTIFACT_DIGEST
  bash "$helper" validate
  bash "$helper" prepare
  bash "$helper" finish
  identity=(--repository "$GITHUB_REPOSITORY" --revision "$GITHUB_SHA" --run-id "$GITHUB_RUN_ID"
    --run-attempt "$GITHUB_RUN_ATTEMPT" --artifact-id "$GPU_ARTIFACT_ID" --artifact-digest "$GPU_ARTIFACT_DIGEST"
    --platform linux --arch "$GPU_ARCH" --vendor "$GPU_VENDOR"
    --file "$tarball" --file "$debfile" --file "$appimage")
  python3 -I "$receipt" verify --directory "$GPU_PACKAGES_DIR" --receipt "$GPU_RECEIPT" \
    --check clean-host-inference "${identity[@]}"
  for mutation in 'GPU_ARTIFACT_ID=999' 'GITHUB_RUN_ATTEMPT=3' 'GPU_ARTIFACT_DIGEST=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; do
    rm -f -- "$GPU_RECEIPT"
    if env "$mutation" bash "$helper" finish >/dev/null 2>&1; then echo "Accepted $mutation" >&2; exit 1; fi
  done
  printf changed >> "$GPU_PACKAGES_DIR/$debfile"
  if bash "$helper" finish >/dev/null 2>&1; then echo 'Accepted changed candidate bytes' >&2; exit 1; fi
  rm -rf -- "$GPU_PACKAGES_DIR" "$GPU_BEFORE_RECEIPT" "$GPU_ARCHIVE_DIR/candidate.zip"
done
if env GPU_VENDOR=amd GPU_ARCH=arm64 bash "$helper" validate >/dev/null 2>&1; then
  echo 'Accepted unsupported ARM ROCm' >&2; exit 1
fi
echo 'PASS: clean-host receipts bind candidate bytes and run identity for supported tuples'
