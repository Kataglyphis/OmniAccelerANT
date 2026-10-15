#!/usr/bin/env bash
# collect-release-assets.sh <artifacts dir> <out dir> <version>: every lane's packages for a release, flat and named with version and arch.
set -euo pipefail

artifacts="${1:?usage: collect-release-assets.sh <artifacts dir> <out dir> <version>}"
out="${2:?usage: collect-release-assets.sh <artifacts dir> <out dir> <version>}"
version="${3:?usage: collect-release-assets.sh <artifacts dir> <out dir> <version>}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

# put <file> <name>: one release file; a second one of the same name would silently replace the first.
put() {
  if [ -e "${out}/$2" ]; then
    printf 'two artifacts carry %s\n' "$2" >&2
    exit 1
  fi
  cp "$1" "${out}/$2"
}

# zip_dir <dir> <name>: an app folder (Windows) as one file.
zip_dir() {
  [ ! -e "${out}/$2" ] || { printf 'two artifacts carry %s\n' "$2" >&2; exit 1; }
  (cd "$1" && zip -qr "${out}/$2" .)
}

linux_arch() { case "$1" in x64) echo x86_64 ;; arm64) echo aarch64 ;; *) printf 'unknown arch %s\n' "$1" >&2; exit 1 ;; esac; }

collect() {
  local dir="$1" name="$2" arch file
  case "$name" in
    omni-observant-*)
      for file in "$dir"*; do [ -f "$file" ] && put "$file" "$(basename "$file")"; done ;;
    omni-accelerant-linux-*-packages)
      arch="${name#omni-accelerant-linux-}"; arch="${arch%-packages}"
      for file in "$dir"*.deb "$dir"*.AppImage; do [ -f "$file" ] && put "$file" "$(basename "$file")"; done
      # The flatpak is named without its arch, so both arches' would collide.
      for file in "$dir"*.flatpak; do [ -f "$file" ] && put "$file" "omni-accelerant-${version}-$(linux_arch "$arch").flatpak"; done ;;
    omni-accelerant-linux-*-tar)
      arch="${name#omni-accelerant-linux-}"; arch="${arch%-tar}"
      put "${dir}omni-accelerant-linux-${arch}.tar.gz" "omni-accelerant-${version}-linux-${arch}.tar.gz" ;;
    omni-accelerant-apk-*-tar)
      tar -xzf "${dir}"omni-accelerant-apk-*.tar.gz -C "${dir}"
      put "${dir}omni-accelerant-apk-bundle/app-release.apk" "omni-accelerant-${version}-android-arm64-v8a.apk" ;;
    windows-release-files) zip_dir "$dir" "omni-accelerant-${version}-windows-x64.zip" ;;
    omni-accelerant-windows-arm64) zip_dir "$dir" "omni-accelerant-${version}-windows-arm64.zip" ;;
    # Logs, debug builds, the arm64 natives the app links, and the web build the ObservANT packages hold.
    build-log*|flutter-build-log-*|*-debug|*-natives-*|gstreamer-ai-web-frontend|*-test-results|*-tests) ;;
    *) printf 'artifact %s is neither collected nor skipped: decide in collect-release-assets.sh\n' "$name" >&2; exit 1 ;;
  esac
}

for dir in "$artifacts"/*/; do
  collect "$dir" "$(basename "$dir")"
done

# A lane that uploaded nothing must not leave a release without its platform.
for expected in "omni-accelerant-${version}-windows-x64.zip" "omni-accelerant-${version}-windows-arm64.zip" \
  "omni-accelerant-${version}-android-arm64-v8a.apk" "omni-accelerant_${version}_amd64.deb" \
  "omni-accelerant_${version}_arm64.deb" "omni-observant_${version}_arm64.deb"; do
  [ -e "${out}/${expected}" ] || { printf 'the release would lack %s\n' "$expected" >&2; exit 1; }
done
ls -1 "$out"
