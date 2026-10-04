[CmdletBinding()]
param(
    [string]$OutputPath,
    [ValidateNotNullOrEmpty()]
    [string]$Label = 'NOT keyboard'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repositoryRoot 'private\usb\baseline-not-keyboard.json'
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

try {
    $presentDevices = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Sort-Object InstanceId)
}
catch {
    throw "Windows did not allow the Plug-and-Play inventory: $($_.Exception.Message)"
}

$presentPnpNodes = @(
    foreach ($device in $presentDevices) {
        [ordered]@{
            Status       = [string]$device.Status
            Class        = [string]$device.Class
            FriendlyName = [string]$device.FriendlyName
            InstanceId   = [string]$device.InstanceId
        }
    }
)

$usbDevices = @(
    $presentDevices | Where-Object {
        $_.InstanceId -like 'USB\*' -or $_.InstanceId -like 'USBSTOR\*'
    }
)

$usbNodes = @(
    foreach ($device in $usbDevices) {
        [ordered]@{
            Status                 = [string]$device.Status
            Class                  = [string]$device.Class
            FriendlyName           = [string]$device.FriendlyName
            InstanceId             = [string]$device.InstanceId
            BusReportedDescription = Get-LocalPnpProperty -InstanceId $device.InstanceId -KeyName 'DEVPKEY_Device_BusReportedDeviceDesc'
            Manufacturer           = Get-LocalPnpProperty -InstanceId $device.InstanceId -KeyName 'DEVPKEY_Device_Manufacturer'
            ContainerId            = Get-LocalPnpProperty -InstanceId $device.InstanceId -KeyName 'DEVPKEY_Device_ContainerId'
            Parent                 = Get-LocalPnpProperty -InstanceId $device.InstanceId -KeyName 'DEVPKEY_Device_Parent'
            LocationPaths          = Get-LocalPnpProperty -InstanceId $device.InstanceId -KeyName 'DEVPKEY_Device_LocationPaths'
            HardwareIds            = Get-LocalPnpProperty -InstanceId $device.InstanceId -KeyName 'DEVPKEY_Device_HardwareIds'
        }
    }
)

$snapshot = [ordered]@{
    SchemaVersion   = 1
    Label           = $Label
    CapturedAt      = [DateTimeOffset]::Now.ToString('o')
    Privacy         = 'Local hardware inventory. Keep this file private and out of Git.'
    PresentPnpNodes = $presentPnpNodes
    UsbNodes        = $usbNodes
}

$fullOutputPath = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = [IO.Path]::GetDirectoryName($fullOutputPath)
[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null

$json = $snapshot | ConvertTo-Json -Depth 8
$utf8WithoutBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($fullOutputPath, $json, $utf8WithoutBom)

[pscustomobject]@{
    Label           = $Label
    PresentPnpNodes = $presentPnpNodes.Count
    UsbNodes        = $usbNodes.Count
    OutputPath      = $fullOutputPath
}
