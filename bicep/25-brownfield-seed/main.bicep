// Deliberately non compliant resources, created on purpose.
//
// Read this before assuming it is a mistake.
//
// The brownfield adoption pattern in ADR 0005 only demonstrates anything if the
// adopted subscription actually violates the policies it is being measured
// against. An empty subscription reports no compliance state at all, because
// there is nothing to evaluate, which makes the audit only assignment look like
// it is not working when it is simply not applicable to anything.
//
// In a real engagement these violations already exist and nobody had to create
// them. Here they are seeded, and the README says so rather than implying an
// inherited mess.
//
// Everything below is free. Virtual networks, subnets and network security
// groups carry no hourly charge.
//
// A second violation used to live here: a network interface carrying a public
// IP, which tripped the Deny assigned at Corp. Because this subscription sits
// under Corp (audit only) it was created successfully and recorded as non
// compliant, where under Corp the same call is refused. That is the clearest
// demonstration in this platform of enforcement following placement rather than
// policy.
//
// It was removed after the compliance evidence was captured, because a Standard
// static public IP is the only resource here that bills by the hour. The
// evidence is committed at docs/evidence/policy-portal.png. This is the deploy,
// screenshot, destroy discipline the network stack uses, applied to a single
// resource.
//
// Scope. The brownfield subscription, and only that one:
//
//   az deployment sub create --subscription <brownfield GUID> \
//     --location westus2 --template-file main.bicep \
//     --parameters main.bicepparam
//
// The Terraform version pins the subscription in an aliased provider so the
// configuration cannot create non compliant resources anywhere else by
// accident. Here the subscription comes from the command line, so --subscription
// is doing that job and it is worth typing rather than relying on whatever
// az account show returns.

targetScope = 'subscription'

@description('Region for the seeded resources.')
param location string = 'westus2'

// ---------------------------------------------------------------------------
// Who owns the costCenter tag
// ---------------------------------------------------------------------------
// The Modify assignment at the intermediate root appends costCenter to any
// resource created without it. It works: nothing below declares costCenter, and
// every resource here carries costCenter = lab after creation.
//
// Terraform turns that into a visible fight. It reads the tag back, does not
// find it in the configuration, and plans to remove it, so the plan is never
// clean until someone decides who owns the field. That is what the
// ignore_changes on tags["costCenter"] in terraform/25-brownfield-seed settles.
//
// Bicep has no ignore_changes and nothing that reports drift on a schedule. A
// redeploy PUTs the tags below over what is there, and the policy appends
// costCenter again on the next evaluation.
//
// what-if does show it. Run against the deployed lab it reports
// "- tags.costCenter: lab" on the virtual network, which is the same argument
// Terraform surfaces in a plan. The difference is that Terraform puts it in
// front of you every time and this only appears if someone asks. The loop is
// invisible by default rather than invisible always.
//
// The mitigation, if it matters, is to read the existing tags and union them in
// rather than declaring them outright. That is left out here because it makes
// first deployment and redeployment behave differently, and this file's job is
// to be obvious. It is the practical cost of policy driven governance alongside
// infrastructure as code, and it is why Modify assignments should be few and
// well known.

resource seed 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'rg-legacy-app'
  location: location

  // Deliberately missing costCenter. The Modify assignment at the intermediate
  // root appends it to resources that lack it, so this is also the test of
  // whether that assignment does what it claims.
  tags: {
    autoDelete: 'true'
  }
}

module network 'seed-network.bicep' = {
  scope: seed
  name: 'seed-network'
  params: {
    location: location
  }
}

@description('Resource ID of the subnet that has no network security group, which is the violation this directory exists to create.')
output nonCompliantSubnetId string = network.outputs.subnetId
