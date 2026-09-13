#!/usr/bin/env bash
# Install the Bicep CLI on a Linux CI runner.
#
# Shared by both CI definitions. To run the checks locally, install Bicep once
# with a package manager instead; see "Running the checks locally" in README.md.
#
# The standalone binary, not "az bicep install", which manages its own copy on
# its own schedule.
#
# Pinned, because new linter rules would fail the build on unchanged files, and
# because runner images ship an older Bicep without types for some API versions
# used here.
set -euo pipefail

BICEP_VERSION="${BICEP_VERSION:-v0.47.16}"
URL="https://github.com/Azure/bicep/releases/download/${BICEP_VERSION}/bicep-linux-x64"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "==> downloading bicep ${BICEP_VERSION}"
curl -fsSL -o "${workdir}/bicep" "$URL"

# The runner image installs its own Bicep at this same path, so this replaces
# it and the pinned version is the one the checks run.
sudo install -m 0755 "${workdir}/bicep" /usr/local/bin/bicep
bicep --version
