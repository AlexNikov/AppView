#!/usr/bin/env bash
# Convenience alias for macOS client setup: xcodegen → pod install → open workspace.
# Must run from any cwd; source of truth is AppView/project.yml.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec bash "$ROOT/Scripts/generate_xcode_project.sh" "$@"
