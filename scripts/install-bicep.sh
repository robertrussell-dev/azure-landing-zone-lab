#!/usr/bin/env bash
# Install the Bicep CLI.
#
# Shared by both CI definitions and by the Bicep checks, which call it when the
# binary is missing.
#
# The standalone binary rather than "az bicep install". The Azure CLI carries
# its own copy of Bicep and upgrades it on its own schedule, so pinning through
# az means pinning two things and getting whichever version the CLI decided to
# fetch. A single pinned binary is one moving part instead of two, and it does
# not drag in the Azure CLI on a runner that has no Azure credentials anyway.
#
# The version is pinned for the reason spelled out in install-lychee.sh. Bicep's
# linter in particular gains rules between releases, and a new rule arriving
# unannounced fails the build on files that have not changed.
set -euo pipefail

. "$(dirname "$0")/tools.sh"

BICEP_VERSION="${BICEP_VERSION:-v0.47.16}"

tools_platform

# A bare executable rather than an archive, named by platform and architecture.
case "$tools_os" in
  linux)   asset="bicep-linux-${tools_arch/amd64/x64}";   binary="bicep" ;;
  darwin)  asset="bicep-osx-${tools_arch/amd64/x64}";     binary="bicep" ;;
  windows) asset="bicep-win-${tools_arch/amd64/x64}.exe"; binary="bicep.exe" ;;
esac

if tools_installed "$binary" "${BICEP_VERSION#v}"; then
  echo "==> bicep ${BICEP_VERSION} already installed"
  exit 0
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "==> downloading bicep ${BICEP_VERSION} (${asset})"
curl -fsSL -o "${workdir}/${binary}" \
  "https://github.com/Azure/bicep/releases/download/${BICEP_VERSION}/${asset}"

tools_install "${workdir}/${binary}" "$binary"

"${tools_bin_dir}/${binary}" --version
