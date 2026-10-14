#!/usr/bin/env bash
# Installs the cat cam .deb, AppImage and flatpak the way a user does and checks what each promises; privileged root in :latest.
set -uo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../.." && pwd)"
deb=""
appimage=""
flatpak_bundle=""
photo="${repo_root}/third_party/ANThology/assets/images/cats/Summy&Thundy_compressed.png"

usage() {
  cat <<'EOF'
usage: test-catcam-package.sh [--deb FILE] [--appimage FILE] [--flatpak FILE] [--photo FILE]

Runs as root in a privileged family image (dpkg, a service user, bubblewrap, headless
Chrome). Each check prints PASS or FAIL; the exit code is the number of failures.
  --deb FILE       the .deb (default: this machine's in out/, as package-catcam.sh names it)
  --appimage FILE  the AppImage (default: this machine's in out/)
  --flatpak FILE   the flatpak bundle (default: this machine's in out/)
  --photo FILE     a photo with a cat in it (default: ANThology's Summy & Thundy)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --deb) deb="${2:?--deb needs a file}"; shift 2 ;;
    --appimage) appimage="${2:?--appimage needs a file}"; shift 2 ;;
    --flatpak) flatpak_bundle="${2:?--flatpak needs a file}"; shift 2 ;;
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
flatpaks=("${repo_root}"/out/omni-accelerant-catcam-*-"$(uname -m)".flatpak)
shopt -u nullglob
[ -n "${deb}" ] || deb="${debs[0]:-}"
[ -n "${appimage}" ] || appimage="${appimages[0]:-}"
[ -n "${flatpak_bundle}" ] || flatpak_bundle="${flatpaks[0]:-}"
[ -f "${deb}" ] && [ -f "${appimage}" ] && [ -f "${flatpak_bundle}" ] ||
  { printf 'no .deb, AppImage or flatpak for %s\n' "${deb_arch}" >&2; usage >&2; exit 2; }
printf 'testing %s, %s and %s\n' "$(basename "${deb}")" "$(basename "${appimage}")" "$(basename "${flatpak_bundle}")"
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

# The unit's environment only (its HOME and GST_REGISTRY, systemd's STATE_DIRECTORY), exec'd so $! is the service.
start_service() {
  local log="$1"; shift
  (exec env -i HOME="${state}" GST_REGISTRY="${state}/gst-registry.bin" STATE_DIRECTORY="${state}" PATH=/usr/bin:/bin \
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

# A tab that comes back after its sockets died unnoticed plays again (the owner's stuck tab, 2026-10-14).
tab_returns_after_silence() {
  local chrome result
  chrome="$(find /opt/chrome-for-testing -maxdepth 3 -type f -name chrome -perm -u+x 2>/dev/null | head -1)"
  [ -n "${chrome}" ] || return 1
  python3 "${script_dir}/lib/silencing-proxy.py" 18097 8080 "${work}/silence" &
  local proxy=$!
  "${chrome}" --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage \
    --autoplay-policy=no-user-gesture-required --remote-debugging-port=9223 \
    --user-data-dir="${work}/chrome-return" about:blank >/dev/null 2>&1 &
  local browser=$!
  sleep 3
  result="$(node "${script_dir}/lib/cdp-tab-return.mjs" 9223 "http://127.0.0.1:18097/#/stream" "${work}/silence" 2>&1 | sed -n 's/^RETURN //p')"
  kill "${browser}" "${proxy}" 2>/dev/null
  wait "${browser}" "${proxy}" 2>/dev/null
  printf '      tab return: %s\n' "${result}"
  jq -e '.before > 100 and .back >= 0 and .later > .back' <<<"${result}" >/dev/null || return 1
  return 0
}

wait_cat() {
  local _
  for _ in $(seq 1 120); do
    curl -sf "http://$1:8080/healthz" 2>/dev/null | jq -e '.cat.in_view and .cat.visits >= 1' >/dev/null 2>&1 && return 0
    sleep 0.25
  done
  return 1
}

jpeg_at() {
  curl -sf "http://$1:8080$2" -o "${work}/got.jpg" &&
    test "$(head -c 3 "${work}/got.jpg" | od -An -tx1 | tr -d ' \n')" = ffd8ff
}

# The engine as the browser gets it, gzipped: the packaged zopfli .gz byte for byte, which unzips to the file.
packaged_gz_served() {
  local file="${prefix}/web/$2"
  test -s "${file}.gz" || return 1
  curl -sf -H 'Accept-Encoding: gzip' "http://$1:8080/$2" -o "${work}/served.gz" || return 1
  cmp -s "${work}/served.gz" "${file}.gz" || return 1
  gzip -dc "${file}.gz" | cmp -s - "${file}"
}

# package-catcam.sh leaves out the renderers this build's loader never asks for and the debug maps.
web_pruned() {
  local web="${prefix}/web"
  test -f "${web}/canvaskit/skwasm.wasm" || return 1
  test ! -e "${web}/canvaskit/webparagraph" || return 1
  if [ -n "$(find "${web}" \( -name 'wimp.*' -o -name '*.symbols' \) -print -quit)" ]; then
    return 1
  fi
}

# Every file the server gzips (its types, 1 KiB and up) ships its zopfli .gz; one missing is gzipped at run time.
web_precompressed() {
  local missing
  missing="$(find "${prefix}/web" -type f -size +1023c \( -name '*.js' -o -name '*.mjs' -o -name '*.wasm' \
    -o -name '*.json' -o -name '*.html' -o -name '*.css' -o -name '*.svg' -o -name '*.ttf' -o -name '*.otf' \) \
    ! -exec test -e '{}.gz' ';' -print)"
  if [ -n "${missing}" ]; then
    printf 'no .gz beside: %s\n' "${missing}" >&2
    return 1
  fi
}

# The settings page: a JSON POST of $2 to /settings, then $3 must hold in /healthz and in the state directory.
set_from_page() {
  curl -sf -X POST -H 'content-type: application/json' -d "$2" "http://$1:8080/settings" >/dev/null || return 1
  healthz_holds "$1" "$3" || return 1
  jq -e "$3" "${state}/settings.json" >/dev/null
}

healthz_holds() {
  curl -sf "http://$1:8080/healthz" | jq -e "$2" >/dev/null
}

# Another site's form post is refused, and a bad value refuses the whole post.
settings_refuse_bad_posts() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -d 'rotate=90' "http://$1:8080/settings")"
  [ "${code}" = 415 ] || return 1
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' -d '{"rotate": 180, "score": 3}' "http://$1:8080/settings")"
  [ "${code}" = 400 ] || return 1
  if healthz_holds "$1" '.rotate == 180'; then return 1; fi
}

# Another site's page may not change a setting; the cat cam's own page, by IP and port, may.
own_page_only() {
  local post=(-s -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' -d '{"name": "Paket-Test"}')
  [ "$(curl "${post[@]}" -H 'Origin: http://evil.example' "http://$1:8080/settings")" = 403 ] || return 1
  [ "$(curl "${post[@]}" -H "Origin: http://$1:8080" "http://$1:8080/settings")" = 200 ] || return 1
  return 0
}

# Each arrival keeps its own picture, named by its time as the clips are.
picture_by_arrival() {
  local t
  t="$(curl -sf "http://$1:8080/healthz" | jq -r '.cat.recent[0].arrived')" || return 1
  jpeg_at "$1" "/arrival.jpg?t=${t}" || return 1
  [ "$(curl -s -o /dev/null -w '%{http_code}' "http://$1:8080/arrival.jpg?t=1")" = 404 ] || return 1
  return 0
}

# "Not a cat" over the boxes the photo shows ends the visit, as the page's button does.
not_a_cat_ends_the_visit() {
  local boxes _
  boxes="$(curl -sf "http://$1:8080/healthz" | jq -c '.cat.boxes')" || return 1
  [ "$(jq length <<<"${boxes}")" -ge 1 ] || return 1
  curl -sf -X POST -H 'content-type: application/json' -d "{\"ignore\": ${boxes}}" "http://$1:8080/settings" >/dev/null || return 1
  for _ in $(seq 1 40); do
    healthz_holds "$1" '.cat.in_view == false and .cat.boxes == []' && return 0
    sleep 0.25
  done
  return 1
}

# Watched again, the photo's cat cannot start a visit: nothing in it moves, and its start is $2 s back.
still_cat_starts_no_visit() {
  local visits
  while [ $(($(date +%s) - $2)) -lt 20 ]; do sleep 1; done
  visits="$(curl -sf "http://$1:8080/healthz" | jq '.cat.visits')" || return 1
  curl -sf -X POST -H 'content-type: application/json' -d '{"ignore": []}' "http://$1:8080/settings" >/dev/null || return 1
  sleep 12
  healthz_holds "$1" ".cat.in_view == false and .cat.visits == ${visits}" || return 1
  return 0
}

# The build /healthz names is the installed package's: package-catcam.sh stamps it into the binary.
names_its_package() {
  local v
  v="$(dpkg-query -W -f='${Version}' omni-accelerant-catcam)" || return 1
  curl -sf "http://$1:8080/healthz" | jq -e --arg v "${v}" '.version | startswith($v)' >/dev/null || return 1
  return 0
}

# Only root and the service's group read the settings, which a webhook secret may be part of.
config_private() {
  [ "$(stat -c '%a %U %G' "${config}")" = "640 root $(id -gn "${user}")" ] || return 1
  return 0
}

# An older version's world-readable settings file is made private at the next setup, its content kept.
old_config_tightened() {
  chmod 644 "${config}" && chgrp root "${config}" || return 1
  cp "${config}" "${work}/config.before"
  "${prefix}/libexec/catcam-install" setup || return 1
  config_private || return 1
  cmp -s "${config}" "${work}/config.before" || return 1
  return 0
}

# A webhook stand-in on loopback that appends every POST body to $2; exec, so $! is python and kill reaches it.
webhook_receiver() {
  exec python3 -c '
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        open(sys.argv[2], "ab").write(self.rfile.read(int(self.headers["content-length"])) + b"\n")
        self.send_response(204); self.end_headers()
    def log_message(self, *args): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
' "$1" "$2" >/dev/null 2>&1
}

visit_remembered() {
  curl -sf "http://$1:8080/healthz" | jq -e '.cat.visits >= 1 and .cat.last_seen != null' >/dev/null
}

# The live service has seen the cat for $2 s of its current visit; up to 10 s.
seen_for() {
  local _
  for _ in $(seq 1 40); do
    curl -sf "http://$1:8080/healthz" 2>/dev/null \
      | jq -e --argjson s "$2" '.cat.last_seen - .cat.recent[0].arrived >= $s' >/dev/null 2>&1 && return 0
    sleep 0.25
  done
  return 1
}

# The arrival's clip, recorded 7 s past the arrival and then encoded, is named in /healthz; up to 30 s.
clip_ready() {
  local _
  for _ in $(seq 1 120); do
    curl -sf "http://$1:8080/healthz" 2>/dev/null \
      | jq -e '.cat.clip != null and .cat.clip == .cat.recent[0].arrived and .cat.clips[0] == .cat.clip' >/dev/null 2>&1 && return 0
    sleep 0.25
  done
  return 1
}

# $2 serves an MP4 (its first box is ftyp) and answers a byte range with 206, which Safari's <video> needs.
mp4_at() {
  curl -sf "http://$1:8080$2" -o "${work}/clip.mp4" || return 1
  [ "$(dd if="${work}/clip.mp4" bs=1 skip=4 count=4 2>/dev/null)" = ftyp ] || return 1
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H 'Range: bytes=0-99' "http://$1:8080$2")" = 206 ] || return 1
  return 0
}

# /arrival.mp4?t= serves the clip of that arrival, and 404 for one it never recorded.
clip_by_arrival() {
  local t
  t="$(curl -sf "http://$1:8080/healthz" | jq -r '.cat.clip')" || return 1
  [ "$(curl -s -o /dev/null -w '%{http_code}' "http://$1:8080/arrival.mp4?t=${t}")" = 200 ] || return 1
  [ "$(curl -s -o /dev/null -w '%{http_code}' "http://$1:8080/arrival.mp4?t=1")" = 404 ] || return 1
  return 0
}

visit_closed() {
  curl -sf "http://$1:8080/healthz" | jq -e --argjson s "$2" '.cat.recent[0].stayed_s >= $s' >/dev/null
}

webhook_got_arrival() {
  webhook_got arrived "$1"
}

# The receiver logged a "$1" event; up to 10 s.
webhook_got() {
  local _
  for _ in $(seq 1 40); do
    grep -q "\"event\":\"$1\"" "$2" 2>/dev/null && return 0
    sleep 0.25
  done
  return 1
}

# Every setting the shipped catcam.toml documents, uncommented: an unknown key is an error, so this reads them all.
template_keys_parse() {
  sed -E 's/^# ([a-z_]+ = )/\1/' "${prefix}/share/omni-accelerant-catcam/catcam.toml" >"${work}/all-keys.toml" &&
    test "$(grep -cE '^[a-z_]+ = ' "${work}/all-keys.toml")" -ge 15 &&
    "${prefix}/catcam" --config "${work}/all-keys.toml" --print-config >/dev/null
}

# The unit loads without warnings and keeps its sandbox: systemd-analyze rates it 1.8 (2026-10-12).
unit_verifies() { test -z "$(systemd-analyze verify "$1" 2>&1)"; }
unit_sandboxed() { systemd-analyze security --offline=true --threshold=25 "$1" >/dev/null 2>&1; }

in_video_group() { id -nG "${user}" | grep -qw video; }
log_lacks() { ! grep -q "$1" "$2"; }
purged() { ! test -e "${config}" && ! test -e "${prefix}"; }
unit_masked() { test "$(readlink /etc/systemd/system/omni-catcam.service)" = /dev/null; }
unit_enabled_unmasked() {
  ! unit_masked && test -e /etc/systemd/system/multi-user.target.wants/omni-catcam.service
}
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
flatpak_gone() { ! flatpak info --system "$1" >/dev/null 2>&1; }
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
check "only root and the service's group read it" config_private
check "an older version's world-readable settings file is made private" old_config_tightened
check "omni-catcam is on PATH" test "$(readlink -f /usr/bin/omni-catcam)" = "${prefix}/catcam"
check "every setting catcam.toml documents is one the service reads" template_keys_parse
check "the unit loads without a warning" unit_verifies /usr/lib/systemd/system/omni-catcam.service
check "the unit keeps its sandbox (exposure 2.5 or less)" unit_sandboxed /usr/lib/systemd/system/omni-catcam.service
check "the unit brings the service back whatever ended it" grep -qx 'Restart=always' /usr/lib/systemd/system/omni-catcam.service
check "the unit starts once the clock is set" grep -qE '^After=.* time-sync\.target' /usr/lib/systemd/system/omni-catcam.service
mkdir -p "${state}" && chown "${user}:" "${state}"

start_service "${work}/idle.log" "${prefix}/catcam" --camera test --inference on --http-port 0
pid=$!
sleep 8
check "idle, it maps nothing from outside the bundle" nothing_outside_bundle "${pid}"
stop_service "${pid}"
check "SIGTERM exits 0" test $? -eq 0
check "no inference failed at shutdown" log_lacks 'inference failed' "${work}/idle.log"

ip="$(hostname -I | awk '{print $1}')"
webhook_receiver 18999 "${work}/webhook.jsonl" &
receiver=$!
start_service "${work}/photo.log" "${prefix}/catcam" --camera "image:${photo}" --inference on --fps 5 \
  --notify-url "http://127.0.0.1:18999/api/webhook/test"
pid=$!
check "/healthz reports the cat in the photo as a visit" wait_cat "${ip}"
check "/healthz says ok while the camera delivers frames" healthz_holds "${ip}" '.ok and .problem == null and .frame_age_s <= 2 and .model_age_s <= 10'
check "/healthz names the installed package's version as its build" names_its_package "${ip}"
check "/snapshot.jpg serves the boxed frame as a JPEG" jpeg_at "${ip}" /snapshot.jpg
check "the arrival is POSTed to notify_url as JSON" webhook_got_arrival "${work}/webhook.jsonl"
check "/arrival.jpg serves the frame the arrival was seen on" jpeg_at "${ip}" /arrival.jpg
check "/arrival.jpg?t= serves that arrival's picture and no other" picture_by_arrival "${ip}"
check "the visit log times the stay while the cat is in view" seen_for "${ip}" 2
check "the arrival's clip is encoded, named in /healthz and first in its list" clip_ready "${ip}"
check "/arrival.mp4 serves it as an MP4 and answers a byte range" mp4_at "${ip}" /arrival.mp4
check "/arrival.mp4?t= serves that arrival's clip and no other" clip_by_arrival "${ip}"
check "the finished clip is POSTed to notify_url as JSON" webhook_got clip "${work}/webhook.jsonl"
check "the page's rotate button turns the picture and the setting is kept" set_from_page "${ip}" '{"rotate": 90}' '.rotate == 90'
check "the settings page sets the detection score and the name" set_from_page "${ip}" '{"score": 0.6, "name": "Paket-Test"}' '.score == 0.6 and .name == "Paket-Test"'
check "/settings refuses a form post and a bad value changes nothing" settings_refuse_bad_posts "${ip}"
check "/settings refuses another site's page and takes the cat cam's own" own_page_only "${ip}"
stop_service "${pid}"
kill "${receiver}" 2>/dev/null
check "the bundled model finds a cat in the photo" grep -q 'cat in view' "${work}/photo.log"

start_service "${work}/stream.log" "${prefix}/catcam" --camera test --inference off
pid=$!
check "the page and /healthz answer on :8080" wait_healthz "${ip}"
check "main.dart.wasm goes out as the packaged zopfli .gz" packaged_gz_served "${ip}" main.dart.wasm
check "the web build ships without the renderers and debug maps no browser fetches" web_pruned
check "every file the server gzips ships its zopfli .gz" web_precompressed
check "a restart keeps the visit the photo counted" visit_remembered "${ip}"
check "a restart closes the visit the stop cut short, at its last sighting" visit_closed "${ip}" 2
check "a restart keeps the arrival frame" jpeg_at "${ip}" /arrival.jpg
check "a restart keeps the arrival clip" mp4_at "${ip}" /arrival.mp4
check "a restart keeps the rotation, score and name the page set" healthz_holds "${ip}" '.rotate == 90 and .score == 0.6 and .name == "Paket-Test"'
check "the page turns the picture upright again" set_from_page "${ip}" '{"rotate": 0}' '.rotate == 0'
check "the page sets the detection score back, below the photo's cat" set_from_page "${ip}" '{"score": 0.25}' '.score == 0.25'
frames="$(chrome_frames "http://${ip}:8080/" 20000)"
printf '      Chrome played %s frame(s) over %s\n' "${frames}" "${ip}"
check "headless Chrome plays the stream from the LAN address" test "${frames:-0}" -ge 200
check "with a viewer, it maps nothing from outside the bundle" nothing_outside_bundle "${pid}"
check "a tab back after its connections went silent plays again" tab_returns_after_silence
stop_service "${pid}"

started="$(date +%s)"
start_service "${work}/ignore.log" "${prefix}/catcam" --camera "image:${photo}" --inference on --fps 5
pid=$!
check "the photo's cat arrives as the camera starts" wait_cat "${ip}"
check "marking it not a cat ends its visit" not_a_cat_ends_the_visit "${ip}"
check "watched again, a cat that does not move starts no visit" still_cat_starts_no_visit "${ip}" "${started}"
stop_service "${pid}"

echo 'rotate = 180' >>"${config}"
dpkg -i "${deb}" </dev/null >"${work}/upgrade.log" 2>&1
check "an upgrade over an edited settings file needs no terminal" grep -q '^Setting up omni-accelerant-catcam' "${work}/upgrade.log"
check "the upgrade keeps the edit" grep -q '^rotate = 180' "${config}"
dpkg -r omni-accelerant-catcam >"${work}/remove.log" 2>&1
check "remove masks the unit, so nothing starts it" unit_masked
dpkg -i "${deb}" </dev/null >"${work}/reinstall.log" 2>&1
check "a reinstall after remove unmasks and enables it again" unit_enabled_unmasked
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

printf '=== the flatpak ===\n'
# A system install: root needs no D-Bus for it, and a user install does.
flatpak_id=org.kataglyphis.omni-accelerant-catcam
autostart_entry="${HOME}/.config/autostart/${flatpak_id}.desktop"
flatpak install --system -y --noninteractive "${flatpak_bundle}" >"${work}/fp-install.log" 2>&1
check "flatpak installs it" flatpak info --system "${flatpak_id}"
flatpak run --command=omni-catcam "${flatpak_id}" --camera test --inference off >"${work}/fp-stream.log" 2>&1 &
pid=$!
check "in its sandbox it answers /healthz" wait_healthz "${ip}"
check "it keeps the cat's visits in its own state directory" grep -q "state: .*/\.var/app/${flatpak_id}/" "${work}/fp-stream.log"
frames="$(chrome_frames "http://${ip}:8080/" 20000)"
printf '      Chrome played %s frame(s) over %s\n' "${frames}" "${ip}"
check "headless Chrome plays the sandboxed stream from the LAN address" test "${frames:-0}" -ge 200
check "its first start set up the sign-in autostart" grep -q "^Exec=flatpak run --command=omni-catcam ${flatpak_id}$" "${autostart_entry}"
kill "${pid}" 2>/dev/null
flatpak kill "${flatpak_id}" >/dev/null 2>&1
wait "${pid}" 2>/dev/null
flatpak run --command=omni-catcam "${flatpak_id}" --autostart off >/dev/null 2>&1
check "--autostart off removes the sign-in entry" test ! -e "${autostart_entry}"
flatpak uninstall --system -y --noninteractive "${flatpak_id}" >/dev/null 2>&1
check "flatpak uninstall leaves no app" flatpak_gone "${flatpak_id}"

printf '%s failure(s)\n' "${failures}"
if [ "${failures}" -gt 0 ]; then
  for log in "${work}"/*.log; do
    printf -- '--- %s\n' "$(basename "${log}")"
    grep -vE 'webrtcsink state' "${log}" | tail -8
  done
fi
exit "${failures}"
