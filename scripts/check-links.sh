#!/usr/bin/env bash
# Markdown link check.
#
# Microsoft Learn rate limits automated clients. 429 is a throttle response, not
# a dead link, so it is accepted rather than failing the build. Retries and a
# concurrency cap keep the check meaningful without making it flaky, which is
# the failure mode that causes people to start ignoring a red build.
set -uo pipefail

cd "$(dirname "$0")/.."

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
