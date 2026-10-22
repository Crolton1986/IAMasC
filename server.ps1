#Requires -Version 7.4
<#
.SYNOPSIS
    Starts the IAMasC web server.

.DESCRIPTION
    Validates the server settings and every workspace before listening, and refuses to start on
    any error. In dev mode it only listens on a loopback address.

.EXAMPLE
    ./server.ps1 -Settings ./examples/server/dev.yaml
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Settings,

    # Overrides spec.listen.port (tests use a free port).
    [int] $Port,

    # Overrides spec.dataPath.
    [string] $DataPath
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$modules = @{
    Config = Join-Path $root 'src' 'IAMasC.Config' 'IAMasC.Config.psd1'
    Store  = Join-Path $root 'src' 'IAMasC.Store' 'IAMasC.Store.psd1'
    Web    = Join-Path $root 'src' 'IAMasC.Web' 'IAMasC.Web.psd1'
}
Import-Module $modules.Config, $modules.Store -Force

function Exit-WithError([string] $Message) {
    [Console]::Error.WriteLine("IAMasC can't start: $Message")
    exit 1
}

function Format-Diagnostic($d) {
    $where = if ($d.Field) { "$($d.File): $($d.Field)" } else { $d.File }
    "  $($d.Severity.ToUpperInvariant()) $where`n    $($d.Message)"
}

# Settings
if (-not (Test-Path -LiteralPath $Settings -PathType Leaf)) { Exit-WithError "settings file '$Settings' not found." }
$settingsDoc = Import-IamServerSetting -Path $Settings
$settingsErrors = @($settingsDoc.Diagnostics | Where-Object Severity -EQ 'Error')
if ($settingsErrors) {
    Exit-WithError ("the settings file has errors:`n" + (($settingsErrors | ForEach-Object { Format-Diagnostic $_ }) -join "`n"))
}
$settingsDir = Split-Path (Resolve-Path -LiteralPath $Settings).Path -Parent
$spec = $settingsDoc.Data['spec']
$resolve = { param($p) if ([IO.Path]::IsPathRooted($p)) { $p } else { [IO.Path]::GetFullPath((Join-Path $settingsDir $p)) } }

$mode = $spec['auth']['mode']
if ($mode -ne 'dev') {
    Exit-WithError "auth.mode '$mode' isn't available in this release yet. Use 'dev' for local testing."
}

$listen = if ($spec['listen']) { $spec['listen'] } else { @{} }
$address = if ($listen['address']) { [string]$listen['address'] } else { '127.0.0.1' }
if (-not $PSBoundParameters.ContainsKey('Port')) { $Port = if ($listen['port']) { [int]$listen['port'] } else { 8080 } }
if ($mode -eq 'dev' -and $address -notin '127.0.0.1', '::1', 'localhost') {
    Exit-WithError "dev mode only listens on 127.0.0.1, ::1, or localhost, not '$address'. Dev mode signs everyone in as an admin."
}

if (-not $DataPath) { $DataPath = if ($spec['dataPath']) { & $resolve $spec['dataPath'] } else { Join-Path $settingsDir 'data' } }
$null = New-Item -ItemType Directory -Path $DataPath -Force

# Workspaces
$workspaces = foreach ($entry in $spec['workspaces']) {
    if (-not $entry['path']) {
        Exit-WithError "workspace '$($entry['name'])' uses repo:. Cloning repositories arrives with the workspaces feature; use path: for now."
    }
    $wsPath = & $resolve $entry['path']
    if (-not (Test-Path -LiteralPath $wsPath -PathType Container)) { Exit-WithError "workspace '$($entry['name'])' folder '$wsPath' not found." }
    $ws = Import-IamWorkspace -Path $wsPath
    $wsErrors = @($ws.Diagnostics | Where-Object Severity -EQ 'Error')
    if ($wsErrors) {
        Exit-WithError ("workspace '$($entry['name'])' has errors. Run ./iamasc.ps1 validate '$wsPath' for details:`n" + (($wsErrors | ForEach-Object { Format-Diagnostic $_ }) -join "`n"))
    }
    # The server settings name wins over the folder's metadata.name.
    $ws.Name = $entry['name']
    $ws
}
$workspaces = @($workspaces)

