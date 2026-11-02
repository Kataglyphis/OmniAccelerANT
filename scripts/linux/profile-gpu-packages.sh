#!/usr/bin/env bash
# Check each finished Linux candidate format on the CPU and requested GPU.
set -euo pipefail
# shellcheck source=scripts/linux/lib/gpu-script-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/gpu-script-common.sh"
gpu_require_argc $# 4 4 'profile-gpu-packages.sh PACKAGE_DIR nvidia|amd x64|arm64 cuda|migraphx'
unset LD_PRELOAD LD_AUDIT
package_dir=$(realpath -e "$1") vendor=$2 arch=$3 provider=$4
facts="$(gpu_target_facts "$vendor" "$arch")" || exit 2
read -r machine deb target_provider <<< "$facts"
[[ "$provider" == "$target_provider" ]] || { echo 'Unsupported GPU candidate' >&2; exit 2; }
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$script_dir/../.." && pwd)
fixture="$repo/third_party/OxidANT/crates/inference/tests/fixtures/two_cats.jpg"
variant="omni-accelerant-$vendor"
shopt -s nullglob
tarball="$package_dir/$variant-linux-$arch.tar.gz"
debs=("$package_dir/${variant}_"*"_${deb}.deb")
images=("$package_dir/${variant}-"*"-${machine}.AppImage")
[[ -f "$tarball" && ${#debs[@]} -eq 1 && ${#images[@]} -eq 1 ]] || { echo 'Expected one candidate tarball, DEB and AppImage' >&2; exit 1; }
gpu_deb_field_is "${debs[0]}" Architecture "$deb" && gpu_deb_field_is "${debs[0]}" Package "$variant" || {
  echo 'DEB package or architecture does not match target' >&2; exit 1;
}
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/omni-gpu-packages.XXXXXXXX")
work=$(realpath -e "$work")
trap 'rm -rf -- "$work"' EXIT
evidence=${PROFILE_EVIDENCE_DIR:-"$work/evidence"}
mkdir -- "$evidence"
evidence=$(realpath -e "$evidence")
case "$evidence" in "$work/tar"|"$work/tar/"*|"$work/deb"|"$work/deb/"*) echo 'Evidence must be outside temporary extraction directories' >&2; exit 1 ;; esac
mkdir -p "$work/tar" "$work/deb" "$work/image" "$work/image-tmp"
preflight="$script_dir/preflight-profile-packages.py"
export PROFILE_DISK_PLAN="$work/space-plan.json" PROFILE_DISK_ROOT="$work"
python3 -I "$preflight" create --tar "$tarball" --deb "${debs[0]}" --image "${images[0]}" \
  --plan "$PROFILE_DISK_PLAN" --root "$PROFILE_DISK_ROOT"
python3 -I "$preflight" check --plan "$PROFILE_DISK_PLAN" --root "$PROFILE_DISK_ROOT" --stage tar
tar -xzf "$tarball" -C "$work/tar"
bash "$script_dir/profile-gpu-candidate.sh" "$work/tar/$variant-bundle" "$provider" "$fixture" "$evidence/tar"
rm -rf -- "$work/tar"
python3 -I "$preflight" check --plan "$PROFILE_DISK_PLAN" --root "$PROFILE_DISK_ROOT" --stage deb
dpkg-deb -x "${debs[0]}" "$work/deb"
bash "$script_dir/profile-gpu-candidate.sh" "$work/deb/opt/$variant" "$provider" "$fixture" "$evidence/deb"
rm -rf -- "$work/deb"
python3 -I "$preflight" check --plan "$PROFILE_DISK_PLAN" --root "$PROFILE_DISK_ROOT" --stage image
cp -- "${images[0]}" "$work/candidate.AppImage"
chmod u+x "$work/candidate.AppImage"
python3 -I "$preflight" check --plan "$PROFILE_DISK_PLAN" --root "$PROFILE_DISK_ROOT" --stage extract
(cd "$work/image" && env -u LD_PRELOAD -u LD_AUDIT "$work/candidate.AppImage" --appimage-extract >/dev/null)
APPIMAGE_EXTRACT_AND_RUN=1 TMPDIR="$work/image-tmp" bash "$script_dir/profile-gpu-candidate.sh" \
  "$work/image/squashfs-root/usr/lib/$variant" "$provider" "$fixture" "$evidence/appimage" "$work/candidate.AppImage"
echo 'CPU/GPU detector parity and provider profiles passed for all candidate formats'
