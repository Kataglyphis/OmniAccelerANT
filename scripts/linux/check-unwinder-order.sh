#!/usr/bin/env bash
# Fails an executable whose load order puts another _Unwind_RaiseException ahead of libgcc_s. See docs/source/platforms.md § Two unwinders
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: check-unwinder-order.sh <executable>" >&2
  exit 2
fi
exe="$1"
if [[ ! -f "$exe" ]]; then
  echo "Error: no executable at ${exe}" >&2
  exit 1
fi
for tool in ldd readelf; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "Error: ${tool} is required" >&2
    exit 2
  fi
done

listing="$(ldd "$exe" 2>&1)" || {
  printf 'Error: ldd failed on %s:\n%s\n' "$exe" "$listing" >&2
  exit 1
}
# An unresolved library hides its symbols, so the order below would be graded on a partial list.
if [[ "$listing" == *"not found"* ]]; then
  printf 'Error: %s has unresolved libraries:\n%s\n' "$exe" "$(printf '%s\n' "$listing" | awk '/not found/')" >&2
  exit 1
fi

first=""
# ldd lists the objects in load order, which is the order the global symbol lookup searches.
while read -r name path; do
  if readelf --dyn-syms -W "$path" | awk '$7 != "UND" && $8 ~ /^_Unwind_RaiseException(@|$)/ {hit = 1} END {exit !hit}'; then
    first="$name"
    break
  fi
done < <(printf '%s\n' "$listing" | awk '$2 == "=>" && $3 ~ /^\// {print $1, $3}')

case "$first" in
  libgcc_s.so*)
    echo "unwinder order: ${first} defines _Unwind_RaiseException first for ${exe##*/}"
    ;;
  "")
    echo "Error: nothing in ${exe}'s load order defines _Unwind_RaiseException" >&2
    exit 1
    ;;
  *)
    echo "Error: ${first} defines _Unwind_RaiseException ahead of libgcc_s.so.1 in ${exe}'s load order," >&2
    echo "       so the first C++ throw or Rust panic in the app aborts. Link gcc_s before flutter in linux/CMakeLists.txt." >&2
    exit 1
    ;;
esac
