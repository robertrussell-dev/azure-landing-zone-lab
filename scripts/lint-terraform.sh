#!/usr/bin/env bash
# tflint across every Terraform directory under infra/.
set -uo pipefail

cd "$(dirname "$0")/.."

failed=0
for dir in infra/*/; do
  if ! compgen -G "${dir}*.tf" > /dev/null; then continue; fi
  echo "==> ${dir}"
  tflint --chdir="${dir}" --no-color || failed=1
done

if [ "$failed" -ne 0 ]; then
  echo "FAIL: tflint reported findings"
  exit 1
fi
echo "PASS: tflint clean"
