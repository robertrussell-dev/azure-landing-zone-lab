// The per subscription baseline that Azure Policy cannot apply: Defender for
// Cloud's free posture tier and its security contact. Activity log streaming
// and Service Health alerts are policy in bicep/10-policy, because policy
// reaches every subscription under the intermediate root including ones vended
// later.
//
// Unlike the Terraform module, this registers no resource providers. A Bicep
// deployment registers the providers for the resource types it declares, so
// deploying these two resources registers Microsoft.Security by itself. The
// Terraform module has to do it explicitly, and also registers
// Microsoft.PolicyInsights, which no template here declares.
//
// Everything here is free.

targetScope = 'subscription'

@description('Addresses Defender for Cloud notifies about high severity alerts. Empty skips the contact.')
param securityContactEmails array = []

// Foundational CSPM, the free tier of Defender for Cloud posture management.
// From 27 October 2026 new subscriptions no longer get it by default, so it is
// set explicitly. "Free" here is the free plan; "Standard" would be the paid
// Defender CSPM plan, billed per resource.
resource foundationalCspm 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'CloudPosture'
  properties: {
    pricingTier: 'Free'
  }
}

// Who Defender emails about high severity alerts in this subscription, in
// addition to its owners.
resource securityContact 'Microsoft.Security/securityContacts@2023-12-01-preview' = if (!empty(securityContactEmails)) {
  name: 'default'
  properties: {
    emails: join(securityContactEmails, ';')
    isEnabled: true
    notificationsByRole: {
      state: 'On'
      roles: [
        'Owner'
      ]
    }
    notificationsSources: [
      {
        sourceType: 'Alert'
        minimalSeverity: 'High'
      }
    ]
  }
}

@description('The Defender for Cloud posture tier this module set. Free is Foundational CSPM.')
output cspmTier string = foundationalCspm.properties.pricingTier
