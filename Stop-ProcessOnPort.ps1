#Requires -Version 5.1
<#
.SYNOPSIS
    Stops process(es) listening on a local port.

.EXAMPLE
    .\Stop-ProcessOnPort.ps1 3000
    Stops process(es) listening on local port 3000.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateRange(1, 65535)]
    [int]$Port
)

$ErrorActionPreference = 'Stop'

$tcpConnections = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
$udpEndpoints = @(Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue)

$processIds = @(
    @($tcpConnections | ForEach-Object { $_.OwningProcess }) +
    @($udpEndpoints | ForEach-Object { $_.OwningProcess })
) |
Where-Object { $null -ne $_ -and [int]$_ -gt 0 } |
Sort-Object -Unique

if ($processIds.Count -eq 0) {
    throw "No process is listening on local port $Port."
}

foreach ($processId in $processIds) {
    $process = Get-Process -Id $processId -ErrorAction Stop
    Stop-Process -Id $processId -Force
    Write-Host "Stopped process $processId ($($process.ProcessName)) listening on port $Port."
}
