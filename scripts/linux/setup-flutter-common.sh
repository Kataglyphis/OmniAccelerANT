#!/usr/bin/env bash
set -e  # exit on any error
# NOTE: Keep LF line endings for Linux shells.

setup_flutter() {
	local arch_label="$1"
	local flutter_version="$2"
	local archive="flutter_linux_${flutter_version}-stable.tar.xz"

	echo "ðŸ“¦ Setting up Flutter ${flutter_version} for ${arch_label}..."

	# Download Flutter SDK
	wget -q "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${archive}"

	# Extract to /opt for a cleaner setup
	sudo mkdir -p /opt
	sudo tar xf "${archive}" -C /opt

	# Remove downloaded archive to keep things clean
	rm -f "${archive}"

	# Add Flutter to PATH permanently for the current user
	if [ -f "$HOME/.bashrc" ]; then
		grep -q '/opt/flutter/bin' "$HOME/.bashrc" || echo 'export PATH="/opt/flutter/bin:$PATH"' >> "$HOME/.bashrc"
	elif [ -f "$HOME/.profile" ]; then
		grep -q '/opt/flutter/bin' "$HOME/.profile" || echo 'export PATH="/opt/flutter/bin:$PATH"' >> "$HOME/.profile"
	else
		echo 'export PATH="/opt/flutter/bin:$PATH"' >> "$HOME/.profile"
	fi

	# Add Flutter to PATH for subsequent GitHub Action steps
	# echo "/opt/flutter/bin" >> "$GITHUB_PATH"

	# Add Flutter to PATH for current shell session
	export PATH="/opt/flutter/bin:$PATH"

	# Clean up unnecessary cache
	sudo rm -rf "/opt/flutter/bin/cache"

	# Verify installation
	flutter --version
}
