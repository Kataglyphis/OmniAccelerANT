#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 2 ]]; then echo 'usage: verify-gpu-candidate.sh nvidia|amd x64|arm64' >&2; exit 2; fi
vendor=$1 arch=$2
case "$vendor:$arch" in
  nvidia:x64) machine=x86_64; deb=amd64; provider=cuda ;;
  nvidia:arm64) machine=aarch64; deb=arm64; provider=cuda ;;
  amd:x64) machine=x86_64; deb=amd64; provider=migraphx ;;
  *) echo 'Unsupported GPU candidate' >&2; exit 2 ;;
esac
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hub="${ANTFRASTRUCTURE_DIR:-$repo/third_party/ANTfrastructure}/linux/scripts/06-packaging"
# shellcheck source=/dev/null
source "$hub/ort-runtime-bundle.sh"
variant="omni-accelerant-$vendor"
shopt -s nullglob
tarballs=("out/$variant-linux-$arch.tar.gz")
debs=(out/"${variant}"_*_"${deb}".deb)
images=(out/"${variant}"-*-"${machine}".AppImage)
if [[ ${#tarballs[@]} -ne 1 || ! -f ${tarballs[0]} || ${#debs[@]} -ne 1 || ${#images[@]} -ne 1 ]]; then
  echo "Expected one $vendor $arch tar, DEB and AppImage candidate" >&2
  exit 1
fi
[[ "$(dpkg-deb --field "${debs[0]}" Architecture)" == "$deb" ]] || {
  echo "DEB architecture does not match $arch" >&2; exit 1;
}
[[ "$(dpkg-deb --field "${debs[0]}" Package)" == "$variant" ]] || {
  echo "DEB package identity does not match $variant" >&2; exit 1;
}
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

collect_ort_libraries() {
  local root="$1" lib="$2/lib" file resolved name
  for name in libonnxruntime.so libonnxruntime.so.1 libonnxruntime_providers_shared.so "libonnxruntime_providers_${provider}.so"; do
    [[ -f "$lib/$name" ]] || { echo "Missing GPU ORT library: $name" >&2; return 1; }
  done
  for file in "$lib"/libonnxruntime*.so*; do
    [[ -f "$file" ]] || continue
    resolved="$(realpath -e "$file")"
    case "$resolved" in "$root/"*) ;; *) echo 'ORT library escapes package' >&2; return 1 ;; esac
    name="${file##*/}"
    case "$name" in
      libonnxruntime_providers_*) [[ ! -L "$file" ]] || { echo 'ORT provider is a symlink' >&2; return 1; } ;;
      libonnxruntime.so*) [[ "${resolved##*/}" =~ ^libonnxruntime\.so(\.[0-9]+)*$ ]] || { echo 'ORT core aliases another component' >&2; return 1; } ;;
    esac
    libs+=(--library "$file")
  done
}

verify_ort_notices() {
  local root="$1" bundle="$2" name notice resolved
  for name in LICENSE ThirdPartyNotices.txt; do
    notice="$bundle/licenses/onnxruntime/$name"
    [[ -f "$notice" && ! -L "$notice" ]] || { echo "Missing or symlinked ORT notice: $notice" >&2; return 1; }
    resolved="$(realpath -e "$notice")"
    case "$resolved" in "$root/"*) ;; *) echo 'ORT notice escapes package' >&2; return 1 ;; esac
    cmp "$notice" "$work/proven/licenses/onnxruntime/$name"
  done
}

verify_detector_model() {
  local root="$1" bundle="$2" directory resolved
  directory="$bundle/data/resources/models"
  resolved="$(realpath -e "$directory")" || { echo 'Missing bundled detector models' >&2; return 1; }
  case "$resolved/" in "$root/"*) ;; *) echo 'Detector models escape package' >&2; return 1 ;; esac
  python3 -I "$repo/scripts/windows/verify_detector_model.py" \
    "$hub/../lib/fetch-data-lock.py" "$repo/third_party/OxidANT/resources/models/models.lock" "$directory"
}

verify_tree() {
  local root="$1" bundle="$2"
  local -a libs=()
  root="$(realpath -e "$root")"
  bundle="$(realpath -e "$bundle")"
  case "$bundle/" in "$root/"*) ;; *) echo 'Bundle escapes extracted package' >&2; return 1 ;; esac
  ort_assert_no_bundled_host_runtime "$root" "$provider"
  collect_ort_libraries "$root" "$bundle"
  mkdir -p "$work/proven"
  python3 "$hub/stage-ort-wheel-licenses.py" --require-unstripped \
    --wheel-dir "${ORT_CHAIN_WHEEL_DIR:-/opt/onnxruntime-wheels}" --destination "$work/proven" \
    --strip "${STRIP:-strip}" "${libs[@]}"
  verify_ort_notices "$root" "$bundle"
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
  [[ -f "$alias" ]] || { echo 'AppImage is missing the ORT dynamic-load alias' >&2; exit 1; }
  resolved="$(realpath -e "$alias")"
  case "$resolved" in "$root/"*) ;; *) echo 'AppImage ORT alias escapes package' >&2; exit 1 ;; esac
)
echo 'PASS: unverified GPU candidates carry the wheel-matched runtime and locked model'
