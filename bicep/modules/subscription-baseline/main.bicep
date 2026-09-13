// The part of the subscription baseline policy can't do: Defender for Cloud's
// free tier and its security contact. The rest is policy in bicep/10-policy.
// All free.
//
// No provider registration: deploying these registers Microsoft.Security.

targetScope = 'subscription'

@description('Addresses Defender for Cloud notifies about high severity alerts. Empty skips the contact.')
param securityContactEmails array = []

// Foundational CSPM. From 27 October 2026 new subscriptions no longer get it by
// default. "Standard" would be the paid plan.
resource foundationalCspm 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'CloudPosture'
  properties: {
    pricingTier: 'Free'
  }
}

// Who Defender emails about high severity alerts, besides the owners.
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
