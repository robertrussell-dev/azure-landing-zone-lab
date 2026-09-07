#!/usr/bin/env bash
# Format check and schema validation for every Terraform directory under infra/.
#
# Shared by both CI definitions. The pipelines install Terraform and call this;
# they do not reimplement it. See docs/ci-security.md for why there are two.
set -uo pipefail

cd "$(dirname "$0")/.."

echo "==> terraform fmt -check -recursive"
if ! terraform fmt -check -recursive -diff infra; then
  echo "FAIL: run 'terraform fmt -recursive infra' and commit the result"
  exit 1
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
