#!/usr/bin/env bash
# bicep lint across every Bicep file under bicep/.
#
# The counterpart of lint-terraform.sh. Rules and the justifications for the two
# that are turned off are in bicep/bicepconfig.json.
#
# Any output at all is a failure, warnings included. bicep lint exits non-zero
# only on errors, so a rule configured at warning level, or a compiler warning
# such as BCP335 on a deployment name that may exceed 64 characters, would
# otherwise pass silently. That matches the stance in .checkov.yml: this lab is
# small enough that there is no excuse for a backlog of accepted findings.
set -uo pipefail

cd "$(dirname "$0")/.."
. ./scripts/tools.sh

ensure_tool bicep install-bicep.sh || exit 1

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
