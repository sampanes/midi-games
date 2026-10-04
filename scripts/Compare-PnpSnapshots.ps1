[CmdletBinding()]
param(
    [string]$BaselinePath,
    [string]$CurrentPath,
    [string]$DiffPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $repositoryRoot 'private\usb\baseline-not-keyboard.json'
}
if ([string]::IsNullOrWhiteSpace($CurrentPath)) {
    $CurrentPath = Join-Path $repositoryRoot 'private\usb\after-keyboard.json'
}
if ([string]::IsNullOrWhiteSpace($DiffPath)) {
    $DiffPath = Join-Path $repositoryRoot 'private\usb\diff.json'
}

$fullBaselinePath = [IO.Path]::GetFullPath($BaselinePath)
if (-not [IO.File]::Exists($fullBaselinePath)) {
    throw "Baseline not found. Run .\scripts\Capture-PnpSnapshot.ps1 before connecting the keyboard."
}

function Get-LocalPnpProperty {
    param(
        [Parameter(Mandatory)]
        [string]$InstanceId,
        [Parameter(Mandatory)]
        [string]$KeyName
    )

    try {
        $value = (Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction Stop).Data
        if ($null -eq $value) {
            return $null
        }

        if ($value -is [System.Array]) {
            return @($value | ForEach-Object { [string]$_ })
        }

        return [string]$value
    }
    catch {
        return $null
    }
}

$baseline = Get-Content -LiteralPath $fullBaselinePath -Raw | ConvertFrom-Json

$captureScript = Join-Path $PSScriptRoot 'Capture-PnpSnapshot.ps1'
$captureSummary = & $captureScript -OutputPath $CurrentPath -Label 'keyboard attached candidate'
$fullCurrentPath = [IO.Path]::GetFullPath($CurrentPath)
$current = Get-Content -LiteralPath $fullCurrentPath -Raw | ConvertFrom-Json

$baselineIds = @{}
foreach ($node in @($baseline.PresentPnpNodes)) {
    $baselineIds[[string]$node.InstanceId] = $true
}

$currentIds = @{}
foreach ($node in @($current.PresentPnpNodes)) {
    $currentIds[[string]$node.InstanceId] = $true
}

$addedBasic = @(
    $current.PresentPnpNodes | Where-Object {
        -not $baselineIds.ContainsKey([string]$_.InstanceId)
    }
)

$removedNodes = @(
    $baseline.PresentPnpNodes | Where-Object {
        -not $currentIds.ContainsKey([string]$_.InstanceId)
    }
)

$addedNodes = @(
    foreach ($node in $addedBasic) {
        $containerId = Get-LocalPnpProperty -InstanceId $node.InstanceId -KeyName 'DEVPKEY_Device_ContainerId'
        $parent = Get-LocalPnpProperty -InstanceId $node.InstanceId -KeyName 'DEVPKEY_Device_Parent'

        $groupKey = if (
            -not [string]::IsNullOrWhiteSpace($containerId) -and
            $containerId -ne '{00000000-0000-0000-FFFF-FFFFFFFFFFFF}'
        ) {
            "container:$containerId"
        }
        elseif (-not [string]::IsNullOrWhiteSpace($parent)) {
            "parent:$parent"
        }
        else {
            "instance:$($node.InstanceId)"
        }

        [pscustomobject][ordered]@{
            GroupKey              = $groupKey
            Status                = [string]$node.Status
            Class                 = [string]$node.Class
            FriendlyName          = [string]$node.FriendlyName
            InstanceId            = [string]$node.InstanceId
            BusReportedDescription = Get-LocalPnpProperty -InstanceId $node.InstanceId -KeyName 'DEVPKEY_Device_BusReportedDeviceDesc'
            ContainerId           = $containerId
            Parent                = $parent
            LocationPaths         = Get-LocalPnpProperty -InstanceId $node.InstanceId -KeyName 'DEVPKEY_Device_LocationPaths'
            HardwareIds           = Get-LocalPnpProperty -InstanceId $node.InstanceId -KeyName 'DEVPKEY_Device_HardwareIds'
        }
    }
)

$groups = @(
    $addedNodes |
        Group-Object GroupKey |
        ForEach-Object {
            [pscustomobject][ordered]@{
                GroupKey = $_.Name
                Nodes    = @($_.Group)
            }
        }
)

$comparison = [ordered]@{
    SchemaVersion      = 1
    BaselineCapturedAt = [string]$baseline.CapturedAt
    ComparedAt         = [DateTimeOffset]::Now.ToString('o')
    Privacy            = 'Local hardware inventory. Keep this file private and out of Git.'
    AddedNodeCount     = $addedNodes.Count
    RemovedNodeCount   = $removedNodes.Count
    AddedGroups        = $groups
    RemovedNodes       = $removedNodes
}

$fullDiffPath = [IO.Path]::GetFullPath($DiffPath)
$diffDirectory = [IO.Path]::GetDirectoryName($fullDiffPath)
[IO.Directory]::CreateDirectory($diffDirectory) | Out-Null

$json = $comparison | ConvertTo-Json -Depth 10
$utf8WithoutBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($fullDiffPath, $json, $utf8WithoutBom)

Write-Host "Added PnP nodes: $($addedNodes.Count)"
Write-Host "Removed PnP nodes: $($removedNodes.Count)"
Write-Host "Candidate groups: $($groups.Count)"

if ($addedNodes.Count -gt 0) {
    $addedNodes |
        Select-Object GroupKey, Class, FriendlyName, InstanceId |
        Format-Table -AutoSize -Wrap |
        Out-Host
}

[pscustomobject]@{
    AddedNodes    = $addedNodes.Count
    RemovedNodes  = $removedNodes.Count
    Groups        = $groups.Count
    CurrentPath   = $captureSummary.OutputPath
    DiffPath      = $fullDiffPath
}
