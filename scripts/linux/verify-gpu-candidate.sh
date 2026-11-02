#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/linux/lib/gpu-script-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/gpu-script-common.sh"
gpu_require_argc $# 2 2 'verify-gpu-candidate.sh nvidia|amd x64|arm64'
vendor=$1 arch=$2
facts="$(gpu_target_facts "$vendor" "$arch")" || exit 2
read -r machine deb provider <<< "$facts"
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hub="${ANTFRASTRUCTURE_DIR:-$repo/third_party/ANTfrastructure}/linux/scripts/06-packaging"
# shellcheck source=/dev/null
source "$hub/ort-runtime-bundle.sh"
# shellcheck source=/dev/null
source "$hub/ort-package-proof.sh"
variant="omni-accelerant-$vendor"
shopt -s nullglob
tarballs=("out/$variant-linux-$arch.tar.gz")
debs=(out/"${variant}"_*_"${deb}".deb)
images=(out/"${variant}"-*-"${machine}".AppImage)
if [[ ${#tarballs[@]} -ne 1 || ! -f ${tarballs[0]} || ${#debs[@]} -ne 1 || ${#images[@]} -ne 1 ]]; then
  echo "Expected one $vendor $arch tar, DEB and AppImage candidate" >&2
  exit 1
fi
gpu_deb_field_is "${debs[0]}" Architecture "$deb" || gpu_die 1 "DEB architecture does not match $arch"
gpu_deb_field_is "${debs[0]}" Package "$variant" || gpu_die 1 "DEB package identity does not match $variant"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

verify_detector_model() {
  local root="$1" bundle="$2" directory resolved
  directory="$bundle/data/resources/models"
  resolved="$(realpath -e "$directory")" || { echo 'Missing bundled detector models' >&2; return 1; }
  case "$resolved/" in "$root/"*) ;; *) echo 'Detector models escape package' >&2; return 1 ;; esac
  python3 -I "$repo/scripts/windows/verify_detector_model.py" \
    "$hub/../lib/fetch-data-lock.py" "$repo/third_party/OxidANT/resources/models/models.lock" "$directory" --root "$root"
}

verify_tree() {
  local root="$1" bundle="$2"
  local -a libs=()
  root="$(realpath -e "$root")"
  bundle="$(realpath -e "$bundle")"
  case "$bundle/" in "$root/"*) ;; *) echo 'Bundle escapes extracted package' >&2; return 1 ;; esac
  ort_assert_no_bundled_host_runtime "$root" "$provider"
  ort_package_collect_libraries "$root" "$bundle/lib" libs libonnxruntime.so libonnxruntime.so.1 \
    libonnxruntime_providers_shared.so "libonnxruntime_providers_${provider}.so"
  mkdir -p "$work/proven"
  python3 "$hub/stage-ort-wheel-licenses.py" --require-unstripped \
    --wheel-dir "${ORT_CHAIN_WHEEL_DIR:-/opt/onnxruntime-wheels}" --destination "$work/proven" \
    --strip "${STRIP:-strip}" "${libs[@]}"
  ort_package_verify_notices "$root" "$bundle/licenses/onnxruntime" "$work/proven/licenses/onnxruntime"
  verify_detector_model "$root" "$bundle"
}

mkdir -p "$work/tar" "$work/deb"
tar -xzf "${tarballs[0]}" -C "$work/tar"
dpkg-deb -x "${debs[0]}" "$work/deb"
verify_tree "$work/tar" "$work/tar/${variant}-bundle"
verify_tree "$work/deb" "$work/deb/opt/$variant"
bash "$hub/verify-ort-appimage-payload.sh" "${images[0]}" "$arch" \
  "usr/lib/$variant/lib" "usr/lib/$variant/licenses/onnxruntime" "$vendor"
image="$(realpath -e "${images[0]}")"
mkdir "$work/appimage"
(
  cd "$work/appimage"
  "$image" --appimage-extract "usr/lib/$variant/data/resources/models/*" > /dev/null
  root="$(realpath -e squashfs-root)"
  verify_detector_model "$root" "$root/usr/lib/$variant"
)
mkdir "$work/appimage-ort"
(
  cd "$work/appimage-ort"
  "$image" --appimage-extract "usr/lib/$variant/lib/libonnxruntime.so*" > /dev/null
  root="$(realpath -e squashfs-root)"
  alias="$root/usr/lib/$variant/lib/libonnxruntime.so"
  [[ -f "$alias" ]] || gpu_die 1 'AppImage is missing the ORT dynamic-load alias'
  resolved="$(realpath -e "$alias")"
  case "$resolved" in "$root/"*) ;; *) gpu_die 1 'AppImage ORT alias escapes package' ;; esac
)
echo 'PASS: unverified GPU candidates carry the wheel-matched runtime and locked model'
