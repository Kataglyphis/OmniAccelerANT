#!/usr/bin/env bash
# Copyright (c) 2026 Kataglyphis
# SPDX-License-Identifier: MIT
# Tests Flutter license and launcher wiring, not full builds or other bundled dependencies.
set -uo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/../lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"
source "${script_dir}/../lib/packaging-common.sh"
source "${script_dir}/../lib/container-steps.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export APP_PACKAGING_BUNDLE_DIR="$work/bundle"
mkdir -p "$APP_PACKAGING_BUNDLE_DIR/licenses/onnxruntime"
printf 'ORT license\n' > "$APP_PACKAGING_BUNDLE_DIR/licenses/onnxruntime/LICENSE"
printf 'ORT notices\n' > "$APP_PACKAGING_BUNDLE_DIR/licenses/onnxruntime/ThirdPartyNotices.txt"
mkdir -p "$APP_PACKAGING_BUNDLE_DIR/lib"
t_fake_elf "$APP_PACKAGING_BUNDLE_DIR/lib/libflutter_linux_gtk.so" 62
mapfile -t inventory < <(python3 "$KATAGLYPHIS_REPO_ROOT/scripts/licenses/generate-third-party-licenses.py" --list-assets)

# copy_inventory <flutter_assets dir>: the third-party license assets, as a Flutter build bundles them.
copy_inventory() {
  local asset
  for asset in "${inventory[@]}"; do
    mkdir -p "$1/$(dirname "$asset")"
    cp "$KATAGLYPHIS_REPO_ROOT/$asset" "$1/$asset"
  done
}

write_flutter_notice() {
  python3 - "$KATAGLYPHIS_REPO_ROOT/LICENSE" "$1" <<'PY'
import gzip
import pathlib
import sys

pathlib.Path(sys.argv[2]).write_bytes(gzip.compress(pathlib.Path(sys.argv[1]).read_bytes()))
PY
}

python3 - "$work" "$KATAGLYPHIS_REPO_ROOT" "${inventory[@]}" <<'PY'
import gzip
import pathlib
import sys
import zipfile

work, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
license_text = (root / "LICENSE").read_bytes()
assets = {name: (root / name).read_bytes() for name in sys.argv[3:]}
fixtures = (("good.apk", license_text, assets), ("wrong.apk", b"wrong license", assets), ("bare.apk", license_text, {}))
for name, content, inventory in fixtures:
    with zipfile.ZipFile(work / name, "w") as package:
        package.writestr("assets/flutter_assets/NOTICES.Z", gzip.compress(content))
        for member, data in inventory.items():
            package.writestr(f"assets/flutter_assets/{member}", data)
with zipfile.ZipFile(work / "web.msix", "w") as package:
    package.writestr("web/assets/NOTICES", license_text)
    for member, data in assets.items():
        package.writestr(f"web/assets/{member}", data)
PY

t_case 'APK and web notices contain the full project text'
t_assert_ok verify_flutter_package_license "$work/good.apk" '*flutter_assets/NOTICES.Z'
t_assert_ok verify_flutter_package_license "$work/web.msix" '*web/assets/NOTICES'
t_assert_fails verify_flutter_package_license "$work/wrong.apk" '*flutter_assets/NOTICES.Z'
t_assert_fails verify_flutter_package_license "$work/good.apk" '*missing/NOTICES.Z'
t_assert_fails verify_flutter_package_license "$work/bare.apk" '*flutter_assets/NOTICES.Z'

t_case 'both Android build paths call the shared launcher and APK license checks'
for lane in lane-android.sh ci-container-run-android.sh; do
  lane_source="$(cat "${script_dir}/../ci/${lane}")"
  t_assert_contains "$lane_source" 'check_flutter_launcher_artifacts'
  t_assert_contains "$lane_source" 'verify_flutter_package_license "build/app/outputs/flutter-apk/app-${BUILD_MODE}.apk"'
done

