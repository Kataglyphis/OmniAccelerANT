#!/usr/bin/env bash
# The packager's lock reader on fixture locks; not covered: a finished package, which test-observant-fixture-lock.sh proves in web.yml.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/linux/observant/lib/locked-model.sh
source "$root/scripts/linux/observant/lib/locked-model.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

cat > "$work/other.lock" <<'LOCK'
# 00  commented.onnx  https://example.invalid/commented.onnx
00  other.LICENSE  https://example.invalid/other.LICENSE
00  other.onnx     https://example.invalid/other.onnx
00  second.onnx    https://example.invalid/second.onnx
LOCK
[ "$(locked_model_name "$work/other.lock")" = other.onnx ] || { echo 'FAIL: the first .onnx row names the model' >&2; exit 1; }

printf '00  other.LICENSE  https://example.invalid/other.LICENSE\n' > "$work/none.lock"
if locked_model_name "$work/none.lock" 2>/dev/null; then
  echo 'FAIL: a lock without a model must fail' >&2
  exit 1
fi

caller="$root/scripts/linux/observant/package-observant.sh"
grep -qF -e 'model_name="$(locked_model_name "${models_lock}")"' "$caller" || { echo 'FAIL: the packager does not ask the reader' >&2; exit 1; }
echo 'Locked model name passed'
