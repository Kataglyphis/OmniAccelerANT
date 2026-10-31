#!/usr/bin/env bash
# Copyright (c) 2026 Kataglyphis
# SPDX-License-Identifier: MIT
# Tests the inventory drift check and native coverage gate offline; regeneration with cargo is not run here.
set -uo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "${script_dir}/../../.." && pwd)"
source "${script_dir}/../lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
coverage="${repo}/scripts/licenses/check-native-coverage.py"

# fresh_tree: the generator's inputs and outputs, copied so a mutation cannot touch the checkout.
fresh_tree() {
  rm -rf "$work/tree"
  mkdir -p "$work/tree/docs/source" "$work/tree/assets" "$work/tree/scripts" \
    "$work/tree/third_party/OxidANT" "$work/tree/third_party/AccelerANTgine/Src/rusty_code"
  cp -a "${repo}/scripts/licenses" "$work/tree/scripts/"
  cp -a "${repo}/assets/licenses" "$work/tree/assets/"
  cp "${repo}/docs/source/third-party-components.md" "$work/tree/docs/source/"
  cp "${repo}/pubspec.lock" "${repo}/LICENSE" "$work/tree/"
  cp "${repo}/third_party/OxidANT/Cargo.lock" "${repo}/third_party/OxidANT/LICENSE" "$work/tree/third_party/OxidANT/"
  cp "${repo}/third_party/AccelerANTgine/LICENSE" "$work/tree/third_party/AccelerANTgine/"
  cp "${repo}/third_party/AccelerANTgine/Src/rusty_code/Cargo.lock" "$work/tree/third_party/AccelerANTgine/Src/rusty_code/"
}
check_tree() { python3 "$work/tree/scripts/licenses/generate-third-party-licenses.py" --check; }

t_case 'workspace license metadata remains truthful and parseable'
t_assert_ok python3 "${repo}/scripts/licenses/tests/test_workspace_license.py"

t_case 'the committed inventory matches its inputs'
t_assert_ok python3 "${repo}/scripts/licenses/generate-third-party-licenses.py" --check
fresh_tree
t_assert_ok check_tree

t_case 'a changed lockfile, text, chunk or page fails the drift check'
printf '\n' >> "$work/tree/third_party/OxidANT/Cargo.lock"
t_assert_fails check_tree
fresh_tree
printf 'altered\n' >> "$work/tree/scripts/licenses/texts/native/gstreamer/COPYING"
t_assert_fails check_tree
fresh_tree
rm "$work/tree/assets/licenses/third-party-license-texts-1.json"
t_assert_fails check_tree
fresh_tree
printf 'edited\n' >> "$work/tree/docs/source/third-party-components.md"
t_assert_fails check_tree
fresh_tree
sed -i 's/  dependency: "direct main"/  dependency: "direct dev"/' "$work/tree/pubspec.lock"
t_assert_fails check_tree

t_case 'every shipped native file needs a table entry'
mkdir -p "$work/linux/lib/gstreamer-1.0"
t_fake_elf "$work/linux/lib/libgstreamer-1.0.so.0" 62
t_fake_elf "$work/linux/lib/gstreamer-1.0/libgstapp.so" 62
t_fake_elf "$work/linux/omni_accelerant.bin" 62
t_fake_elf "$work/linux/lib/libonnxruntime_providers_shared.so" 62
t_fake_elf "$work/linux/lib/libonnxruntime_providers_cuda.so" 62
t_fake_elf "$work/linux/lib/libonnxruntime_providers_migraphx.so" 62
printf '{}' > "$work/linux/lib/notes.json"
t_assert_ok python3 "$coverage" --platform linux "$work/linux"
t_fake_elf "$work/linux/lib/libmystery.so.1" 62
t_assert_fails python3 "$coverage" --platform linux "$work/linux"
t_fake_elf "$work/linux/unnamed-elf" 62
rm "$work/linux/lib/libmystery.so.1"
t_assert_fails python3 "$coverage" --platform linux "$work/linux"
mkdir -p "$work/empty"
t_assert_fails python3 "$coverage" --platform linux "$work/empty"

t_case 'Windows names match case-insensitively and an unknown DLL fails'
mkdir -p "$work/windows/gstreamer-1.0"
: > "$work/windows/OMNI_ACCELERANT.EXE"
: > "$work/windows/gstreamer-1.0/gstapp.dll"
: > "$work/windows/libcrypto-4-x64.dll"
: > "$work/windows/onnxruntime_providers_cuda.dll"
t_assert_ok python3 "$coverage" --platform windows "$work/windows"
: > "$work/windows/x264-164.dll"
t_assert_fails python3 "$coverage" --platform windows "$work/windows"

t_case 'an APK is read from its lib/ slices'
t_zip "$work/good.apk" lib/arm64-v8a/libflutter.so lib/arm64-v8a/liboxidant.so lib/arm64-v8a/libdartjni.so assets/flutter_assets/NOTICES.Z
t_assert_ok python3 "$coverage" --platform android "$work/good.apk"
t_zip "$work/bad.apk" lib/arm64-v8a/libflutter.so lib/arm64-v8a/libmystery.so
t_assert_fails python3 "$coverage" --platform android "$work/bad.apk"

t_case 'removing a table entry uncovers its files'
python3 - "${repo}/scripts/licenses/native-components.json" "$work/table.json" <<'PY'
import json
import sys

table = json.load(open(sys.argv[1], encoding="utf-8"))
table["components"] = [c for c in table["components"] if c["id"] != "gstreamer"]
json.dump(table, open(sys.argv[2], "w", encoding="utf-8"))
PY
rm "$work/linux/unnamed-elf"
t_assert_fails python3 "$coverage" --platform linux --table "$work/table.json" "$work/linux"

t_case 'every package path runs the coverage gate and ships the inventory'
t_assert_contains "$(cat "${repo}/scripts/linux/lib/packaging-common.sh")" 'check_native_license_coverage "$bundle" linux'
for lane in lane-android.sh ci-container-run-android.sh; do
  t_assert_contains "$(cat "${repo}/scripts/linux/ci/${lane}")" 'check_native_license_coverage "build/app/outputs/flutter-apk/app-${BUILD_MODE}.apk" android'
done
omni_ps="$(cat "${repo}/scripts/windows/Package-OmniAccelerANT.ps1")"
t_assert_contains "$omni_ps" 'Assert-NativeLicenseCoverage -Path $AppDir -RepoRoot $repoRoot'
t_assert_contains "$omni_ps" 'Assert-ThirdPartyLicensePackage -Path "$base.msi" -RepoRoot $repoRoot -Asset $licenseAssets'
t_assert_contains "$omni_ps" 'Assert-ThirdPartyLicensePackage -Path "$base.msix" -RepoRoot $repoRoot -Asset $licenseAssets'
observant_ps="$(cat "${repo}/scripts/windows/observant/Package-ObservANT.ps1")"
t_assert_contains "$observant_ps" 'Assert-ThirdPartyLicensePackage -Path "$msixBase.msi" -RepoRoot $repoRoot -Asset $licenseAssets'
t_assert_contains "$observant_ps" "Assert-ThirdPartyLicensePackage -Path \"\$msixBase.msix\" -RepoRoot \$repoRoot -Asset \$licenseAssets -MemberPrefix '*web/assets/'"

t_summary
