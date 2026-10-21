#Requires -Version 7.4
<#
.SYNOPSIS
    Installs a release zip side by side with earlier releases and switches the service to it.
    Rolls back to the previous release if the health check fails.

.DESCRIPTION
    Layout under -InstallRoot:
        releases/<version>/   one folder per release
        current               junction to the active release (the service runs from here)
        config/, data/, logs/ live outside releases so upgrades never touch them
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $ZipPath,
    [Parameter(Mandatory)] [string] $InstallRoot,
    [string] $ServiceName = 'IAMasC',
    [string] $HealthUrl,
    [int] $KeepReleases = 3
)

$ErrorActionPreference = 'Stop'

function Test-Health {
    param([string] $Url)
    if (-not $Url) { return $true }
    foreach ($attempt in 1..10) {
        try {
            $response = Invoke-WebRequest -Uri $Url -TimeoutSec 5 -SkipHttpErrorCheck
            if ($response.StatusCode -eq 200) { return $true }
        } catch {
            Write-Verbose "Health attempt $attempt failed: $_"
        }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Switch-Release {
    param([string] $Target)
    $current = Join-Path $InstallRoot 'current'
    if (Test-Path $current) { (Get-Item $current).Delete() }
    $null = New-Item -ItemType Junction -Path $current -Target $Target
}

$sumFile = "$ZipPath.sha256"
if (Test-Path $sumFile) {
    $expected = ((Get-Content $sumFile -Raw).Trim() -split '\s+')[0]
    $actual = (Get-FileHash $ZipPath -Algorithm SHA256).Hash
    if ($actual -ne $expected) { throw "Checksum mismatch for $ZipPath." }
}

$releases = Join-Path $InstallRoot 'releases'
foreach ($dir in $releases, (Join-Path $InstallRoot 'config'), (Join-Path $InstallRoot 'data'), (Join-Path $InstallRoot 'logs')) {
    $null = New-Item -ItemType Directory -Path $dir -Force
}

$name = [IO.Path]::GetFileNameWithoutExtension($ZipPath)
if (-not $name.StartsWith('IAMasC-')) { throw "Unexpected package name '$name'. Expected IAMasC-<version>.zip." }
$version = $name.Substring('IAMasC-'.Length)
$target = Join-Path $releases $version
$current = Join-Path $InstallRoot 'current'
$previous = if (Test-Path $current) { (Get-Item $current).Target } else { $null }

if ($PSCmdlet.ShouldProcess($target, "Install IAMasC $version")) {
    Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive -Path $ZipPath -DestinationPath $target

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) { Stop-Service -Name $ServiceName }
    Switch-Release -Target $target
    if ($service) { Start-Service -Name $ServiceName }

    if (-not (Test-Health -Url $HealthUrl)) {
        if ($previous) {
            Write-Warning "Health check failed, rolling back to $previous"
            if ($service) { Stop-Service -Name $ServiceName }
            Switch-Release -Target $previous
            if ($service) { Start-Service -Name $ServiceName }
        }
        throw "IAMasC $version failed its health check."
    }

    Get-ChildItem $releases -Directory | Sort-Object CreationTime -Descending |
        Select-Object -Skip $KeepReleases | Remove-Item -Recurse -Force
    Write-Information "Deployed IAMasC $version" -InformationAction Continue
}
