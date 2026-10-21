#Requires -Version 7.4
<#
.SYNOPSIS
    Build entry point. CI runs exactly these tasks, so a green local run means a green CI run.

.EXAMPLE
    ./build.ps1 -Task Bootstrap, Lint, Test
    ./build.ps1 -Task SecurityScan
    ./build.ps1 -Task Package -Version 0.1.0
#>
[CmdletBinding()]
param(
    [ValidateSet('Bootstrap', 'Lint', 'Test', 'SecurityScan', 'Package')]
    [string[]] $Task = @('Lint', 'Test'),

    # Package version. Defaults to the latest git tag without the leading 'v'.
    [string] $Version,

    # Where Lint writes SARIF and Test writes JUnit/coverage.
    [string] $OutputPath = (Join-Path $PSScriptRoot 'out')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step {
    param([string] $Message)
    Write-Information "==> $Message" -InformationAction Continue
}

function Get-Requirement {
    (Import-PowerShellDataFile (Join-Path $PSScriptRoot 'requirements.psd1')).Modules
}

function Import-Requirement {
    param([string] $Name)
    $req = Get-Requirement | Where-Object Name -EQ $Name
    Import-Module $Name -RequiredVersion $req.Version -Force
}

function Invoke-Bootstrap {
    Write-Step 'Installing pinned modules'
    foreach ($module in Get-Requirement) {
        $installed = Get-Module -ListAvailable -Name $module.Name |
            Where-Object { $_.Version -eq [version] $module.Version }
        if ($installed) {
            Write-Step "$($module.Name) $($module.Version) already installed"
            continue
        }
        Install-Module -Name $module.Name -RequiredVersion $module.Version `
            -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
    }

    Write-Step 'Restoring .NET packages into lib/'
    & (Join-Path $PSScriptRoot 'tools/Restore-NuGetPackage.ps1')
}

function Invoke-Lint {
    param([string] $OutputPath)
    Import-Requirement PSScriptAnalyzer
    $injectionHunter = (Get-Module -ListAvailable InjectionHunter |
            Where-Object { $_.Version -eq [version] (Get-Requirement | Where-Object Name -EQ 'InjectionHunter').Version }).Path

    $files = Get-ChildItem -Path $PSScriptRoot -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1' |
        Where-Object { $_.FullName -notmatch '[\\/](out|dist|\.git)[\\/]' }

    Write-Step "Analyzing $($files.Count) files"
    $settings = Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1'
    $results = foreach ($file in $files) {
        Invoke-ScriptAnalyzer -Path $file.FullName -Settings $settings
        # InjectionHunter rules only apply to script code, not data files.
        if ($file.Extension -ne '.psd1') {
            Invoke-ScriptAnalyzer -Path $file.FullName -CustomRulePath $injectionHunter
        }
    }

    $null = New-Item -ItemType Directory -Path $OutputPath -Force
    & (Join-Path $PSScriptRoot 'tools/ConvertTo-Sarif.ps1') -Result $results -RepoRoot $PSScriptRoot |
        Set-Content -Path (Join-Path $OutputPath 'psscriptanalyzer.sarif') -Encoding utf8

    if ($results) {
        foreach ($r in $results) {
            Write-Information "$($r.Severity) $($r.RuleName) $($r.ScriptName):$($r.Line) $($r.Message)" -InformationAction Continue
        }
        throw "PSScriptAnalyzer found $(@($results).Count) issue(s)."
    }
    Write-Step 'Lint clean'
}

function Invoke-Test {
    param([string] $OutputPath)
    Import-Requirement Pester
    $null = New-Item -ItemType Directory -Path $OutputPath -Force

    $config = New-PesterConfiguration
    $config.Run.Path = Join-Path $PSScriptRoot 'tests'
    $config.Run.Exit = $false
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'JUnitXml'
    $config.TestResult.OutputPath = Join-Path $OutputPath 'testResults.xml'

    # Coverage turns on once application code exists under src/.
    $src = Join-Path $PSScriptRoot 'src'
    if (Test-Path $src) {
        $config.CodeCoverage.Enabled = $true
        $config.CodeCoverage.Path = $src
        $config.CodeCoverage.OutputFormat = 'JaCoCo'
        $config.CodeCoverage.OutputPath = Join-Path $OutputPath 'coverage.xml'
    }

    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0) {
        throw "$($result.FailedCount) test(s) failed."
    }
}

function Invoke-SecurityScan {
    Write-Step 'Auditing pinned PowerShell modules'
    & (Join-Path $PSScriptRoot 'tools/Test-ModuleRequirements.ps1')

    if (Get-Command gitleaks -ErrorAction SilentlyContinue) {
        Write-Step 'gitleaks'
        & gitleaks git $PSScriptRoot --redact --no-banner --exit-code 1
        if ($LASTEXITCODE -ne 0) { throw 'gitleaks found secrets.' }
    } else {
        Write-Warning 'gitleaks not on PATH, skipped locally (CI runs it).'
    }

    if (Get-Command trivy -ErrorAction SilentlyContinue) {
        Write-Step 'trivy fs'
        & trivy fs --scanners vuln, misconfig, secret --severity HIGH, CRITICAL --exit-code 1 --quiet $PSScriptRoot
        if ($LASTEXITCODE -ne 0) { throw 'trivy found HIGH/CRITICAL issues.' }
    } else {
        Write-Warning 'trivy not on PATH, skipped locally (CI runs it).'
    }
}

function Invoke-Package {
    param([string] $Version)
    if (-not $Version) {
        $tag = git -C $PSScriptRoot describe --tags --abbrev=0 2>$null
        $Version = if ($tag) { $tag.TrimStart('v') } else { '0.0.0-dev' }
    }
    $dist = Join-Path $PSScriptRoot 'dist'
    $staging = Join-Path $dist "IAMasC-$Version"
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    $null = New-Item -ItemType Directory -Path $staging -Force

    # Ship only what runs in production. Tests, docs, and CI config stay out.
    $include = @('server.ps1', 'iamasc.ps1', 'src', 'lib', 'routes', 'views', 'public', 'config', 'requirements.psd1', 'README.md', 'CHANGELOG.md')
    foreach ($item in $include) {
        $path = Join-Path $PSScriptRoot $item
        if (Test-Path $path) { Copy-Item $path -Destination $staging -Recurse }
    }
    Set-Content -Path (Join-Path $staging 'VERSION') -Value $Version -NoNewline

    $zip = Join-Path $dist "IAMasC-$Version.zip"
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip
    $hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -Path "$zip.sha256" -Value "$hash  $(Split-Path $zip -Leaf)"
    Write-Step "Packaged $zip"
}

foreach ($t in $Task) {
    Write-Step "Task: $t"
    switch ($t) {
        'Bootstrap' { Invoke-Bootstrap }
        'Lint' { Invoke-Lint -OutputPath $OutputPath }
        'Test' { Invoke-Test -OutputPath $OutputPath }
        'SecurityScan' { Invoke-SecurityScan }
        'Package' { Invoke-Package -Version $Version }
    }
}
