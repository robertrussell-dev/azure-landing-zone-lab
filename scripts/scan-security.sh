#!/usr/bin/env bash
# checkov static analysis. Writes JUnit XML so both CI systems can publish it.
#
# --soft-fail is deliberately not used. A finding fails the build. Anything
# accepted is recorded in .checkov.yml with a written justification.
set -uo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="${1:-checkov-results}"

checkov \
  --directory infra \
  --framework terraform \
  --config-file .checkov.yml \
  --output junitxml \
  --output-file-path "${OUT_DIR}"
rc=$?

if [ "$rc" -ne 0 ]; then
  echo "FAIL: checkov reported findings, see ${OUT_DIR}"
  exit "$rc"
fi
echo "PASS: checkov clean"
