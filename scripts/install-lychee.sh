#!/usr/bin/env bash
# Install the lychee link checker.
#
# Shared by both CI definitions. It lived inline in each of them until the
# first real pipeline run failed, at which point the same bug needed fixing in
# two places. Tool installation that is genuinely identical belongs in a script
# for the same reason the checks themselves do.
#
# Two things this gets right that the inline version did not:
#
# 1. The release archive extracts into a directory named after the target
#    triple, not to the current directory. "mv lychee" therefore had nothing to
#    move, and the failure message named the missing file rather than the cause.
#    --strip-components=1 flattens it.
#
# 2. The version is pinned. "latest" means the build depends on whatever was
#    released this morning, which turns an unrelated upstream change into a
#    broken pipeline on a day nobody touched this repository.
set -euo pipefail

# The release tag is prefixed with the project name: "lychee-v0.24.2", not
# "v0.24.2". Getting that wrong produces a 404 and curl exit 22, which reports
# an HTTP error rather than naming the tag.
LYCHEE_VERSION="${LYCHEE_VERSION:-lychee-v0.24.2}"
TARGET="x86_64-unknown-linux-gnu"
URL="https://github.com/lycheeverse/lychee/releases/download/${LYCHEE_VERSION}/lychee-${TARGET}.tar.gz"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "==> downloading lychee ${LYCHEE_VERSION}"
curl -fsSL -o "${workdir}/lychee.tar.gz" "$URL"

echo "==> extracting"
tar -xzf "${workdir}/lychee.tar.gz" -C "$workdir" --strip-components=1

if [ ! -f "${workdir}/lychee" ]; then
  echo "FAIL: no lychee binary in the archive. Layout may have changed:" >&2
  tar -tzf "${workdir}/lychee.tar.gz" | head -20 >&2
  exit 1
fi

sudo mv "${workdir}/lychee" /usr/local/bin/lychee
sudo chmod +x /usr/local/bin/lychee
lychee --version
