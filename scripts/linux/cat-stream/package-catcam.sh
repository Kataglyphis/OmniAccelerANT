#!/usr/bin/env bash
# Packages the cat cam service: a self-contained bundle (its own GStreamer, ONNX Runtime and C library)
# and a .deb and an AppImage that install it as a systemd service, autostarted. Runs inside the family image.
#
# Usage, from the repository root inside the image:
#   bash scripts/linux/cat-stream/package-catcam.sh --web-root build/web [options]
#
#   --web-root DIR   the Flutter web build (the web lane's build/web); required
#   --model FILE     ONNX model to ship (default: AccelerANTgine's yolo26n.onnx)
#   --producer FILE  a built kataglyphis_cat_webrtc (default: cargo build --release here)
#   --out DIR        where the .deb, the AppImage and the bundle tarball land (default: out/)
#   --version X.Y.Z  package version (default: pubspec.yaml's, without +build)
#
# Details: docs/source/camera-streaming.md § The cat cam package.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../.." && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${script_dir}/../lib/antfrastructure.sh"

package=omni-accelerant-catcam
prefix="/opt/${package}"
web_root=""
model="${repo_root}/third_party/AccelerANTgine/models/yolo26n.onnx"
producer=""
out_dir="${repo_root}/out"
version=""

while [ $# -gt 0 ]; do
  case "$1" in
    --web-root) web_root="${2:?--web-root needs a directory}"; shift 2 ;;
    --model) model="${2:?--model needs a file}"; shift 2 ;;
    --producer) producer="${2:?--producer needs a file}"; shift 2 ;;
    --out) out_dir="${2:?--out needs a directory}"; shift 2 ;;
    --version) version="${2:?--version needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "${web_root}" ] || { printf -- '--web-root is required\n' >&2; exit 2; }
[ -f "${web_root}/index.html" ] || { printf 'no index.html in %s\n' "${web_root}" >&2; exit 1; }
[ -f "${model}" ] || { printf 'model not found: %s\n' "${model}" >&2; exit 1; }
for tool in patchelf dpkg-deb readelf ldd appimagetool; do
  command -v "${tool}" >/dev/null 2>&1 || { printf '%s not found\n' "${tool}" >&2; exit 1; }
done

case "$(uname -m)" in
  x86_64) deb_arch=amd64; triplet=x86_64-linux-gnu; loader=ld-linux-x86-64.so.2 ;;
  aarch64) deb_arch=arm64; triplet=aarch64-linux-gnu; loader=ld-linux-aarch64.so.1 ;;
  *) printf 'unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac

if [ -z "${version}" ]; then
  version="$(sed -n 's/^version:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' "${repo_root}/pubspec.yaml" | head -1)"
  [ -n "${version}" ] || { printf 'no version in pubspec.yaml\n' >&2; exit 1; }
fi

if [ -z "${producer}" ]; then
  printf 'building kataglyphis_cat_webrtc (release)\n'
  export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/catcam-target}"
  (cd "${repo_root}/third_party/OxidANT" && cargo build --release --locked -p kataglyphis_cat_webrtc)
  producer="${CARGO_TARGET_DIR}/release/kataglyphis_cat_webrtc"
fi
[ -x "${producer}" ] || { printf 'producer not executable: %s\n' "${producer}" >&2; exit 1; }

# Container-native work dir: the bind mount cannot chmod for the container uid (AGENTS.md § 5).
work="$(mktemp -d /tmp/catcam-work.XXXXXX)"
trap 'rm -rf "${work}"' EXIT
bundle="${work}/bundle"
mkdir -p "${bundle}/bin" "${bundle}/lib/gstreamer-1.0" "${bundle}/libexec" "${bundle}/models" \
  "${bundle}/share/doc/${package}"

install -m 755 "${producer}" "${bundle}/bin/kataglyphis_cat_webrtc"
cp -a "${web_root}" "${bundle}/web"
install -m 644 "${model}" "${bundle}/models/$(basename "${model}")"
model_name="$(basename "${model}")"

# The service's pipelines and webrtcsink's own; without debugutilsbad's errorignore its codec discovery finds none.
gst_plugin_dir=/opt/gstreamer/lib/multiarch/gstreamer-1.0
plugins=(coreelements app videoconvertscale videorate videofilter videotestsrc rawparse videoparsersbad debugutilsbad
  jpeg png multifile video4linux2 rswebrtc rsrtp webrtc nice dtls srtp sctp rtpmanager rtp vpx)
