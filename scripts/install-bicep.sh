#!/usr/bin/env bash
# Install the Bicep CLI on a Linux CI runner.
#
# Shared by both CI definitions. To run the checks locally, install Bicep once
# with a package manager instead; see "Running the checks locally" in README.md.
#
# The standalone binary rather than "az bicep install". The Azure CLI carries
# its own copy of Bicep and upgrades it on its own schedule, so pinning through
# az means pinning two things and getting whichever version the CLI decided to
# fetch. A single pinned binary is one moving part instead of two, and it does
# not drag in the Azure CLI on a runner that has no Azure credentials anyway.
#
# The version is pinned for the reason spelled out in install-lychee.sh. Bicep's
# linter in particular gains rules between releases, and a new rule arriving
# unannounced fails the build on files that have not changed. The pin also
# matters for type data: hosted runner images ship an older Bicep that has no
# types for some of the API versions used here.
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