t_case 'the shared launcher check rejects a missing Android icon'
mkdir -p "$work/fixture/android/app/src/main"
cp "$KATAGLYPHIS_REPO_ROOT/pubspec.yaml" "$work/fixture/"
cp "$KATAGLYPHIS_REPO_ROOT/android/app/src/main/AndroidManifest.xml" "$work/fixture/android/app/src/main/"
cp -a "$KATAGLYPHIS_REPO_ROOT/android/app/src/main/res" "$work/fixture/android/app/src/main/"
KATAGLYPHIS_REPO_ROOT="$work/fixture" t_assert_ok check_flutter_launcher_artifacts
rm "$work/fixture/android/app/src/main/res/mipmap-hdpi/ic_launcher.png"
KATAGLYPHIS_REPO_ROOT="$work/fixture" t_assert_fails check_flutter_launcher_artifacts

t_case 'the deb wrapper validates the artifact built by the shared packager'
t_needs 'dpkg-deb' command -v dpkg-deb
mkdir -p "$work/deb/DEBIAN" "$work/deb/opt/omni-accelerant/data/flutter_assets" "$work/deb/opt/omni-accelerant/licenses"
cp -a "$APP_PACKAGING_BUNDLE_DIR/licenses/onnxruntime" "$work/deb/opt/omni-accelerant/licenses/"
printf 'Package: omni-accelerant\nVersion: 1.2.3\nArchitecture: amd64\nMaintainer: Test <test@example.invalid>\nDescription: test\n' > "$work/deb/DEBIAN/control"
write_flutter_notice "$work/deb/opt/omni-accelerant/data/flutter_assets/NOTICES.Z"
copy_inventory "$work/deb/opt/omni-accelerant/data/flutter_assets"
dpkg-deb --root-owner-group --build "$work/deb" "$work/omni-accelerant_1.2.3_amd64.deb" >/dev/null
app_packaging_package_linux_bundle_deb() { return 0; }
APP_PACKAGING_VERSION=1.2.3 APP_PACKAGING_OUT_DIR="$work" t_assert_ok package_deb_with_project_license x64 Omni-AccelerANT
printf wrong > "$work/deb/opt/omni-accelerant/licenses/onnxruntime/ThirdPartyNotices.txt"
dpkg-deb --root-owner-group --build "$work/deb" "$work/omni-accelerant_1.2.3_amd64.deb" >/dev/null
APP_PACKAGING_VERSION=1.2.3 APP_PACKAGING_OUT_DIR="$work" t_assert_fails package_deb_with_project_license x64 Omni-AccelerANT
cp "$APP_PACKAGING_BUNDLE_DIR/licenses/onnxruntime/ThirdPartyNotices.txt" "$work/deb/opt/omni-accelerant/licenses/onnxruntime/"
printf wrong > "$work/deb/opt/omni-accelerant/data/flutter_assets/NOTICES.Z"
dpkg-deb --root-owner-group --build "$work/deb" "$work/omni-accelerant_1.2.3_amd64.deb" >/dev/null
APP_PACKAGING_VERSION=1.2.3 APP_PACKAGING_OUT_DIR="$work" t_assert_fails package_deb_with_project_license x64 Omni-AccelerANT
unset -f app_packaging_package_linux_bundle_deb

t_case 'tar packaging checks the completed archive'
mkdir -p "$work/tar/Omni-AccelerANT-bundle/data/flutter_assets" "$work/tar/Omni-AccelerANT-bundle/licenses" "$work/out"
cp -a "$APP_PACKAGING_BUNDLE_DIR/licenses/onnxruntime" "$work/tar/Omni-AccelerANT-bundle/licenses/"
cp "$work/deb/opt/omni-accelerant/data/flutter_assets/NOTICES.Z" "$work/tar/Omni-AccelerANT-bundle/data/flutter_assets/NOTICES.Z"
copy_inventory "$work/tar/Omni-AccelerANT-bundle/data/flutter_assets"
app_packaging_package_linux_bundle_tar() { tar -C "$work/tar" -czf "$work/out/Omni-AccelerANT-linux-x64.tar.gz" Omni-AccelerANT-bundle; }
cd "$work" || exit 1
APP_PACKAGING_VERSION=1.2.3 t_assert_fails package_tar_with_project_license x64 Omni-AccelerANT
write_flutter_notice "$work/tar/Omni-AccelerANT-bundle/data/flutter_assets/NOTICES.Z"
APP_PACKAGING_VERSION=1.2.3 t_assert_ok package_tar_with_project_license x64 Omni-AccelerANT
printf wrong > "$work/tar/Omni-AccelerANT-bundle/licenses/onnxruntime/ThirdPartyNotices.txt"
APP_PACKAGING_VERSION=1.2.3 t_assert_fails package_tar_with_project_license x64 Omni-AccelerANT

