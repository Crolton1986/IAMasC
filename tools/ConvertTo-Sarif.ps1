#Requires -Version 7.4
<#
.SYNOPSIS
    Converts PSScriptAnalyzer results to SARIF 2.1.0 so findings show in GitHub code scanning.
#>
[CmdletBinding()]
param(
    [AllowNull()]
    [object[]] $Result,

    [Parameter(Mandatory)]
    [string] $RepoRoot
)

$levels = @{ Error = 'error'; Warning = 'warning'; Information = 'note'; ParseError = 'error' }
$rootFull = (Resolve-Path $RepoRoot).Path

$rules = @{}
$sarifResults = foreach ($r in @($Result | Where-Object { $_ })) {
    if (-not $rules.ContainsKey($r.RuleName)) {
        $rules[$r.RuleName] = @{ id = $r.RuleName; shortDescription = @{ text = $r.RuleName } }
    }
    $relative = [IO.Path]::GetRelativePath($rootFull, $r.ScriptPath) -replace '\\', '/'
    @{
        ruleId    = $r.RuleName
        level     = $levels["$($r.Severity)"] ?? 'warning'
        message   = @{ text = $r.Message }
        locations = @(@{
                physicalLocation = @{
                    artifactLocation = @{ uri = $relative }
                    region           = @{ startLine = [math]::Max(1, [int] $r.Line); startColumn = [math]::Max(1, [int] $r.Column) }
                }
            })
    }
}

@{
    '$schema' = 'https://json.schemastore.org/sarif-2.1.0.json'
    version   = '2.1.0'
    runs      = @(@{
            tool    = @{ driver = @{ name = 'PSScriptAnalyzer'; informationUri = 'https://github.com/PowerShell/PSScriptAnalyzer'; rules = @($rules.Values) } }
            results = @($sarifResults)
        })
} | ConvertTo-Json -Depth 20