for plugin in "${plugins[@]}"; do
  [ -e "${gst_plugin_dir}/libgst${plugin}.so" ] || {
    printf 'GStreamer plugin %s not in the image (%s)\n' "${plugin}" "${gst_plugin_dir}" >&2
    exit 1
  }
  cp -L "${gst_plugin_dir}/libgst${plugin}.so" "${bundle}/lib/gstreamer-1.0/"
done
# H.264 is a second codec offer; VP8 alone streams to every browser.
if [ -e "${gst_plugin_dir}/libgstopenh264.so" ]; then
  cp -L "${gst_plugin_dir}/libgstopenh264.so" "${bundle}/lib/gstreamer-1.0/"
else
  printf 'warning: openh264 not in the image, the stream offers VP8 only\n' >&2
fi
# The image keeps libcamerasrc beside its libcamera, not in the GStreamer prefix.
libcamera_plugin="${LIBCAMERA_PREFIX:-/opt/libcamera}/lib/gstreamer-1.0/libgstlibcamera.so"
if [ -e "${libcamera_plugin}" ]; then
  cp -L "${libcamera_plugin}" "${bundle}/lib/gstreamer-1.0/"
else
  printf 'warning: libcamerasrc not in the image\n' >&2
fi

# webrtcsink's codec discovery needs a registry built by the scanner, under the bundled loader too.
scanner="$(find /opt/gstreamer -name gst-plugin-scanner -type f 2>/dev/null | head -1 || true)"
[ -n "${scanner}" ] || { printf 'gst-plugin-scanner not found in the image\n' >&2; exit 1; }
install -m 755 "${scanner}" "${bundle}/libexec/gst-plugin-scanner"
cat > "${bundle}/libexec/gst-plugin-scanner-wrapper" <<WRAPPER
#!/bin/sh
here="\$(cd -- "\$(dirname -- "\$0")/.." && pwd)"
exec "\$here/lib/${loader}" --library-path "\$here/lib" "\$here/libexec/gst-plugin-scanner" "\$@"
WRAPPER
chmod 755 "${bundle}/libexec/gst-plugin-scanner-wrapper"

# The chain ONNX Runtime only (owner rule 2026-09-23); G6 below proves the bytes.
ort_dir="${ORT_LIB_LOCATION:-/usr/local/lib/onnxruntime-cpu/lib}"
ort_copied=0
for lib in "${ort_dir}"/libonnxruntime.so*; do
  [ -e "${lib}" ] || continue
  cp -L "${lib}" "${bundle}/lib/"
  ort_copied=$((ort_copied + 1))
done
[ "${ort_copied}" -gt 0 ] || { printf 'no chain libonnxruntime.so* in %s\n' "${ort_dir}" >&2; exit 1; }

# The image's glibc is newer than Debian 13's or Raspberry Pi OS's, so the C runtime travels too.
cp -L "/lib/${triplet}/${loader}" "${bundle}/lib/"

# libsrtp2's NSS loads its softokn and freebl modules from beside libnss3, so they travel with it.
nss_lib="$(ldd "${bundle}/lib/gstreamer-1.0/libgstsrtp.so" 2>/dev/null | awk '/libnss3/ {print $3}')"
if [ -n "${nss_lib}" ]; then
  for module in libsoftokn3.so libfreeblpriv3.so libfreebl3.so; do
    if [ -e "$(dirname "${nss_lib}")/${module}" ]; then
      cp -L "$(dirname "${nss_lib}")/${module}" "${bundle}/lib/"
    fi
  done
fi

# Transitive closure. libcamera stays the host's: its IPA and tuning must match the host kernel.
declare -A seen=()
queue=()
while IFS= read -r -d '' f; do queue+=("$f"); done \
  < <(find "${bundle}/bin" "${bundle}/lib" "${bundle}/libexec" -type f \( -name '*.so*' -o -perm -u+x \) -print0)