# Store
$dbPath = Join-Path $DataPath 'iamasc.db'
$store = Open-IamStore -Path $dbPath
$versionFile = Join-Path $root 'VERSION'
$version = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { '0.0.0-dev' }
$null = Write-IamAudit -Store $store -Actor 'system' -Action 'server.started' -After @{
    version    = $version
    mode       = $mode
    address    = $address
    port       = $Port
    workspaces = @($workspaces | ForEach-Object Name)
}
Close-IamStore $store

Write-Information "IAMasC $version listening on http://$($address):$Port ($mode mode, $($workspaces.Count) workspace(s))" -InformationAction Continue

Import-Module Pode -RequiredVersion 2.14.1
Start-PodeServer -Threads 4 -ScriptBlock {
    Add-PodeEndpoint -Address $address -Port $Port -Protocol Http

    New-PodeLoggingMethod -File -Path (Join-Path $DataPath 'logs') -Name 'errors' | Enable-PodeErrorLogging

    # Headers on every response, error pages included.
    Set-PodeSecurityContentSecurityPolicy -Default 'self' -FrameAncestor 'none' -FormAction 'self' -BaseUri 'self'
    Set-PodeSecurityContentTypeOptions
    Set-PodeSecurityReferrerPolicy -Type 'no-referrer'
    Set-PodeSecurityFrameOptions -Type 'Deny'
    Hide-PodeSecurityServer

    Import-PodeModule -Path $modules.Config
    Import-PodeModule -Path $modules.Store
    Import-PodeModule -Path $modules.Web

    $null = Set-PodeState -Name 'context' -Value @{
        Version    = $version
        DevMode    = ($mode -eq 'dev')
        User       = if ($mode -eq 'dev') { 'dev-admin' } else { '' }
        Workspaces = $workspaces
        Database   = $dbPath
    }

    Add-PodeStaticRoute -Path '/static' -Source (Join-Path $root 'src' 'IAMasC.Web' 'public')

    Add-PodeRoute -Method Get -Path '/health' -ScriptBlock {
        $ctx = Get-PodeState -Name 'context'
        $database = 'ok'
        try {
            $s = Open-IamStore -Path $ctx.Database
            try { $null = Invoke-IamQuery -Store $s -Sql 'SELECT 1 AS ok' } finally { Close-IamStore $s }
        } catch {
            $database = 'unavailable'
        }
        $healthy = $database -eq 'ok'
        Write-PodeJsonResponse -StatusCode ($healthy ? 200 : 503) -Value ([ordered]@{
                status     = $healthy ? 'ok' : 'degraded'
                version    = $ctx.Version
                database   = $database
                workspaces = @($ctx.Workspaces | ForEach-Object {
                        [ordered]@{ name = $_.Name; people = @($_.People).Count; warnings = @($_.Diagnostics | Where-Object Severity -EQ 'Warning').Count }
                    })
            })
    }

    Add-PodeRoute -Method Get -Path '/' -ScriptBlock {
        Write-PodeHtmlResponse -Value (Get-IamDashboardPage -Context (Get-PodeState -Name 'context'))
    }

    Add-PodeRoute -Method Get -Path '/people' -ScriptBlock {
        Write-PodeHtmlResponse -Value (Get-IamPeoplePage -Context (Get-PodeState -Name 'context') -Query $WebEvent.Query['q'] -Status $WebEvent.Query['status'])
    }

    Add-PodeRoute -Method Get -Path '/people/:workspace/:id' -ScriptBlock {
        $ctx = Get-PodeState -Name 'context'
        $html = Get-IamPersonPage -Context $ctx -Workspace $WebEvent.Parameters['workspace'] -Id $WebEvent.Parameters['id']
        if ($html) {
            Write-PodeHtmlResponse -Value $html
        } else {
            Write-PodeHtmlResponse -StatusCode 404 -Value (Get-IamNotFoundPage -Context $ctx -What 'person')
        }
    }
}
