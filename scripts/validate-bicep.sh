#!/usr/bin/env bash
# Format check and compilation for everything under bicep/.
#
# Shared by both CI definitions. The pipelines install Bicep and call this; they
# do not reimplement it. See docs/ci-security.md for why there are two.
#
# Mirrors validate-terraform.sh: format, compile, then the parameter files.
set -uo pipefail

cd "$(dirname "$0")/.."

if ! command -v bicep > /dev/null 2>&1; then
  echo "FAIL: bicep not found. See \"Running the checks locally\" in README.md." >&2
  exit 1
fi

# Tracked files only, so the gitignored main.bicepparam can't fail it locally.
# There's no "bicep format --check", so this formats to stdout and compares.
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

# Every .bicep file, so a module nothing calls yet still gets compiled. This is
# offline; the schemas ship with the pinned CLI.
echo "==> bicep build"
while IFS= read -r f; do
  echo "  ${f}"
  bicep build "$f" --stdout > /dev/null || failed=1
done < <(git ls-files 'bicep/*.bicep')

# Each committed example against its template, so a renamed parameter fails
# here.
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
