#!/usr/bin/env bash
# run_detect_check against a fake app: a photo without two cats, or a blank frame that does not exit 1, fails it.
set -euo pipefail
# shellcheck source=scripts/linux/tests/fixture-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/fixture-common.sh"
root="$(fixture_root)"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin"
fixture_xvfb_stub "$work/bin"
fixture_stub "$work/app" <<'STUB'
[[ $# == 2 && "$1" == --detect-check && -f "$2" ]]
if [[ "$2" == *.png ]]; then
  python3 -I -c 'import struct, sys; d = open(sys.argv[1], "rb").read(); assert d[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", d[16:24]) == (64, 64)' "$2"
  printf 'blank\n' >> "$SEEN"
  exit "${FAKE_BLANK_RC:-1}"
fi
printf 'photo\n' >> "$SEEN"
exit "${FAKE_PHOTO_RC:-0}"
STUB
chmod +x "$work/app"
printf 'jpeg' > "$work/two_cats.jpg"
export PATH="$work/bin:$PATH" SEEN="$work/seen"
failures=0

expect() {
  local want=$1 label=$2 rc=0
  shift 2
  : > "$SEEN"
  env "$@" bash -c 'source "$1/scripts/linux/lib/container-steps.sh"; run_detect_check "$2" "$3"' _ "$root" "$work/app" "$work/two_cats.jpg" > "$work/out" 2>&1 || rc=$?
  if { [[ $want == pass ]] && [[ $rc -ne 0 ]]; } || { [[ $want == fail ]] && [[ $rc -eq 0 ]]; }; then
    echo "FAIL: $label (rc $rc)"; cat "$work/out"; failures=$((failures + 1))
  else
    echo "ok: $label"
  fi
}

expect pass 'two cats pass and the blank frame exits 1' FAKE_PHOTO_RC=0
grep -qx photo "$SEEN" && grep -qx blank "$SEEN" || { echo 'FAIL: both images were not checked'; failures=$((failures + 1)); }
expect fail 'too few cats in the photo fail' FAKE_PHOTO_RC=1
expect fail 'a blank frame that passes fails' FAKE_BLANK_RC=0
expect fail 'a blank frame that crashes fails' FAKE_BLANK_RC=134
[[ $failures -eq 0 ]] || exit 1
echo 'detect check wiring passed'
