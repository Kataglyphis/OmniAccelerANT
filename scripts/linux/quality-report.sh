#!/usr/bin/env bash
# The hub's quality-report.sh on this checkout; it measures and grades, and builds or tests nothing.
exec bash "$(dirname "$0")/../../third_party/ANTfrastructure/linux/scripts/quality-report.sh" --root "$(dirname "$0")/../.." "$@"
