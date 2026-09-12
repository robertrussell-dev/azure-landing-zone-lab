// Central Log Analytics workspace.
//
// This exists so the DeployIfNotExists assignment in bicep/10-policy has
// somewhere to route diagnostics. Until it exists, that assignment is skipped
// rather than assigned against nothing. See bicep/10-policy/main.bicep.
//
// Cost, verified against the Azure retail prices API on 2026-09-06 for West
// US 2 in USD. Verify before reusing, these move.
//
//   Analytics Logs Data Ingestion   2.30 per GB
//   Analytics Logs Data Retention   0.10 per GB per month, beyond the
//                                   31 days included at no charge
//
// The daily cap is the guardrail that makes this safe to leave running on a
// personal card. At 0.1 GB per day the worst case is roughly 7 USD per month
// even if something starts logging aggressively, and the realistic figure for a
// lab with no traffic is close to zero. A workspace without a cap is an
// unbounded bill, which is the one shape of mistake worth engineering against.

@description('Workspace name.')
param name string

@description('Region for the workspace.')
param location string

resource workspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: name
  location: location

  properties: {
    sku: {
      name: 'PerGB2018'
    }

    // 30 days is the minimum and is included at no additional charge. Anything
    // longer is a per GB per month cost and should be a deliberate decision
    // tied to a retention requirement, not a default nobody revisited.
    retentionInDays: 30

    workspaceCapping: {
      // Ingestion stops for the rest of the day once this is hit. Data already
      // ingested is queryable, and collection resumes at the next daily reset.
      // Losing a lab's logs is preferable to an unbounded bill.
      //
      // json() because Bicep has no float literal. Writing 0.1 directly is a
      // parse error, not a rounding surprise, so the failure is at least loud.
      dailyQuotaGb: json('0.1')
    }
  }

  tags: {
    costCenter: 'lab'
    autoDelete: 'true'
  }
}

@description('Resource ID of the workspace.')
output id string = workspace.id