t_case 'the native AppImage and Flatpak paths are checked after packaging'
app_packaging_package_linux_bundle_appimage() { return 0; }
verify_flutter_appimage_license() { if [ "$1" = "$work/omni-accelerant-1.2.3-x86_64.AppImage" ] && [ "$2" = x64 ] && [ "$3" = 'usr/lib/omni-accelerant/data/flutter_assets/NOTICES.Z' ] && [ "${APPIMAGE_FAILURE:-0}" = 0 ]; then return 0; fi; return 1; }
verify_ort_wheel_appimage_licenses() { if [ "$1" = "$work/omni-accelerant-1.2.3-x86_64.AppImage" ] && [ "$2" = "$APP_PACKAGING_BUNDLE_DIR" ] && [ "$3" = x64 ] && [ "$4" = 'usr/lib/omni-accelerant' ] && [ "${ORT_FAILURE:-0}" = 0 ]; then return 0; fi; return 1; }
APP_PACKAGING_VERSION=1.2.3 APP_PACKAGING_OUT_DIR="$work" t_assert_ok package_appimage_with_project_license x64 Omni-AccelerANT
APP_PACKAGING_VERSION=1.2.3 APP_PACKAGING_OUT_DIR="$work" APPIMAGE_FAILURE=1 t_assert_fails package_appimage_with_project_license x64 Omni-AccelerANT
APP_PACKAGING_VERSION=1.2.3 APP_PACKAGING_OUT_DIR="$work" ORT_FAILURE=1 t_assert_fails package_appimage_with_project_license x64 Omni-AccelerANT
app_packaging_package_linux_bundle_flatpak() { return 0; }
verify_flutter_package_license() { if [ "$1" = "$work/omni-accelerant-1.2.3.flatpak" ] && [ "$2" = '*flutter_assets/NOTICES.Z' ]; then return 0; fi; return 1; }
verify_ort_wheel_package_licenses() { if [ "$1" = "$work/omni-accelerant-1.2.3.flatpak" ] && [ "$2" = "$APP_PACKAGING_BUNDLE_DIR" ] && [ "$3" = 'files/lib/omni-accelerant' ]; then return 0; fi; return 1; }
APP_PACKAGING_VERSION=1.2.3 APP_PACKAGING_OUT_DIR="$work" t_assert_ok package_with_project_license flatpak x64 Omni-AccelerANT
package_source="$(cat "${script_dir}/../package-linux.sh")"
observant_source="$(cat "${script_dir}/../observant/package-observant.sh")"
bundle_source="$(cat "${script_dir}/../bundle-runtime-closure.sh")"
producer_source="$(cat "${script_dir}/../observant/package-producer-bundle.sh")"
t_assert_contains "$package_source" 'package_with_project_license flatpak "$@"'
t_assert_contains "$package_source" 'tar) packager=package_tar_with_project_license'
t_assert_contains "$package_source" 'appimage) packager=package_appimage_with_project_license'
t_assert_contains "$observant_source" 'verify_flutter_package_license "${out_dir}/${package}-${version}-linux-${deb_arch}.tar.gz"'
t_assert_contains "$observant_source" 'verify_flutter_appimage_license "${appimage_file}"'
t_assert_contains "$observant_source" 'verify_flutter_package_license "${flatpak_file}"'
t_assert_contains "$bundle_source" 'stage_ort_wheel_licenses "$BUNDLE_DIR"'
t_assert_contains "$observant_source" 'stage_ort_wheel_licenses "${bundle}"'
t_assert_contains "$observant_source" 'verify_ort_wheel_package_licenses "${deb_file}"'
t_assert_contains "$observant_source" 'verify_ort_wheel_package_licenses "${out_dir}/${package}-${version}-linux-${deb_arch}.tar.gz"'
t_assert_contains "$observant_source" 'verify_ort_wheel_appimage_licenses "${appimage_file}"'
t_assert_contains "$observant_source" 'verify_ort_wheel_package_licenses "${flatpak_file}"'
t_assert_contains "$producer_source" 'stage_ort_wheel_licenses /out'
t_assert_contains "$producer_source" 'verify_ort_wheel_package_licenses /out /out .'

t_summary
