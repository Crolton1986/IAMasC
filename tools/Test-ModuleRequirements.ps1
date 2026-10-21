#Requires -Version 7.4
<#
.SYNOPSIS
    Audits requirements.psd1. PSGallery modules aren't covered by GitHub's advisory database,
    Dependabot, or Trivy, so this is the supply-chain check for them.

.DESCRIPTION
    Fails when a module:
      - isn't pinned to an exact version,
      - is listed in security/module-denylist.psd1 (known-bad name or version),
      - can't be found on PSGallery at the pinned version (pulled or unlisted releases often mean a problem).
    Warns when a newer version is published, so upgrades get reviewed instead of forgotten.
#>
[CmdletBinding()]
param(
    [string] $RequirementsPath = (Join-Path $PSScriptRoot '..' 'requirements.psd1'),
    [string] $DenylistPath = (Join-Path $PSScriptRoot '..' 'security' 'module-denylist.psd1'),
    [switch] $Offline
)

$ErrorActionPreference = 'Stop'
$failures = [Collections.Generic.List[string]]::new()
$modules = (Import-PowerShellDataFile $RequirementsPath).Modules
$denylist = if (Test-Path $DenylistPath) { (Import-PowerShellDataFile $DenylistPath).Entries } else { @() }

foreach ($m in $modules) {
    if ($m.Version -notmatch '^\d+\.\d+\.\d+(\.\d+)?$') {
        $failures.Add("$($m.Name): version '$($m.Version)' is not an exact pin")
        continue
    }

    foreach ($d in $denylist | Where-Object Name -EQ $m.Name) {
        if (-not $d.Version -or $d.Version -eq $m.Version) {
            $failures.Add("$($m.Name) $($m.Version): denylisted ($($d.Reason))")
        }
    }

    if ($Offline) { continue }

    $pinned = Find-Module -Name $m.Name -RequiredVersion $m.Version -Repository PSGallery -ErrorAction SilentlyContinue
    if (-not $pinned) {
        $failures.Add("$($m.Name) $($m.Version): not found on PSGallery")
        continue
    }
    $latest = Find-Module -Name $m.Name -Repository PSGallery -ErrorAction SilentlyContinue
    if ($latest -and [version] $latest.Version -gt [version] $m.Version) {
        Write-Warning "$($m.Name): pinned $($m.Version), latest is $($latest.Version). Review the changelog and bump in a chore/ PR."
    }
    Write-Information "OK  $($m.Name) $($m.Version)" -InformationAction Continue
}

if ($failures.Count) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "Module audit failed with $($failures.Count) problem(s)."
}
