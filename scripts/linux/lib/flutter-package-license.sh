#!/usr/bin/env bash
# Copyright (c) 2026 Kataglyphis
# SPDX-License-Identifier: MIT
# Checks this app's full license in Flutter artifacts, not the completeness of native dependency notices.

verify_flutter_package_license() {
  local artifact="${1:?artifact required}" pattern="${2:?license member pattern required}" verifier
  verifier="$(antfrastructure_path linux/scripts/verify_package_license.py)" || return $?
  python3 "$verifier" "$artifact" --require "${pattern}=${KATAGLYPHIS_REPO_ROOT}/LICENSE"
}

verify_flutter_appimage_license() {
  local artifact="${1:?artifact required}" arch="${2:?arch required}" entry="${3:?license entry required}" verifier
  verifier="$(antfrastructure_path linux/scripts/06-packaging/verify-native-appimage-license.sh)" || return $?
  bash "$verifier" "$artifact" "$arch" "$entry" "${KATAGLYPHIS_REPO_ROOT}/LICENSE"
}
