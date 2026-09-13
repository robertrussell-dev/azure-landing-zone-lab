<#
.SYNOPSIS
Deletes billable lab resources whose deleteAfter tag has passed.

.DESCRIPTION
Catches billable devices someone forgot to switch off in the 90 roots.

Three guards:

  1. Tags. autoDelete is "true" and deleteAfter has passed. autoDelete alone
     isn't enough: the brownfield seed network has it, with no deadline.
  2. The type list below.
  3. The janitor's role, which can only delete those types. If the list ever
     grows past the role, the delete fails with a 403.

One tier per run. Devices go first; public IPs and firewall policies can't be
deleted while a device references them, so they go on a later run. That costs a
few cents of public IP time and avoids waiting on slow deletes inside a job
billed by the minute.

Authenticates with the Automation account's managed identity and imports no
modules.

.PARAMETER ManagementGroupId
Name of the management group to search. Normally the intermediate root.

.PARAMETER DryRun
Report what would be deleted and delete nothing. Required outside Automation,
where the caller's identity is broader than the janitor's role.
#>
param(
    [Parameter(Mandatory = $true)]
    [string] $ManagementGroupId,

    # bool rather than switch: Automation cannot pass a switch from a schedule.
    [bool] $DryRun = $false
)

$ErrorActionPreference = 'Stop'

# Types this deletes, and their tier. Keep in step with the janitor role in
# both trees.
$tiers = @{
    'microsoft.network/azurefirewalls'         = 1
    'microsoft.network/virtualnetworkgateways' = 1
    'microsoft.network/bastionhosts'           = 1
    # Route Server is modeled as a virtual hub.
    'microsoft.network/virtualhubs'            = 1
    'microsoft.network/firewallpolicies'       = 2
    'microsoft.network/publicipaddresses'      = 2
}

# Valid for all six types (checked with "az provider show", 2026-09-12).
$apiVersion = '2024-05-01'

$arm = 'https://management.azure.com'

function Get-ArmToken {
    if ($env:IDENTITY_ENDPOINT) {
        $headers = @{ 'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER; 'Metadata' = 'True' }
        $uri = '{0}?resource={1}/' -f $env:IDENTITY_ENDPOINT, $arm
        return (Invoke-RestMethod -Method Get -Uri $uri -Headers $headers).access_token
    }

    if (-not $DryRun) {
        throw 'Not running in Automation. Pass -DryRun $true to report from a workstation.'
    }

    $token = az account get-access-token --resource "$arm/" --query accessToken -o tsv
    if (-not $token) {
        throw 'No managed identity endpoint and no Azure CLI session to fall back on.'
    }
    return $token
}

function Get-ErrorDetail($record) {
    if ($record.ErrorDetails -and $record.ErrorDetails.Message) {
        return $record.ErrorDetails.Message
    }
    return $record.Exception.Message
}

$auth = @{ Authorization = "Bearer $(Get-ArmToken)" }

# Every tagged resource, whatever its type, so a mistagged one shows in the log.
$query = @"
resources
| where tostring(tags['autoDelete']) =~ 'true' and isnotempty(tostring(tags['deleteAfter']))
| project id, type = tolower(type), deleteAfter = tostring(tags['deleteAfter']), state = tostring(properties.provisioningState)
"@

$body = @{
    managementGroups = @($ManagementGroupId)
    query            = $query
    options          = @{ '$top' = 1000 }
} | ConvertTo-Json -Depth 5

$result = Invoke-RestMethod -Method Post -Headers $auth -ContentType 'application/json' -Body $body `
    -Uri "$arm/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01"

if ($result.'$skipToken') {
    Write-Warning 'More than 1000 tagged resources. Only the first page was read.'
}

$now = [DateTimeOffset]::UtcNow
$expired = @()

foreach ($row in @($result.data)) {
    $deadline = [DateTimeOffset]::MinValue
    $parsed = [DateTimeOffset]::TryParse(
        $row.deleteAfter,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal,
        [ref] $deadline)

    if (-not $parsed) {
        Write-Warning "Skipped, deleteAfter is not a date ($($row.deleteAfter)): $($row.id)"
        continue
    }
    if ($deadline -gt $now) {
        Write-Output "Not due until $($deadline.ToString('u')): $($row.id)"
        continue
    }
    if (-not $tiers.ContainsKey($row.type)) {
        Write-Warning "Skipped, $($row.type) is not a type this runbook deletes: $($row.id)"
        continue
    }

    $expired += [pscustomobject]@{
        Id    = $row.id
        Tier  = $tiers[$row.type]
        State = $row.state
    }
}

if ($expired.Count -eq 0) {
    Write-Output 'Nothing expired.'
    return
}

$tier = 2
if (@($expired | Where-Object { $_.Tier -eq 1 }).Count -gt 0) {
    $tier = 1
}
$waiting = @($expired | Where-Object { $_.Tier -gt $tier })
if ($waiting.Count -gt 0) {
    Write-Output "$($waiting.Count) public IP(s) or firewall policies wait for a run with no expired device left."
}

$failures = 0

foreach ($target in @($expired | Where-Object { $_.Tier -eq $tier })) {
    if ($target.State -eq 'Deleting') {
        Write-Output "Already deleting: $($target.Id)"
        continue
    }
    if ($DryRun) {
        Write-Output "Would delete: $($target.Id)"
        continue
    }

    try {
        Invoke-RestMethod -Method Delete -Headers $auth `
            -Uri ('{0}{1}?api-version={2}' -f $arm, $target.Id, $apiVersion) | Out-Null
        Write-Output "Delete accepted: $($target.Id)"
    }
    catch {
        $failures++
        Write-Error "Delete failed: $($target.Id): $(Get-ErrorDetail $_)" -ErrorAction Continue
    }
}

# A failed job is the alert. A delete that fails after being accepted is retried
# by the next run.
if ($failures -gt 0) {
    throw "$failures delete request(s) failed. See the errors above."
}
