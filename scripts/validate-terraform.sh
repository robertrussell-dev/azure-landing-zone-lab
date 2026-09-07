#!/usr/bin/env bash
# Format check and schema validation for every Terraform directory under infra/.
#
# Shared by both CI definitions. The pipelines install Terraform and call this;
# they do not reimplement it. See docs/ci-security.md for why there are two.
set -uo pipefail

cd "$(dirname "$0")/.."

# Format check runs over git tracked files only, not over the working tree.
#
# "terraform fmt -recursive" walks everything on disk, which includes
# terraform.tfvars. Those are gitignored and CI never sees them, so a recursive
# check fails locally and passes in CI for files that are not in the
# repository. A check that only fails on the developer's machine is a check
# people learn to ignore.
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
for dir in infra/*/; do
  # A directory with no .tf files yet is a placeholder for a later phase, not a
  # failure. Without this, scaffolding a phase breaks the build.
  if ! compgen -G "${dir}*.tf" > /dev/null; then
    echo "SKIP  ${dir} (no .tf files yet)"
    continue
  fi

  echo "==> ${dir}"
  # -backend=false installs providers so that validate can check resource
  # schemas, without configuring state or authenticating to Azure. This is what
  # allows validation to run with no credentials present.
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