while ((${#queue[@]})); do
  f="${queue[0]}"; queue=("${queue[@]:1}")
  while IFS= read -r dep; do
    [ -n "${dep}" ] || continue
    case "${dep}" in "${bundle}"/*) continue ;; esac
    base="$(basename "${dep}")"
    case "${base}" in
      libcamera.so.*|libcamera-base.so.*|libonnxruntime.so*) continue ;;
    esac
    [ -n "${seen[${base}]:-}" ] && continue
    seen[${base}]=1
    cp -L "${dep}" "${bundle}/lib/${base}"
    queue+=("${bundle}/lib/${base}")
  done < <(ldd "${f}" 2>/dev/null | awk '/=> \// {print $3} /^\t\/[^ ]+ \(/ {print $1}')
done

# The image also carries a distro GStreamer; a libgst* from outside /opt/gstreamer would be the wrong one.
while IFS= read -r line; do
  case "${line}" in
    */opt/gstreamer/*) ;;
    *libgst*) printf 'a GStreamer library resolved outside /opt/gstreamer: %s\n' "${line}" >&2; exit 1 ;;
  esac
done < <(ldd "${bundle}/bin/kataglyphis_cat_webrtc" 2>/dev/null | awk '/libgst/ {print $1 " " $3}')

# Loaders ask for sonames; the copies are named after the resolved files.
for lib in "${bundle}"/lib/*.so*; do
  soname="$(readelf -d "${lib}" 2>/dev/null | awk '/SONAME/ {gsub(/[][]/,""); print $NF}')"
  if [ -n "${soname}" ] && [ ! -e "${bundle}/lib/${soname}" ]; then
    ln -s "$(basename "${lib}")" "${bundle}/lib/${soname}"
  fi
done

# The launcher passes --library-path; this RUNPATH says the same to G6's ld.so model.
# shellcheck disable=SC2016
patchelf --set-rpath '$ORIGIN/../lib' "${bundle}/bin/kataglyphis_cat_webrtc"
bash "$(antfrastructure_path linux/scripts/06-packaging/check-ort-provenance.sh)" "${bundle}"

cat > "${bundle}/catcam" <<LAUNCHER
#!/bin/sh
# Runs the cat cam with its own GStreamer, ONNX Runtime and C library, whatever the host ships.
# Arguments and ${package}'s catcam.toml settings pass straight through.
here="\$(cd -- "\$(dirname -- "\$(readlink -f -- "\$0")")" && pwd)"
case "\${1:-}" in
  --install|--uninstall) exec "\$here/libexec/catcam-install" "\$@" ;;
esac
export GST_PLUGIN_PATH="\$here/lib/gstreamer-1.0"
# Never the host's plugins: they are built against another GStreamer.
export GST_PLUGIN_SYSTEM_PATH=""
export GST_PLUGIN_SYSTEM_PATH_1_0=""
export GST_PLUGIN_SCANNER="\$here/libexec/gst-plugin-scanner-wrapper"
export GST_REGISTRY="\${GST_REGISTRY:-\${XDG_CACHE_HOME:-\$HOME/.cache}/${package}/gst-registry.bin}"
mkdir -p "\$(dirname "\$GST_REGISTRY")"
export ORT_DYLIB_PATH="\${ORT_DYLIB_PATH:-\$here/lib/libonnxruntime.so.1}"
export KATAGLYPHIS_WEB_ROOT="\${KATAGLYPHIS_WEB_ROOT:-\$here/web}"
export KATAGLYPHIS_ONNX_MODEL="\${KATAGLYPHIS_ONNX_MODEL:-\$here/models/${model_name}}"
# --library-path, not LD_LIBRARY_PATH: a child such as rpicam-vid must keep the host's libraries.
exec "\$here/lib/${loader}" --library-path "\$here/lib" "\$here/bin/kataglyphis_cat_webrtc" "\$@"
LAUNCHER
chmod 755 "${bundle}/catcam"

# The installer the AppImage and the tarball run, and the files it installs; the .deb installs the same ones.
install -m 755 "${script_dir}/catcam/catcam-install" "${bundle}/libexec/catcam-install"
mkdir -p "${bundle}/share/${package}"
for file in omni-catcam.service catcam.toml ufw-omni-catcam; do
  install -m 644 "${script_dir}/catcam/${file}" "${bundle}/share/${package}/${file}"
done

cat > "${bundle}/share/doc/${package}/NOTICE-model" <<NOTICE
${model_name} is an Ultralytics YOLO model, licensed AGPL-3.0
(https://www.gnu.org/licenses/agpl-3.0.html; https://ultralytics.com/license).
It is a separate work shipped beside the MIT-licensed OmniAccelerANT code; replace it
with a model of your choice through 'model' in /etc/omni-accelerant/catcam.toml.
NOTICE

# --- the .deb --------------------------------------------------------------------------------
deb="${work}/deb"
mkdir -p "${deb}/DEBIAN" "${deb}${prefix}" "${deb}/usr/bin" "${deb}/usr/lib/systemd/system" \
  "${deb}/etc/ufw/applications.d"
cp -a "${bundle}/." "${deb}${prefix}/"
ln -s "${prefix}/catcam" "${deb}/usr/bin/omni-catcam"
install -m 644 "${script_dir}/catcam/omni-catcam.service" "${deb}/usr/lib/systemd/system/"
install -m 644 "${script_dir}/catcam/ufw-omni-catcam" "${deb}/etc/ufw/applications.d/omni-catcam"
for script in postinst prerm postrm; do
  install -m 755 "${script_dir}/catcam/${script}" "${deb}/DEBIAN/${script}"
done
# catcam.toml is postinst's, written once from the bundle's copy, so no upgrade asks about an edited one.
printf '%s\n' /etc/ufw/applications.d/omni-catcam > "${deb}/DEBIAN/conffiles"
installed_kb="$(du -sk "${deb}" | cut -f1)"
cat > "${deb}/DEBIAN/control" <<CONTROL
Package: ${package}
Version: ${version}
Architecture: ${deb_arch}
Maintainer: Kataglyphis <dev@kataglyphis.local>
Section: video
Priority: optional
Installed-Size: ${installed_kb}
Homepage: https://github.com/Kataglyphis/OmniAccelerANT
Description: OmniAccelerANT cat cam - camera, YOLO cat boxes, WebRTC and its web page
 Picks the Raspberry Pi camera when one is attached, else a USB webcam, draws a
 box around every cat it sees and streams the picture to any browser on the LAN
 at http://<this-host>:8080/. Runs as the omni-catcam service from boot; turn
 that off with: sudo systemctl disable --now omni-catcam
 Settings: /etc/omni-accelerant/catcam.toml. Firewall: sudo ufw allow OmniCatCam
CONTROL

mkdir -p "${out_dir}"
deb_file="${out_dir}/${package}_${version}_${deb_arch}.deb"
dpkg-deb --root-owner-group --build "${deb}" "${deb_file}" >/dev/null
tar -C "${bundle}/.." -czf "${out_dir}/${package}-${version}-linux-${deb_arch}.tar.gz" \
  --transform "s|^bundle|${package}|" bundle

# --- the AppImage: the bundle in the foreground, or `sudo <AppImage> --install` --------------
appdir="${work}/appdir"
cp -a "${bundle}" "${appdir}"
ln -s catcam "${appdir}/AppRun"
install -m 644 "${repo_root}/assets/icons/kataglyphis_app_icon.svg" "${appdir}/${package}.svg"
cat > "${appdir}/${package}.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=OmniAccelerANT Cat Cam
Comment=Camera, YOLO cat boxes and a WebRTC stream for any browser on the network
Exec=catcam
Icon=${package}
Categories=AudioVideo;Video;
Terminal=true
DESKTOP
# The image stages appimagetool's runtime; naming it keeps the build from downloading one.
runtime_args=()
for candidate in "${HOME:-/root}/.local/share/appimagekit/runtime-$(uname -m)" \
  "/etc/skel/.local/share/appimagekit/runtime-$(uname -m)"; do
  if [ -f "${candidate}" ]; then
    runtime_args=(--runtime-file "${candidate}")
    break
  fi
done
appimage_file="${out_dir}/${package}-${version}-$(uname -m).AppImage"
if ! APPIMAGE_EXTRACT_AND_RUN=1 NO_APPSTREAM=1 ARCH="$(uname -m)" \
  appimagetool "${runtime_args[@]}" "${appdir}" "${appimage_file}" >"${work}/appimagetool.log" 2>&1; then
  cat "${work}/appimagetool.log" >&2
  printf 'appimagetool failed for %s\n' "${appimage_file}" >&2
  exit 1
fi

printf 'bundle: %s files, %s\n' "$(find "${bundle}" -type f | wc -l)" "$(du -sh "${bundle}" | cut -f1)"
printf 'wrote %s (%s)\n' "${deb_file}" "$(du -h "${deb_file}" | cut -f1)"
printf 'wrote %s (%s)\n' "${appimage_file}" "$(du -h "${appimage_file}" | cut -f1)"
