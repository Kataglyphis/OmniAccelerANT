#!/usr/bin/env bash
set -e  # exit on any error

# ------------------------------------------
# Setup Flutter SDK on ARM64 (Linux)
# ------------------------------------------

# Allow passing version as an argument
FLUTTER_VERSION="${1:-3.35.6}"  # default if not provided

echo "📦 Setting up Flutter $FLUTTER_VERSION for x86-64..."

# Download Flutter SDK
wget -q "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

# Extract
tar xf "flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

# Add Flutter to PATH for subsequent GitHub Action steps
echo "$PWD/flutter/bin" >> "$GITHUB_PATH"

# Add Flutter to PATH for current shell session
export PATH="$PWD/flutter/bin:$PATH"

# Verify installation
flutter --version
