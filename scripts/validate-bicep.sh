#!/usr/bin/env bash
# Format check and compilation for everything under bicep/.
#
# Shared by both CI definitions. The pipelines install Bicep and call this; they
# do not reimplement it. See docs/ci-security.md for why there are two.
#
# The Terraform equivalent is validate-terraform.sh, and this deliberately
# mirrors it: format first, then a check that every root actually compiles, then
# the parameter files against the templates they claim to configure.
set -uo pipefail

cd "$(dirname "$0")/.."
. ./scripts/tools.sh

ensure_tool bicep install-bicep.sh || exit 1

# Format check runs over git tracked files only, for the same reason
# validate-terraform.sh does. main.bicepparam is gitignored and holds one
# operator's tenant and subscription IDs, so a check that walked the working
# tree would fail locally and pass in CI on a file that is not in the
# repository. A check that only fails on the developer's machine is a check
# people learn to ignore.
#
# There is no "bicep format --check". Formatting to stdout and comparing is the
# equivalent, and the file list is small enough that the extra process per file
# costs nothing.
echo "==> bicep format check, tracked files only"
mapfile -t bicep_files < <(git ls-files 'bicep/*.bicep' 'bicep/*.bicepparam')

if [ "${#bicep_files[@]}" -eq 0 ]; then
  echo "SKIP  no tracked Bicep files"
else
  fmt_failed=0
  for f in "${bicep_files[@]}"; do
    if ! diff -q "$f" <(bicep format "$f" --stdout) > /dev/null 2>&1; then
      echo "  needs formatting: $f"
      fmt_failed=1
    fi
  done
  if [ "$fmt_failed" -ne 0 ]; then
    echo "FAIL: run 'bicep format <file>' on the files above and commit the result"
    exit 1
  fi
  echo "PASS  ${#bicep_files[@]} tracked files correctly formatted"
fi

failed=0

# Every .bicep file, not only the four roots. A module is compiled anyway when
# a root that calls it is compiled, but compiling it on its own is what catches
# a module nothing calls yet, which is exactly the state a half finished
# refactor leaves behind.
#
# Compilation needs no Azure credentials and reaches no Azure API. Resource type
# schemas are embedded in the CLI, which is the reason the pinned version in
# install-bicep.sh matters.
echo "==> bicep build"
while IFS= read -r f; do
  echo "  ${f}"
  bicep build "$f" --stdout > /dev/null || failed=1
done < <(git ls-files 'bicep/*.bicep')

# Parameter files are compiled against the template their "using" statement
# names, so a parameter that was renamed in the template fails here rather than
# at deployment time. Only the committed examples exist to check; a real
# main.bicepparam is gitignored.
echo "==> bicep build-params"
while IFS= read -r f; do
  echo "  ${f}"
  bicep build-params "$f" --stdout > /dev/null || failed=1
done < <(git ls-files 'bicep/*.bicepparam')

if [ "$failed" -ne 0 ]; then
  echo "FAIL: bicep reported errors"
  exit 1
fi
echo "PASS: all Bicep files compile"
