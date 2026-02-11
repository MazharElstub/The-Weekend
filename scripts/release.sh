#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <marketing_version> <build_number>"
  echo "Example: $0 1.1.0 5"
  exit 1
fi

MARKETING_VERSION="$1"
BUILD_NUMBER="$2"

if [[ ! "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: marketing_version must be semantic version format MAJOR.MINOR.PATCH (for example 1.2.0)."
  exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: build_number must be an integer."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "Error: xcrun is required to run agvtool."
  exit 1
fi

echo "Setting MARKETING_VERSION to $MARKETING_VERSION..."
xcrun agvtool new-marketing-version "$MARKETING_VERSION" >/dev/null

echo "Setting CURRENT_PROJECT_VERSION to $BUILD_NUMBER..."
xcrun agvtool new-version -all "$BUILD_NUMBER" >/dev/null

echo "Version update complete."
echo "Next steps:"
echo "1. Update CHANGELOG.md"
echo "2. Commit: git commit -am \"chore: release v$MARKETING_VERSION\""
echo "3. Tag: git tag v$MARKETING_VERSION"
echo "4. Push: git push origin main --tags"
