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

verify_flutter_package_license() {
  local artifact="${1:?artifact required}" pattern="${2:?license member pattern required}" verifier requires rule
  local -a args=(--require "${pattern}=${KATAGLYPHIS_REPO_ROOT}/LICENSE")
  verifier="$(antfrastructure_path linux/scripts/verify_package_license.py)" || return $?
  requires="$(third_party_license_requires "$pattern")" || return $?
  while IFS= read -r rule; do args+=(--require "$rule"); done <<< "$requires"
  python3 "$verifier" "$artifact" "${args[@]}"
}

verify_flutter_appimage_license() {
  local artifact="${1:?artifact required}" arch="${2:?arch required}" entry="${3:?license entry required}" verifier requires rule
  verifier="$(antfrastructure_path linux/scripts/06-packaging/verify-native-appimage-license.sh)" || return $?
  bash "$verifier" "$artifact" "$arch" "$entry" "${KATAGLYPHIS_REPO_ROOT}/LICENSE" || return $?
  requires="$(third_party_license_requires "$entry")" || return $?
  while IFS= read -r rule; do
    bash "$verifier" "$artifact" "$arch" "${rule%%=*}" "${rule#*=}" || return $?
  done <<< "$requires"
}

# <payload> <linux|windows|android>: every shipped native binary needs an entry in the inventory's native table.
check_native_license_coverage() {
  local payload="${1:?payload required}" platform="${2:?platform required}"
  python3 "${KATAGLYPHIS_REPO_ROOT}/scripts/licenses/check-native-coverage.py" --platform "$platform" "$payload"
}
