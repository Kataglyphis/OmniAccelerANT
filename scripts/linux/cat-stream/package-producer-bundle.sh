#!/usr/bin/env bash
# Packages a self-contained aarch64 runtime bundle of the cat producer for a
# host that cannot run the :latest container (e.g. a Raspberry Pi Zero
# 2 W with 512 MB RAM). The producer, its GStreamer subset and the transitive
# closure of their shared libraries are exported from the image into
# build/cat-stream/pi-bundle/; the bundle runs natively with its own run.sh.
#
# It uses the target host's libcamera (same 0.7 soname as the image's), so the
# camera stack stays the one Raspberry Pi OS ships for that board, while the
# image's glibc is bundled and invoked explicitly - the host's glibc version
# does not matter, only libcamera with its IPA and tuning files must be there.
#
# Usage:
#   scripts/linux/cat-stream/package-producer-bundle.sh [--build] [--deploy HOST]
#
# --build        build the producer in the container first
# --deploy HOST  rsync the finished bundle to HOST:cat-cam/ afterwards
#
# On the target:
#   ~/cat-cam/run.sh --no-inference --libcamera          # no AI, camera only
#   ~/cat-cam/run.sh --libcamera                         # needs a model in models/
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../.." && pwd)"

# The image ref is ANTfrastructure's, never spelled out here: versions.env is
# the fleet's one owner of both tags, a spelled-out copy freezes at the tag it
# was written on, and the hub's verify_ci_image_refs.py check D fails any
# tracked *.sh that carries one. Resolved in two assignments, never one: a
# command substitution that dies inside a larger expansion is swallowed by
# `set -e`. Same block as OxidANT's run-producer-pi.sh, its Pi 5 sibling.
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${script_dir}/../lib/antfrastructure.sh"
_ci_image_ref_sh="$(antfrastructure_path linux/scripts/ci-image-ref.sh)"
image="$(bash "${_ci_image_ref_sh}")"
target_volume="kataglyphis-cat-target"
cargo_volume="kataglyphis-cat-cargo"
bundle_dir="${repo_root}/build/cat-stream/pi-bundle"
producer="/cargo-target/release/kataglyphis_cat_webrtc"
do_build=false
deploy=""

while [ $# -gt 0 ]; do
  case "$1" in
    --build) do_build=true; shift ;;
    --deploy) deploy="${2:?--deploy needs a host}"; shift 2 ;;
    -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

command -v nerdctl >/dev/null 2>&1 || { printf 'nerdctl not found\n' >&2; exit 1; }

producer_present() {
  nerdctl run --rm --user 0:0 --entrypoint bash -v "${target_volume}":/cargo-target "${image}" \
    -c "test -x ${producer}" >/dev/null 2>&1
}

if [ "${do_build}" = true ] || ! producer_present; then
  printf 'building kataglyphis_cat_webrtc in the container\n'
  nerdctl run --rm --user 0:0 --network host \
    -v "${repo_root}":/workspace \
    -v "${target_volume}":/cargo-target \
    -v "${cargo_volume}":/cargo-home \
    -e CARGO_TARGET_DIR=/cargo-target -e CARGO_HOME=/cargo-home \
    --entrypoint bash "${image}" \
    -lc 'cd /workspace/third_party/OxidANT && cargo build --release --locked -p kataglyphis_cat_webrtc'
fi

printf 'assembling %s\n' "${bundle_dir}"
rm -rf "${bundle_dir}"
mkdir -p "${bundle_dir}"
nerdctl run --rm -i --user 0:0 \
  -v "${target_volume}":/cargo-target \
  -v "${bundle_dir}":/out \
  --entrypoint bash "${image}" -s <<'BUNDLE_BUILDER'
set -euo pipefail

mkdir -p /out/bin /out/lib /out/gstreamer-1.0 /out/libexec
install -m 755 /cargo-target/release/kataglyphis_cat_webrtc /out/bin/
for tool in gst-inspect-1.0 gst-launch-1.0; do
  if [ -e "/opt/gstreamer/bin/${tool}" ]; then
    install -m 755 "/opt/gstreamer/bin/${tool}" /out/bin/
  fi
done

# GStreamer plugin subset for: libcamerasrc -> videoconvert/videoscale ->
# vp8enc -> webrtcsink (which pulls in the webrtc/sdp/dtls/sctp/nice bits).
gst_lib_dir=/opt/gstreamer/lib/multiarch
gst_plugin_dir="${gst_lib_dir}/gstreamer-1.0"
for plugin in coreelements app videoconvertscale videorate videofilter videotestsrc debugutilsbad vpx rswebrtc webrtc nice sdp dtls sctp rtpmanager rtp; do
  if [ -e "${gst_plugin_dir}/libgst${plugin}.so" ]; then
    cp -L "${gst_plugin_dir}/libgst${plugin}.so" /out/gstreamer-1.0/
  else
    printf 'warning: plugin %s not found in the image\n' "${plugin}" >&2
  fi
done

# The image keeps the libcamera plugin next to its libcamera build, not in the
# GStreamer prefix.
if [ -e /opt/libcamera/lib/gstreamer-1.0/libgstlibcamera.so ]; then
  cp -L /opt/libcamera/lib/gstreamer-1.0/libgstlibcamera.so /out/gstreamer-1.0/
else
  printf 'warning: libcamera plugin not found in the image\n' >&2
fi

