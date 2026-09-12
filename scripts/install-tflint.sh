#!/usr/bin/env bash
# Install tflint.
#
# Shared by both CI definitions and by lint-terraform.sh, which calls it when
# the binary is missing.
#
# Upstream offers an install script fetched from the master branch and piped to
# a shell. That is two problems in one line: the build depends on whatever is on
# master this morning, and it runs unreviewed code as part of the pipeline. A
# pinned release asset avoids both, and matches how every other tool here is
# installed.
#
# tflint gains rules between releases in the same way Bicep's linter does, so
# the version is pinned to keep a new rule from failing a build on files that
# have not changed.
set -euo pipefail

. "$(dirname "$0")/tools.sh"

TFLINT_VERSION="${TFLINT_VERSION:-v0.64.0}"

tools_platform

# tflint names its assets with the same os and arch vocabulary tools_platform
# uses, so no translation is needed.
archive="tflint_${tools_os}_${tools_arch}.zip"
binary="tflint"
[ "$tools_os" = "windows" ] && binary="tflint.exe"

if tools_installed "$binary" "${TFLINT_VERSION#v}"; then
  echo "==> tflint ${TFLINT_VERSION} already installed"
  exit 0
fi

base="https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "==> downloading tflint ${TFLINT_VERSION} for ${tools_os}/${tools_arch}"
curl -fsSL -o "${workdir}/${archive}" "${base}/${archive}"

tools_extract "${workdir}/${archive}" "$workdir"
tools_install "$(tools_locate "$workdir" "$binary")" "$binary"

"${tools_bin_dir}/${binary}" --version
