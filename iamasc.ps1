#Requires -Version 7.4
<#
.SYNOPSIS
    IAMasC command line.

.DESCRIPTION
    Commands:
      validate <path>   Check a workspace folder or a server settings file.
                        Exit code 0 when there are no errors, 1 otherwise.
                        Warnings don't fail unless -Strict is set.

.EXAMPLE
    ./iamasc.ps1 validate ./examples/corp-chicago
    ./iamasc.ps1 validate ./examples/server/iamasc-server.yaml -Format json
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory)]
    [ValidateSet('validate')]
    [string] $Command,

    [Parameter(Position = 1, Mandatory)]
    [string] $Path,

    [ValidateSet('text', 'json')]
    [string] $Format = 'text',

    # Treat warnings as errors.
    [switch] $Strict
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src' 'IAMasC.Config' 'IAMasC.Config.psd1') -Force

switch ($Command) {
    'validate' {
        if (-not (Test-Path -LiteralPath $Path)) {
            [Console]::Error.WriteLine("Path not found: $Path")
            exit 2
        }

        if (Test-Path -LiteralPath $Path -PathType Container) {
            $result = Import-IamWorkspace -Path $Path
            $subject = "workspace $($result.Name ?? (Split-Path $result.Path -Leaf))"
        } else {
            $result = Import-IamServerSetting -Path $Path
            $subject = "server settings $(Split-Path $Path -Leaf)"
        }

        $diagnostics = @($result.Diagnostics)
        $errorCount = @($diagnostics | Where-Object Severity -EQ 'Error').Count
        $warningCount = @($diagnostics | Where-Object Severity -EQ 'Warning').Count
        $failed = $errorCount -gt 0 -or ($Strict -and $warningCount -gt 0)

        if ($Format -eq 'json') {
            [ordered]@{
                subject     = $subject
                valid       = -not $failed
                errors      = $errorCount
                warnings    = $warningCount
                diagnostics = @($diagnostics | Select-Object Severity, File, Field, Message)
            } | ConvertTo-Json -Depth 5
        } else {
            foreach ($d in $diagnostics | Sort-Object File, Field) {
                $where = if ($d.Field) { "$($d.File): $($d.Field)" } else { $d.File }
                "{0,-7} {1}`n        {2}" -f $d.Severity.ToUpperInvariant(), $where, $d.Message
            }
            if ($diagnostics) { '' }
            $verdict = if ($failed) { 'FAILED' } else { 'OK' }
            "$verdict  ${subject}: $errorCount error(s), $warningCount warning(s)"
        }

        exit ([int]$failed)
    }
}
