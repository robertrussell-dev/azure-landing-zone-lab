#!/usr/bin/env bash
# Format check and schema validation for every Terraform root under terraform/.
#
# Shared by both CI definitions. The pipelines install Terraform and call this;
# they do not reimplement it. See docs/ci-security.md for why there are two.
set -uo pipefail

cd "$(dirname "$0")/.."

if ! command -v terraform > /dev/null 2>&1; then
  echo "FAIL: terraform not found. See \"Running the checks locally\" in README.md." >&2
  exit 1
fi

# Tracked files only. "terraform fmt -recursive" would also check the
# gitignored terraform.tfvars, which CI never sees.
echo "==> terraform fmt -check, tracked files only"
mapfile -t tf_files < <(git ls-files '*.tf' '*.tfvars')
if [ "${#tf_files[@]}" -eq 0 ]; then
  echo "SKIP  no tracked Terraform files"
else
  fmt_failed=0
  for f in "${tf_files[@]}"; do
    terraform fmt -check -diff "$f" > /dev/null || { echo "  needs formatting: $f"; fmt_failed=1; }
  done
  if [ "$fmt_failed" -ne 0 ]; then
    echo "FAIL: run 'terraform fmt' on the files above and commit the result"
    exit 1
  fi
  echo "PASS  ${#tf_files[@]} tracked files correctly formatted"
fi

failed=0
# Numbered roots only; modules are validated through their callers.
for dir in terraform/[0-9]*/; do
  # An empty directory is a placeholder, not a failure.
  if ! compgen -G "${dir}*.tf" > /dev/null; then
    echo "SKIP  ${dir} (no .tf files yet)"
    continue
  fi

  echo "==> ${dir}"
  # -backend=false installs providers without state or Azure credentials.
  if ! terraform -chdir="${dir}" init -backend=false -input=false -no-color; then
    failed=1
    continue
  fi
  terraform -chdir="${dir}" validate -no-color || failed=1
done

if [ "$failed" -ne 0 ]; then
  echo "FAIL: terraform validate reported errors"
  exit 1
fi
echo "PASS: all Terraform directories valid"
