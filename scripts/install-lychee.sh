#!/usr/bin/env bash
# Install the lychee link checker on a Linux CI runner.
#
# Shared by both CI definitions. Tool installation that is genuinely identical
# belongs in a script for the same reason the checks themselves do. To run the
# checks locally, install the tools once with a package manager instead; see
# "Running the checks locally" in README.md.
#
# The version is pinned. "latest" makes the build depend on whatever was
# released this morning, which turns an unrelated upstream change into a broken
# pipeline on a day nobody touched this repository.
set -euo pipefail

# The release tag carries the project name: "lychee-v0.24.2", not "v0.24.2".
LYCHEE_VERSION="${LYCHEE_VERSION:-lychee-v0.24.2}"
URL="https://github.com/lycheeverse/lychee/releases/download/${LYCHEE_VERSION}/lychee-x86_64-unknown-linux-gnu.tar.gz"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "==> downloading lychee ${LYCHEE_VERSION}"
curl -fsSL -o "${workdir}/lychee.tar.gz" "$URL"

# The archive holds the binary inside a directory named after the target
# triple. --strip-components=1 flattens that so the binary lands in workdir.
tar -xzf "${workdir}/lychee.tar.gz" -C "$workdir" --strip-components=1

if [ ! -f "${workdir}/lychee" ]; then
  echo "FAIL: no lychee binary in the archive. Layout may have changed:" >&2
  tar -tzf "${workdir}/lychee.tar.gz" | head -20 >&2
  exit 1
fi

sudo install -m 0755 "${workdir}/lychee" /usr/local/bin/lychee
lychee --version
