#!/usr/bin/env bash
# Install tflint on a Linux CI runner.
#
# Shared by both CI definitions. To run the checks locally, install tflint once
# with a package manager instead; see "Running the checks locally" in README.md.
#
# Upstream offers an install script fetched from the master branch and piped to
# a shell. That is two problems in one line: the build depends on whatever is on
# master this morning, and it runs unreviewed code as part of the pipeline. A
# pinned release asset avoids both, and matches how the other tools here are
# installed.
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