# Codec discovery only finds encoders/payloaders when the registry is built by
# the plugin scanner, and the scanner must run under the bundled glibc too -
# hence the wrapper.
scanner="$(find /opt/gstreamer -name gst-plugin-scanner -type f 2>/dev/null | head -1 || true)"
if [ -n "${scanner}" ]; then
  install -m 755 "${scanner}" /out/libexec/gst-plugin-scanner
  cat > /out/libexec/gst-plugin-scanner-wrapper <<'WRAPPER'
#!/bin/sh
here="$(cd -- "$(dirname -- "$0")/.." && pwd)"
exec "$here/lib/ld-linux-aarch64.so.1" --library-path "$here/lib" \
  "$here/libexec/gst-plugin-scanner" "$@"
WRAPPER
  chmod 755 /out/libexec/gst-plugin-scanner-wrapper
else
  printf 'warning: gst-plugin-scanner not found in the image\n' >&2
fi

# Core GStreamer libraries (and GES and friends, a few MB - not worth pruning).
for lib in "${gst_lib_dir}"/libgst*.so* "${gst_lib_dir}"/libges*.so*; do
  [ -e "${lib}" ] || continue
  cp -L "${lib}" /out/lib/
done

# Dynamic-load-only dependency: nothing links against it, the producer loads
# it when a detector is created, so copy it explicitly.
for lib in /opt/opencv5/lib/libonnxruntime.so*; do
  [ -e "${lib}" ] || continue
  cp -L "${lib}" /out/lib/
done

# The image's glib is built against glibc 2.43 while Raspberry Pi OS ships
# 2.41, so the C runtime is part of the bundle too (run.sh invokes this loader
# explicitly instead of the host's).
cp -L /lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 /out/lib/

# Transitive library closure of everything in the bundle, including the C
# runtime copied above.
declare -A seen=()
queue=()
while IFS= read -r -d '' f; do queue+=("$f"); done \
  < <(find /out/bin /out/lib /out/gstreamer-1.0 /out/libexec -type f -print0)
while ((${#queue[@]})); do
  f="${queue[0]}"; queue=("${queue[@]:1}")
  while IFS= read -r dep; do
    [ -n "${dep}" ] || continue
    case "${dep}" in /out/*) continue ;; esac
    base="$(basename "${dep}")"
    # libcamera deliberately stays out of the bundle: the plugin must load the
    # target's own build (its IPA and tuning match the target's kernel).
    case "${base}" in
      libcamera.so.0.7|libcamera.so.0.7.*|libcamera-base.so.0.7|libcamera-base.so.0.7.*) continue ;;
    esac
    [ -n "${seen[${base}]:-}" ] && continue
    seen[${base}]=1
    cp -L "${dep}" "/out/lib/${base}"
    queue+=("/out/lib/${base}")
  done < <(ldd "${f}" 2>/dev/null | awk '/=> \// {print $3} /^\t\/[^ ]+ \(/ {print $1}')
done

# Loaders ask for sonames; the copies above are named after the resolved
# files, so link every soname that is not already a file.
for lib in /out/lib/*; do
  soname="$(readelf -d "${lib}" 2>/dev/null | awk '/SONAME/ {gsub(/[][]/,""); print $NF}')"
  if [ -n "${soname}" ] && [ ! -e "/out/lib/${soname}" ]; then
    ln -s "$(basename "${lib}")" "/out/lib/${soname}"
  fi
done

printf 'bundle: %s files, %s\n' "$(find /out -type f | wc -l)" "$(du -sh /out | cut -f1)"
BUNDLE_BUILDER

cat > "${bundle_dir}/run.sh" <<'RUN_SH'
#!/usr/bin/env bash
# Runs the cat producer from the bundle with its own GStreamer, without a
# container. Pass producer flags through, e.g.:
#   ./run.sh --no-inference --libcamera
#   ./run.sh --libcamera --model models/yolov10n.onnx
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

export GST_PLUGIN_PATH="${here}/gstreamer-1.0"
# Never load the host's plugins into this GStreamer: version skew (1.29 here
# vs whatever the distro ships) makes the registry reject them anyway.
export GST_PLUGIN_SYSTEM_PATH=""
export GST_PLUGIN_SYSTEM_PATH_1_0=""
# The scanner builds the plugin registry (in-process registration makes
# webrtcsink's codec discovery come up empty) and itself runs under the
# bundled glibc through the wrapper.
export GST_PLUGIN_SCANNER="${here}/libexec/gst-plugin-scanner-wrapper"
export GST_REGISTRY="${GST_REGISTRY:-${HOME}/.cache/cat-cam/gst-registry.bin}"
mkdir -p "$(dirname "${GST_REGISTRY}")"
export ORT_DYLIB_PATH="${ORT_DYLIB_PATH:-${here}/lib/libonnxruntime.so.1}"

# The image's glibc is bundled; invoke its loader explicitly so the host's
# (older) libc never loads these libraries.
exec "${here}/lib/ld-linux-aarch64.so.1" --library-path "${here}/lib" \
  "${here}/bin/kataglyphis_cat_webrtc" "$@"
RUN_SH
chmod +x "${bundle_dir}/run.sh"

if [ -n "${deploy}" ]; then
  printf 'deploying to %s:cat-cam/\n' "${deploy}"
  rsync -a --delete "${bundle_dir}/" "${deploy}:cat-cam/"
  printf 'done - run it there with: ssh %s '"'"'~/cat-cam/run.sh --no-inference --libcamera'"'"'\n' "${deploy}"
fi
