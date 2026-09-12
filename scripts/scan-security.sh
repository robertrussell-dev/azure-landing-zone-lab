#!/usr/bin/env bash
# checkov static analysis. Writes JUnit XML so both CI systems can publish it.
#
# Two scans, one per language, into subdirectories of the output path:
#
#   terraform   terraform/, scanned directly
#   arm         bicep/, scanned after compiling to ARM JSON
#
# Bicep is not scanned as Bicep. checkov's Bicep parser cannot read lambda
# expressions, and bicep/modules/policy-assignment uses toObject with two
# lambdas to wrap policy parameters. Those files come back as parsing errors,
# checkov exits 0 anyway, and the result is a gate that reports success while
# covering nothing. Compiling first avoids the parser entirely, scans what
# would actually be deployed rather than what was written, and on this tree
# reaches 46 resources against the Bicep parser's 24.
#
# --soft-fail is deliberately not used. A finding fails the build. Anything
# accepted is recorded in .checkov.yml with a written justification.
#
# A parsing error also fails the build. checkov counts them in its summary and
# then exits 0, so a file it cannot read is otherwise indistinguishable from a
# file with nothing wrong in it.
set -uo pipefail

cd "$(dirname "$0")/.."
. ./scripts/tools.sh

# The Bicep tree is scanned as compiled ARM JSON, so this needs a Bicep CLI.
ensure_tool bicep install-bicep.sh || exit 1

# checkov is a Python package rather than a release binary, so it is not
# installed on demand the way the others are. Dropping a pinned executable into
# a gitignored directory is reversible and affects nothing else; installing into
# whichever Python happens to be on PATH is neither, so it stays an explicit
# choice the operator makes.
if ! command -v checkov > /dev/null 2>&1; then
  echo "FAIL: checkov not found. Install it with 'pip install checkov' and re-run." >&2
  exit 1
fi

OUT_DIR="${1:-checkov-results}"

BICEP_BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BICEP_BUILD_DIR"' EXIT

failed=0

run_scan() {
  local name="$1" directory="$2" framework="$3"

  echo "==> checkov ${framework} on ${directory}"
  checkov \
    --directory "${directory}" \
    --framework "${framework}" \
    --config-file .checkov.yml \
    --output junitxml \
    --output json \
    --output-file-path "${OUT_DIR}/${name}"
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    echo "FAIL: checkov reported findings in ${directory}, see ${OUT_DIR}/${name}"
    failed=1
    return
  fi

  local parsing_errors
  parsing_errors="$(python3 -c "
import json, sys
with open(sys.argv[1]) as handle:
    report = json.load(handle)
if isinstance(report, list):
    report = report[0]
print(report['summary']['parsing_errors'])
" "${OUT_DIR}/${name}/results_json.json")"

  if [ "$parsing_errors" != "0" ]; then
    echo "FAIL: checkov could not parse ${parsing_errors} file(s) in ${directory}. Unparsed files are not scanned."
    failed=1
  fi
}

# name, directory, framework
run_scan terraform terraform terraform

# Compile every Bicep root and module to ARM JSON, preserving the directory
# layout so a finding names something a reader can find in the repository.
echo "==> compiling bicep for the arm scan"
while IFS= read -r f; do
  target_dir="${BICEP_BUILD_DIR}/$(dirname "$f")"
  mkdir -p "${target_dir}"
  bicep build "$f" --outfile "${target_dir}/$(basename "$f" .bicep).json" || failed=1
done < <(git ls-files 'bicep/*.bicep')

run_scan bicep "${BICEP_BUILD_DIR}" arm

if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "PASS: checkov clean"
