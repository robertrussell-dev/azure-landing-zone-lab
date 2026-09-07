# CI security posture

The code lives in a public GitHub repository. The validation pipeline runs in
Azure Pipelines. This document records why that combination is safe and what
would change if the pipeline ever needed to reach Azure.

## The pipeline holds no credentials

`azure-pipelines.yml` has no service connection and no secrets. It runs
`terraform fmt`, `terraform validate`, `tflint`, `checkov` and a markdown
link check. It never runs `terraform plan` or
`terraform apply` against a subscription.

`terraform init -backend=false` is what makes this possible. It installs
providers so `validate` can check resource schemas, without configuring a
backend or authenticating.

Deployment is run interactively by an operator. See the README.

## Public repository, forked pull request risk

The relevant threat is a stranger forking the repository, adding a malicious
step to the pipeline definition or a script it calls, and opening a pull
request that causes it to run.

Azure Pipelines defaults are already the safe ones, and have been since 2023:

| Setting | Default | Why it matters |
|---|---|---|
| `Limit building pull requests from forked GitHub repositories` | Organizations created since September 2023 default to `Securely build pull requests from forked repositories` | Fork PRs cannot receive secrets, cannot get normal build permissions, and must be triggered by a pull request comment |
| Automatic building of fork PRs | Disabled by default for new projects and organizations since Sprint 229 | Nothing runs until a maintainer asks for it |
| `Make secrets available to builds of forks` | Off | The setting that leaks secrets to strangers. Never enable it on a public repository |
| `Make fork builds have the same permissions as regular builds` | Off | Fork builds get a restricted access token |

Settings applied to this project:

1. `Limit building pull requests from forked GitHub repositories` set to
   `Securely build pull requests from forked repositories` at organization level.
2. `Make secrets available to builds of forks` left off. There are no secrets to
   leak, but the setting is confirmed off so that adding one later does not
   silently expose it.
3. Microsoft hosted agents only. Agent machines are deleted immediately after a
   build completes, so a compromised build has no lasting effect. A self hosted
   agent building fork pull requests from a public repository would be a serious
   mistake, because the machine persists between runs.

The residual risk is that a stranger can cause code to execute on an ephemeral
Microsoft hosted VM, after a maintainer comments on the pull request. That is
the same posture as any public repository using hosted CI, and it is accepted.

## Why there are two CI definitions

This repository carries both `.github/workflows/validate.yml` and
`azure-pipelines.yml`, running the same checks. That is unusual and a reviewer
will notice it, so the reason is stated rather than left to be guessed: this is
a portfolio artifact, and both platforms are in scope for the roles it is aimed
at.

The obvious failure modes of duplicated CI are that the two definitions drift
apart in what they verify, and that one of them quietly stops running and
becomes decorative. Two things guard against that:

1. **The checks live in `scripts/`, not in the CI files.** Both definitions
   install tools and then call the same scripts. Neither can silently check
   something different from the other, because neither contains the logic.
2. **Both actually run on every pull request**, and the README shows the status
   of both. A pipeline definition that has never executed is worse than no
   pipeline definition.

What stays in the CI file is genuinely platform specific, and the differences
are the interesting part rather than noise:

| Concern | Azure Pipelines | GitHub Actions |
|---|---|---|
| Test result rendering | `PublishTestResults@2` renders checkov JUnit XML natively in the Tests tab | No equivalent. JUnit XML is uploaded as an artifact rather than run a third party reporter action in CI |
| Supply chain of the CI definition itself | Script steps only, no Marketplace extension tasks, so the pipeline runs in any organisation and a reviewer can read exactly what executes | First party actions only, pinned by commit SHA rather than tag, because a tag is mutable and can be repointed by whoever controls the action repository |
| Tool installation | Explicit `curl` of a pinned Terraform version | `hashicorp/setup-terraform` with `terraform_wrapper: false`, because the wrapper intercepts exit codes and breaks the shared scripts |
| Fork pull request safety | Org and project level controls, covered above | `permissions: contents: read` at workflow level, and fork PRs get a read only token by default |

## The GitHub connection

Azure Pipelines connects to GitHub with a GitHub App installation rather than a
personal access token. The App is scoped to this single repository. A personal
access token with `repo` scope would grant Azure DevOps access to every
repository the account can reach, which is a much larger blast radius for no
benefit.

## If the pipeline ever needed Azure access

It does not today, and the deliberate absence is the point. If deployment were
added, the design would be:

- An **Azure Resource Manager service connection using workload identity
  federation**, created as `App registration (automatic)` with the credential
  type `Workload identity federation`. Microsoft's current guidance recommends
  this over a service principal with a secret, because it removes the secret
  entirely rather than protecting it.
- **Scope level `Management Group`**, not `Subscription`. Azure Pipelines
  supports management group scoped service connections directly, which matches
  how a landing zone is actually operated: the platform pipeline needs to write
  policy assignments at a management group, not resources in one subscription.
- **Not** `Grant access permission to all pipelines`. Each pipeline is
  authorized individually.
- Deployment stages gated behind an Environment with a manual approval check,
  so no push to a branch can apply changes on its own.

Two operational details worth knowing about workload identity federation
service connections:

- Azure DevOps is retiring the Azure DevOps issuer
  (`https://vstoken.dev.azure.com`) on 1 July 2027 and standardising on the
  Microsoft Entra issuer (`https://login.microsoftonline.com/`). New connections
  already use the Entra issuer by default.
- Azure Pipelines can automatically disable a service connection that has not
  been used for 100 days. A pipeline that runs rarely, which describes most
  landing zone platform pipelines, can fail for this reason alone.

## References

- [Build GitHub repositories, contributions from forks](https://learn.microsoft.com/en-us/azure/devops/pipelines/repos/github?view=azure-devops#contributions-from-forks)
- [Repository protection, forks](https://learn.microsoft.com/en-us/azure/devops/pipelines/security/misc?view=azure-devops#forks)
- [Use an Azure Resource Manager service connection](https://learn.microsoft.com/en-us/azure/devops/pipelines/library/connect-to-azure?view=azure-devops)
