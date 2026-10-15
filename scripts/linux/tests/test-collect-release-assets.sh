#!/usr/bin/env bash
# test-collect-release-assets.sh: collect-release-assets.sh against artifact trees shaped like a release run's uploads.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
collect="${here}/../collect-release-assets.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
fails=0
check() {
  if "${@:2}"; then printf 'ok    %s\n' "$1"; else printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); fi
}

# artifacts <dir>: one of each upload a release run makes, two bytes apiece.
artifacts() {
  local a="$1" arch deb
  for arch in x64 arm64; do
    deb=amd64; [ "$arch" = arm64 ] && deb=arm64
    mkdir -p "${a}/omni-accelerant-linux-${arch}-packages" "${a}/omni-accelerant-linux-${arch}-tar" "${a}/omni-observant-linux-${arch}"
    printf 'd' > "${a}/omni-accelerant-linux-${arch}-packages/omni-accelerant_2.1.0_${deb}.deb"
    printf 'f' > "${a}/omni-accelerant-linux-${arch}-packages/omni-accelerant-2.1.0.flatpak"
    printf 't' > "${a}/omni-accelerant-linux-${arch}-tar/omni-accelerant-linux-${arch}.tar.gz"
    printf 'o' > "${a}/omni-observant-linux-${arch}/omni-observant_2.1.0_${deb}.deb"
  done
  for arch in x64 arm64; do
    mkdir -p "${a}/omni-observant-windows-${arch}"
    printf 'm' > "${a}/omni-observant-windows-${arch}/omni-observant-2.1.0-windows-${arch}.msi"
  done
  mkdir -p "${a}/omni-accelerant-apk-linux-x64-tar/src/omni-accelerant-apk-bundle" "${a}/windows-release-files/data" \
    "${a}/omni-accelerant-windows-arm64" "${a}/build-log" "${a}/omni-accelerant-natives-windows-arm64" \
    "${a}/omni-accelerant-windows-arm64-debug" "${a}/gstreamer-ai-web-frontend"
  printf 'apk' > "${a}/omni-accelerant-apk-linux-x64-tar/src/omni-accelerant-apk-bundle/app-release.apk"
  tar -czf "${a}/omni-accelerant-apk-linux-x64-tar/omni-accelerant-apk-linux-x64.tar.gz" -C "${a}/omni-accelerant-apk-linux-x64-tar/src" omni-accelerant-apk-bundle
  rm -rf "${a}/omni-accelerant-apk-linux-x64-tar/src"
  printf 'exe' > "${a}/windows-release-files/omni_accelerant.exe"
  printf 'dat' > "${a}/windows-release-files/data/app.so"
  printf 'exe' > "${a}/omni-accelerant-windows-arm64/omni_accelerant.exe"
  printf 'log' > "${a}/build-log/build.log"
  printf 'dll' > "${a}/omni-accelerant-natives-windows-arm64/AccelerANTgine.dll"
  printf 'dbg' > "${a}/omni-accelerant-windows-arm64-debug/omni_accelerant.exe"
  printf 'js' > "${a}/gstreamer-ai-web-frontend/main.dart.js"
}

artifacts "${work}/a"
out="${work}/release"
check "a full release run's uploads collect" bash -c "bash '${collect}' '${work}/a' '${out}' 2.1.0 >/dev/null"
check "both Windows apps, zipped" test -s "${out}/omni-accelerant-2.1.0-windows-x64.zip" -a -s "${out}/omni-accelerant-2.1.0-windows-arm64.zip"
check "the x64 zip keeps its folders" bash -c "unzip -l '${out}/omni-accelerant-2.1.0-windows-x64.zip' | grep -q 'data/app.so'"
check "the APK out of its tarball" test "$(cat "${out}/omni-accelerant-2.1.0-android-arm64-v8a.apk")" = apk
check "each flatpak named for its arch" test -e "${out}/omni-accelerant-2.1.0-x86_64.flatpak" -a -e "${out}/omni-accelerant-2.1.0-aarch64.flatpak"
check "each tarball named with the version" test -e "${out}/omni-accelerant-2.1.0-linux-x64.tar.gz" -a -e "${out}/omni-accelerant-2.1.0-linux-arm64.tar.gz"
check "the ObservANT packages as they are" test -e "${out}/omni-observant_2.1.0_arm64.deb" -a -e "${out}/omni-observant_2.1.0_amd64.deb"
check "and its MSIs for both Windows arches" test -e "${out}/omni-observant-2.1.0-windows-x64.msi" -a -e "${out}/omni-observant-2.1.0-windows-arm64.msi"
check "no logs, natives, debug build or web build" bash -c "! ls '${out}' | grep -qE 'log|AccelerANTgine|debug|dart.js'"

artifacts "${work}/b"
mkdir -p "${work}/b/omni-accelerant-macos"
check "an upload nobody decided about fails the release" bash -c "bash '${collect}' '${work}/b' '${work}/r2' 2.1.0 2>&1 | grep -q 'neither collected nor skipped'"

artifacts "${work}/c"
rm -rf "${work}/c/omni-accelerant-windows-arm64"
check "a release without Windows arm64 fails" bash -c "bash '${collect}' '${work}/c' '${work}/r3' 2.1.0 2>&1 | grep -q 'would lack omni-accelerant-2.1.0-windows-arm64.zip'"

artifacts "${work}/e"
rm -rf "${work}/e/omni-observant-windows-arm64"
check "a release without the arm64 ObservANT fails" bash -c "bash '${collect}' '${work}/e' '${work}/r5' 2.1.0 2>&1 | grep -q 'would lack omni-observant-2.1.0-windows-arm64.msi'"

artifacts "${work}/d"
mkdir -p "${work}/d/omni-observant-linux-x64-again"
cp "${work}/d/omni-observant-linux-x64/omni-observant_2.1.0_amd64.deb" "${work}/d/omni-observant-linux-x64-again/"
check "two uploads of one file name fail rather than overwrite" bash -c "bash '${collect}' '${work}/d' '${work}/r4' 2.1.0 2>&1 | grep -q 'two artifacts carry'"

if [ "${fails}" -gt 0 ]; then
  printf '%d of the collect checks failed\n' "${fails}"
  exit 1
fi
printf 'collect-release-assets: all checks passed\n'
