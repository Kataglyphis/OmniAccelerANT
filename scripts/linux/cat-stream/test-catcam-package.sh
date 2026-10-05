#!/usr/bin/env bash
# Installs the cat cam .deb and AppImage the way a user does and checks what each promises; root, inside :latest.
set -uo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../.." && pwd)"
deb=""
appimage=""
photo="${repo_root}/third_party/ANThology/assets/images/cats/Summy&Thundy_compressed.png"

usage() {
  cat <<'EOF'
usage: test-catcam-package.sh [--deb FILE] [--appimage FILE] [--photo FILE]

Runs as root in the family image (dpkg, a service user, headless Chrome). Each
check prints PASS or FAIL; the exit code is the number of failures.
  --deb FILE       the .deb (default: this machine's in out/, as package-catcam.sh names it)
  --appimage FILE  the AppImage (default: this machine's in out/)
  --photo FILE     a photo with a cat in it (default: ANThology's Summy & Thundy)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --deb) deb="${2:?--deb needs a file}"; shift 2 ;;
    --appimage) appimage="${2:?--appimage needs a file}"; shift 2 ;;
    --photo) photo="${2:?--photo needs a file}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
case "$(uname -m)" in
  x86_64) deb_arch=amd64 ;;
  aarch64) deb_arch=arm64 ;;
  *) deb_arch="$(uname -m)" ;;
