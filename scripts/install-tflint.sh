#!/usr/bin/env bash
# Install tflint on a Linux CI runner.
#
# Shared by both CI definitions. To run the checks locally, install tflint once
# with a package manager instead; see "Running the checks locally" in README.md.
#
# A pinned release asset, not upstream's install script piped from master,
# which would be unpinned and unreviewed.
set -euo pipefail

TFLINT_VERSION="${TFLINT_VERSION:-v0.64.0}"
URL="https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/tflint_linux_amd64.zip"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "==> downloading tflint ${TFLINT_VERSION}"
curl -fsSL -o "${workdir}/tflint.zip" "$URL"
unzip -q "${workdir}/tflint.zip" -d "$workdir"

sudo install -m 0755 "${workdir}/tflint" /usr/local/bin/tflint
tflint --version
