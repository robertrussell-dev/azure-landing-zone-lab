#!/usr/bin/env bash
# tflint across every Terraform root under terraform/.
#
# The glob matches the numbered roots and not terraform/modules/, which has no
# .tf files at its top level and is validated through the roots that call it.
set -uo pipefail

cd "$(dirname "$0")/.."

failed=0
for dir in terraform/[0-9]*/; do
  if ! compgen -G "${dir}*.tf" > /dev/null; then continue; fi
  echo "==> ${dir}"
  tflint --chdir="${dir}" --no-color || failed=1
done

if [ "$failed" -ne 0 ]; then
  echo "FAIL: tflint reported findings"
  exit 1
fi
echo "PASS: tflint clean"
