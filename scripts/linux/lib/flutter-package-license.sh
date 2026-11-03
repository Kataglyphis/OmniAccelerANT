#!/usr/bin/env bash
# Copyright (c) 2026 Kataglyphis
# SPDX-License-Identifier: MIT
# Checks this app's license and its third-party inventory in Flutter artifacts; coverage of static code is not checked.

# <notices-member>: every shipped inventory asset, as "<member>=<repo file>" beside the given NOTICES member.
third_party_license_requires() {
  local notices="${1:?notices member required}" prefix assets asset
  prefix="${notices%NOTICES*}"
  assets="$(python3 "${KATAGLYPHIS_REPO_ROOT}/scripts/licenses/generate-third-party-licenses.py" --list-assets)" || return $?
  [[ -n "$assets" ]] || { echo "Error: the third-party license inventory lists no assets" >&2; return 1; }
  while IFS= read -r asset; do
    printf '%s\n' "${prefix}${asset}=${KATAGLYPHIS_REPO_ROOT}/${asset}"
  done <<< "$assets"
}

# flutter_license_rules <member>: the project LICENSE rule first, then each third-party text, as MEMBER=FILE lines.
flutter_license_rules() {
  local requires
  requires="$(third_party_license_requires "$1")" || return $?
  printf '%s\n%s\n' "$1=${KATAGLYPHIS_REPO_ROOT}/LICENSE" "$requires"
}

# for_each_license_rule <member> <callback> [args...]: stops at the first callback failure and returns its status.
for_each_license_rule() {
  local rules rule callback="$2" member="$1"
  shift 2
  rules="$(flutter_license_rules "$member")" || return $?
  while IFS= read -r rule; do
    "$callback" "$rule" "$@" || return $?
  done <<< "$rules"
}

_append_license_require() { _license_args+=(--require "$1"); }

_verify_appimage_rule() { bash "$2" "$3" "$4" "${1%%=*}" "${1#*=}"; }

verify_flutter_package_license() {
  local artifact="${1:?artifact required}" pattern="${2:?license member pattern required}" verifier
  local -a _license_args=()
  verifier="$(antfrastructure_path linux/scripts/verify_package_license.py)" || return $?
  for_each_license_rule "$pattern" _append_license_require || return $?
  python3 "$verifier" "$artifact" "${_license_args[@]}"
}

verify_flutter_appimage_license() {
  local artifact="${1:?artifact required}" arch="${2:?arch required}" entry="${3:?license entry required}" verifier
  verifier="$(antfrastructure_path linux/scripts/06-packaging/verify-native-appimage-license.sh)" || return $?
  for_each_license_rule "$entry" _verify_appimage_rule "$verifier" "$artifact" "$arch"
}

# <payload> <linux|windows|android>: every shipped native binary needs an entry in the inventory's native table.
check_native_license_coverage() {
  local payload="${1:?payload required}" platform="${2:?platform required}"
  python3 "${KATAGLYPHIS_REPO_ROOT}/scripts/licenses/check-native-coverage.py" --platform "$platform" "$payload"
}
