#!/usr/bin/env bash
# bicep lint across every Bicep file under bicep/.
#
# The counterpart of lint-terraform.sh. Rules and the justifications for the two
# that are turned off are in bicep/bicepconfig.json.
#
# Any output fails, warnings included, because bicep lint exits 0 on warnings
# such as BCP335.
set -uo pipefail

cd "$(dirname "$0")/.."

if ! command -v bicep > /dev/null 2>&1; then
  echo "FAIL: bicep not found. See \"Running the checks locally\" in README.md." >&2
  exit 1
fi

failed=0
found=0

while IFS= read -r f; do
  found=$((found + 1))
  output="$(bicep lint "$f" 2>&1)"
  if [ -n "$output" ]; then
    echo "==> ${f}"
    echo "$output"
    failed=1
  fi
done < <(git ls-files 'bicep/*.bicep')

if [ "$found" -eq 0 ]; then
  echo "SKIP  no tracked Bicep files"
  exit 0
fi

if [ "$failed" -ne 0 ]; then
  echo "FAIL: bicep lint reported findings"
  exit 1
fi
echo "PASS: bicep lint clean across ${found} files"
