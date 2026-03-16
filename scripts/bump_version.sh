#!/bin/bash

# Bump version across all project files.
# Usage: ./scripts/bump_version.sh <new_version> [build_number]
#
# This script updates version numbers in:
# - pubspec.yaml (Flutter version + MSIX version)
# - Debian control file
# - Rust Cargokit build files

set -e

if [ -z "$1" ]; then
  echo "Usage: ./scripts/bump_version.sh <new_version> [build_number]"
  echo "Example: ./scripts/bump_version.sh 1.2.0"
  echo "Example: ./scripts/bump_version.sh 1.2.0 2"
  exit 1
fi

NEW_VERSION=$1
BUILD_NUMBER=${2:-1}  # Default build number to 1 if not provided

echo "Bumping version to $NEW_VERSION+$BUILD_NUMBER..."

# Cross-platform sed -i wrapper (handles macOS vs Linux differences)
# Usage: sed_inplace 'pattern' file
sed_inplace() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS requires an empty string argument after -i
    sed -i '' -E "$1" "$2"
  else
    # Linux (GNU sed) works with -i directly
    sed -i -E "$1" "$2"
  fi
}

# 1. Update main pubspec.yaml
if [ -f "pubspec.yaml" ]; then
  echo "Updating pubspec.yaml..."
  # Update the main version
  sed_inplace "s/^version: .*/version: $NEW_VERSION+$BUILD_NUMBER/" pubspec.yaml
  # Update the msix_version (Windows requirement: must be X.Y.Z.0)
  sed_inplace "s/^[[:space:]]*msix_version:.*/  msix_version: $NEW_VERSION.0/" pubspec.yaml
fi

# 2. Update Debian control file (only if writable)
if [ -w "out/deb/DEBIAN/control" ]; then
  echo "Updating out/deb/DEBIAN/control..."
  sed_inplace "s/^Version: .*/Version: $NEW_VERSION/" out/deb/DEBIAN/control
fi

# 3. Update Rust Cargokit files (if applicable)
if [ -f "rust_builder/cargokit/run_build_tool.sh" ]; then
  echo "Updating rust_builder/cargokit/run_build_tool.sh..."
  sed_inplace "s/version: [0-9]+\.[0-9]+\.[0-9]+/version: $NEW_VERSION/" rust_builder/cargokit/run_build_tool.sh
fi

if [ -f "rust_builder/cargokit/build_tool/pubspec.yaml" ]; then
  echo "Updating rust_builder/cargokit/build_tool/pubspec.yaml..."
  sed_inplace "s/^version: .*/version: $NEW_VERSION/" rust_builder/cargokit/build_tool/pubspec.yaml
fi

if [ -f "rust_builder/cargokit/run_build_tool.cmd" ]; then
  echo "Updating rust_builder/cargokit/run_build_tool.cmd..."
  sed_inplace "s/version: [0-9]+\.[0-9]+\.[0-9]+/version: $NEW_VERSION/" rust_builder/cargokit/run_build_tool.cmd
fi

echo ""
echo "Version bumped successfully to $NEW_VERSION+$BUILD_NUMBER!"
echo "Please review the changes using 'git diff' before committing."