esac
shopt -s nullglob
debs=("${repo_root}"/out/omni-accelerant-catcam_*_"${deb_arch}".deb)
appimages=("${repo_root}"/out/omni-accelerant-catcam-*-"$(uname -m)".AppImage)
shopt -u nullglob
[ -n "${deb}" ] || deb="${debs[0]:-}"
[ -n "${appimage}" ] || appimage="${appimages[0]:-}"
[ -f "${deb}" ] && [ -f "${appimage}" ] || { printf 'no .deb or AppImage for %s\n' "${deb_arch}" >&2; usage >&2; exit 2; }
printf 'testing %s and %s\n' "$(basename "${deb}")" "$(basename "${appimage}")"
[ -f "${photo}" ] || { printf 'no photo at %s\n' "${photo}" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { printf 'run as root: dpkg and the service user need it\n' >&2; exit 2; }

prefix=/opt/omni-accelerant-catcam
state=/var/lib/omni-accelerant-catcam
config=/etc/omni-accelerant/catcam.toml
user=omni-catcam
work="$(mktemp -d /tmp/catcam-test.XXXXXX)"
failures=0

check() {
  local name="$1"; shift
  if "$@"; then
    printf 'PASS  %s\n' "${name}"
  else
    printf 'FAIL  %s\n' "${name}"
    failures=$((failures + 1))
  fi
}

# The unit's environment and nothing else: no LD_LIBRARY_PATH, no GST_*, no image PATH.
as_service() {
  env -i HOME="${state}" GST_REGISTRY="${state}/gst-registry.bin" PATH=/usr/bin:/bin \
    setpriv --reuid="${user}" --regid="${user}" --init-groups "$@"
}

# exec in a subshell: $! is then the service itself, which a backgrounded function is not.
start_service() {
  local log="$1"; shift
  (exec env -i HOME="${state}" GST_REGISTRY="${state}/gst-registry.bin" PATH=/usr/bin:/bin \
    setpriv --reuid="${user}" --regid="${user}" --init-groups "$@" >"${log}" 2>&1) &
}

# Root in a container may not read another uid's maps; the service's own uid may. Unreadable maps fail.
nothing_outside_bundle() {
  local maps outside
  maps="$(setpriv --reuid="${user}" --regid="${user}" --init-groups cat "/proc/$1/maps")" || return 1
  outside="$(printf '%s\n' "${maps}" | awk '$6 ~ /\.so/ {print $6}' | sort -u | grep -v "^${prefix}/")"
  [ -z "${outside}" ] || { printf '      outside: %s\n' "${outside}" | tr '\n' ' '; echo; return 1; }
}

stop_service() {
  kill -TERM "$1" 2>/dev/null
  wait "$1"
}

wait_healthz() {
  local _
  for _ in $(seq 1 100); do
    curl -sf "http://$1:8080/healthz" >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  return 1
}

chrome_frames() {
  local chrome probe
  chrome="$(find /opt/chrome-for-testing -maxdepth 3 -type f -name chrome -perm -u+x 2>/dev/null | head -1)"
  [ -n "${chrome}" ] || { printf 'no Chrome for Testing in the image\n' >&2; echo 0; return; }
  "${chrome}" --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage \
    --autoplay-policy=no-user-gesture-required --remote-debugging-port=9222 \
    --user-data-dir="${work}/chrome" about:blank >/dev/null 2>&1 &
  local browser=$!
  sleep 3
  probe="$(node "${script_dir}/lib/cdp-video-probe.mjs" 9222 "$1" "$2" 2>&1 | sed -n 's/^PROBE //p')"
  kill "${browser}" 2>/dev/null
  wait "${browser}" 2>/dev/null
  printf '%s' "${probe}" | jq -r '[.videos[].frames] | max // 0' 2>/dev/null || echo 0
}

in_video_group() { id -nG "${user}" | grep -qw video; }
log_lacks() { ! grep -q "$1" "$2"; }
purged() { ! test -e "${config}" && ! test -e "${prefix}"; }
as_plain() {
  setpriv --reuid=1001 --regid=1001 --clear-groups \
    env -i HOME="${work}/home" PATH=/usr/bin:/bin APPIMAGE_EXTRACT_AND_RUN=1 "$@"
}
plain_foreground() { as_plain "${work}/catcam.AppImage" --print-config | grep -q '^camera = '; }
plain_install_refused() { ! as_plain "${work}/catcam.AppImage" --install >/dev/null 2>&1; }
appimage_installed() {
  test -f /etc/systemd/system/omni-catcam.service && test -f "${config}" &&
    test "$(readlink -f /usr/local/bin/omni-catcam)" = "${prefix}/catcam"
}
installed_copy_refuses() { ! /usr/local/bin/omni-catcam --install >/dev/null 2>&1; }
uninstalled() {
  ! test -e "${prefix}" && ! test -e /etc/systemd/system/omni-catcam.service &&
    ! test -e "${config}" && ! id "${user}" >/dev/null 2>&1
}

printf '=== the .deb ===\n'
dpkg -i "${deb}" </dev/null >"${work}/install.log" 2>&1
check "dpkg installs it with no terminal" grep -q '^Setting up omni-accelerant-catcam' "${work}/install.log"
check "the service user is in the video group" in_video_group
check "the unit is installed and enabled" test -e /etc/systemd/system/multi-user.target.wants/omni-catcam.service
check "postinst wrote the settings file" test -f "${config}"
check "omni-catcam is on PATH" test "$(readlink -f /usr/bin/omni-catcam)" = "${prefix}/catcam"
mkdir -p "${state}" && chown "${user}:" "${state}"

start_service "${work}/idle.log" "${prefix}/catcam" --camera test --inference on --http-port 0
pid=$!
sleep 8
check "idle, it maps nothing from outside the bundle" nothing_outside_bundle "${pid}"
stop_service "${pid}"
check "SIGTERM exits 0" test $? -eq 0
check "no inference failed at shutdown" log_lacks 'inference failed' "${work}/idle.log"

as_service timeout 25 "${prefix}/catcam" --camera "image:${photo}" --inference on --fps 5 --http-port 0 \
  >"${work}/photo.log" 2>&1
check "the bundled model finds a cat in the photo" grep -q 'cat in view' "${work}/photo.log"

ip="$(hostname -I | awk '{print $1}')"
start_service "${work}/stream.log" "${prefix}/catcam" --camera test --inference off
pid=$!
check "the page and /healthz answer on :8080" wait_healthz "${ip}"
frames="$(chrome_frames "http://${ip}:8080/" 20000)"
printf '      Chrome played %s frame(s) over %s\n' "${frames}" "${ip}"
check "headless Chrome plays the stream from the LAN address" test "${frames:-0}" -ge 200
check "with a viewer, it maps nothing from outside the bundle" nothing_outside_bundle "${pid}"
stop_service "${pid}"

echo 'rotate = 180' >>"${config}"
dpkg -i "${deb}" </dev/null >"${work}/upgrade.log" 2>&1
check "an upgrade over an edited settings file needs no terminal" grep -q '^Setting up omni-accelerant-catcam' "${work}/upgrade.log"
check "the upgrade keeps the edit" grep -q '^rotate = 180' "${config}"
dpkg --purge omni-accelerant-catcam >"${work}/purge.log" 2>&1
check "purge removes the settings and ${prefix}" purged

printf '=== the AppImage ===\n'
# No FUSE in a container; the runtime extracts instead and runs the same AppRun.
export APPIMAGE_EXTRACT_AND_RUN=1
install -m 755 "${appimage}" "${work}/catcam.AppImage"
mkdir -p "${work}/home" && chown 1001:1001 "${work}/home" "${work}"
check "it runs in the foreground as a plain user" plain_foreground
check "--install refuses a non-root caller" plain_install_refused
"${work}/catcam.AppImage" --install >"${work}/ai-install.log" 2>&1
check "--install sets up the unit, the settings and the launcher" appimage_installed
check "--install leaves nothing under ${prefix} owned by the builder" test -z "$(find "${prefix}" ! -user root -print -quit)"
mkdir -p "${state}" && chown "${user}:" "${state}"
start_service "${work}/ai-stream.log" "${prefix}/catcam" --camera test --inference off
pid=$!
check "the installed copy answers /healthz" wait_healthz "${ip}"
stop_service "${pid}"
echo 'rotate = 180' >>"${config}"
"${work}/catcam.AppImage" --install >/dev/null 2>&1
check "a second --install keeps the edit" grep -q '^rotate = 180' "${config}"
check "the installed copy refuses --install" installed_copy_refuses
/usr/local/bin/omni-catcam --uninstall --purge >/dev/null 2>&1
check "--uninstall --purge leaves nothing" uninstalled

printf '%s failure(s)\n' "${failures}"
if [ "${failures}" -gt 0 ]; then
  for log in "${work}"/*.log; do
    printf -- '--- %s\n' "$(basename "${log}")"
    grep -vE 'webrtcsink state' "${log}" | tail -8
  done
fi
exit "${failures}"
