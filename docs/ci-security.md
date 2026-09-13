# CI security posture

The code lives in a public GitHub repository. The validation pipeline runs in
Azure Pipelines. This document records why that combination is safe and what
would change if the pipeline ever needed to reach Azure.

## The pipeline holds no credentials

`azure-pipelines.yml` has no service connection and no secrets. It runs
`terraform fmt`, `terraform validate`, `tflint`, the Bicep build and lint,
`checkov` and a markdown link check. It never plans or deploys.

`terraform init -backend=false` installs providers so `validate` can check
schemas without a backend or credentials, and `bicep build` is offline.

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

Required configuration, to be verified against the organization before the
pipeline is enabled on a public repository:

1. `Limit building pull requests from forked GitHub repositories` set to
   `Securely build pull requests from forked repositories` at organization
   level.
2. `Make secrets available to builds of forks` off. There are no secrets
   today, but this keeps one added later from being exposed.
3. Microsoft hosted agents only. They're deleted after each build, so a
   compromised build doesn't persist. A self hosted agent building fork pull
   requests would.

Status: applied. The repository is public, the Azure DevOps project builds it
through a GitHub App service connection, and all three controls above are in
place.

Item 3 is visible in the pipeline definition itself, which targets the
Microsoft hosted `Azure Pipelines` pool with `vmImage: ubuntu-latest` and
declares no self hosted agent.

Items 1 and 2 are organization level settings and **aren't exposed by the Azure
DevOps REST API**, so CI can't check them. They're in the portal at
**Organization settings, Pipelines, Settings**, and that's where to verify this
claim.

The remaining risk is that a stranger's code runs on a throwaway Microsoft
hosted VM after a maintainer comments on the pull request. That's true of any
public repository using hosted CI, and it's accepted.

## Why there are two CI definitions

This repository has both `.github/workflows/validate.yml` and
`azure-pipelines.yml`, running the same checks, because it's a portfolio
project and both platforms matter for the roles it's aimed at.

The risks of duplicated CI are the two drifting apart, and one of them
stopping without anyone noticing:

1. **The checks live in `scripts/`, not in the CI files.** Both definitions
   install tools and call the same scripts, so neither can check something
   different.
2. **Both run on every pull request, and both pass.** The Azure Pipelines
   definition builds the repository through a GitHub App service connection.
   It passed on its first run, because every bug the first GitHub Actions run
   found was in the shared scripts.

Public projects in Azure DevOps are retired for organizations not already
using them, so the Azure Pipelines badge can't be shown to anonymous readers.
Only someone with access to the project can see that pipeline.

What stays in each CI file is platform specific:

| Concern | Azure Pipelines | GitHub Actions |
|---|---|---|
| Test result rendering | `PublishTestResults@2` shows checkov JUnit XML in the Tests tab | No equivalent. JUnit XML is uploaded as an artifact, to avoid running a third party reporter action |
| Supply chain of the CI definition itself | Script steps only, no Marketplace extensions, so it runs in any organization and every step is readable | First party actions only, pinned by commit SHA, because tags can be moved |
| Tool installation | Explicit `curl` of a pinned Terraform version | `hashicorp/setup-terraform` with `terraform_wrapper: false`, because the wrapper intercepts exit codes and breaks the shared scripts |
| Fork pull request safety | Org and project level controls, covered above | `permissions: contents: read` at workflow level, and fork PRs get a read only token by default |

## The GitHub connection

Azure Pipelines connects to GitHub through a GitHub App installation scoped to
this repository. A personal access token with `repo` scope would give Azure
DevOps every repository the account can reach.

## If the pipeline ever needed Azure access

It doesn't today. If deployment were added, the design would be:

- An **Azure Resource Manager service connection using workload identity
  federation**, created as `App registration (automatic)` with the credential
  type `Workload identity federation`. Microsoft recommends this over a service
  principal with a secret, because there's no secret at all.
- **Scope level `Management Group`**, not `Subscription`, because a platform
  pipeline writes policy assignments at management groups.
- **Not** `Grant access permission to all pipelines`. Each pipeline is
  authorized individually.
- Deployment stages gated behind an Environment with a manual approval check,
  so no push to a branch can apply changes on its own.

Two details about workload identity federation service connections:

- Azure DevOps is retiring the Azure DevOps issuer
  (`https://vstoken.dev.azure.com`) on 1 July 2027 and standardizing on the
  Microsoft Entra issuer (`https://login.microsoftonline.com/`). New connections
  already use the Entra issuer by default.
- Azure Pipelines can disable a service connection unused for 100 days, and
  platform pipelines often run that rarely.

## References

- [Build GitHub repositories, contributions from forks](https://learn.microsoft.com/en-us/azure/devops/pipelines/repos/github?view=azure-devops#contributions-from-forks)
- [Repository protection, forks](https://learn.microsoft.com/en-us/azure/devops/pipelines/security/misc?view=azure-devops#forks)
- [Use an Azure Resource Manager service connection](https://learn.microsoft.com/en-us/azure/devops/pipelines/library/connect-to-azure?view=azure-devops)
