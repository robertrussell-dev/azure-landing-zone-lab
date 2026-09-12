#!/usr/bin/env bash
# Install the Bicep CLI.
#
# Shared by both CI definitions, for the same reason install-lychee.sh is.
#
# The standalone binary rather than "az bicep install". The Azure CLI carries
# its own copy of Bicep and upgrades it on its own schedule, so pinning through
# az means pinning two things and getting whichever version the CLI decided to
# fetch. A single pinned binary is one moving part instead of two, and it does
# not drag in the Azure CLI on a runner that has no Azure credentials anyway.
#
# The version is pinned for the reason spelled out in install-lychee.sh: latest
# turns an unrelated upstream release into a broken pipeline on a day nobody
# touched this repository. Bicep's linter in particular gains rules between
# releases, and a new rule arriving unannounced fails the build on files that
# have not changed.
set -euo pipefail

BICEP_VERSION="${BICEP_VERSION:-v0.47.16}"
URL="https://github.com/Azure/bicep/releases/download/${BICEP_VERSION}/bicep-linux-x64"

echo "==> downloading bicep ${BICEP_VERSION}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

curl -fsSL -o "${workdir}/bicep" "$URL"
chmod +x "${workdir}/bicep"

sudo mv "${workdir}/bicep" /usr/local/bin/bicep
bicep --version
