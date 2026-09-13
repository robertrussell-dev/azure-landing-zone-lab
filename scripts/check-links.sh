#!/usr/bin/env bash
# Markdown link check.
#
# Microsoft Learn rate limits automated clients, so 429 counts as a pass.
# Retries and a concurrency cap keep the check from being flaky.
set -uo pipefail

cd "$(dirname "$0")/.."

if ! command -v lychee > /dev/null 2>&1; then
  echo "FAIL: lychee not found. See \"Running the checks locally\" in README.md." >&2
  exit 1
fi

lychee \
  --no-progress \
  --accept 200,206,429 \
  --max-retries 3 \
  --retry-wait-time 5 \
  --max-concurrency 4 \
  --exclude-path ./landing-zone-lab-brief.md \
  './**/*.md'
rc=$?

if [ "$rc" -ne 0 ]; then
  echo "FAIL: broken links found"
  exit "$rc"
fi
echo "PASS: all links resolve"
