# HTML building blocks. Every value that came from a file or a request goes through
# ConvertTo-IamHtml before it reaches the page. Person files are user-editable YAML, so treat
# their contents as hostile.

function ConvertTo-IamHtml {
    <# HTML-encodes any value. $null becomes an empty string. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] $Value)
    if ($null -eq $Value) { return '' }
    [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-IamUrlSegment {
    <# Encodes a value for use inside a URL path or query string. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] $Value)
    if ($null -eq $Value) { return '' }
    [Uri]::EscapeDataString([string]$Value)
}

function Get-IamStatusPill {
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Status)
    $class = switch ($Status) {
        'Active' { 'ok' }
        'Pending' { 'info' }
        'Offboarding' { 'warn' }
        default { '' }
    }
    "<span class=`"pill $class`">$(ConvertTo-IamHtml $Status)</span>"
}

function Get-IamLayout {
    <#
    .SYNOPSIS
        Wraps page content in the site layout: rail navigation, dev banner, and the main column.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Title,
        [Parameter(Mandatory)] [string] $Body,
        [ValidateSet('dashboard', 'people', 'none')] [string] $Active = 'none',
        [Parameter(Mandatory)] [hashtable] $Context
    )

    $nav = foreach ($item in @(
            @{ Key = 'dashboard'; Href = '/'; Label = 'Dashboard' }
            @{ Key = 'people'; Href = '/people'; Label = 'People' }
        )) {
        $current = if ($item.Key -eq $Active) { ' aria-current="page"' } else { '' }
        "<a href=`"$($item.Href)`"$current>$($item.Label)</a>"
    }
    $banner = if ($Context.DevMode) {
        '<div class="devbanner" role="status">Dev mode: signed in as a local test admin. Only reachable from this machine.</div>'
    } else { '' }
    $workspaces = ($Context.Workspaces | ForEach-Object { ConvertTo-IamHtml $_.Name }) -join ', '

    @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(ConvertTo-IamHtml $Title) &middot; IAMasC</title>
<link rel="stylesheet" href="/static/iamasc.css">
</head>
<body>
$banner
<div class="app">
  <aside class="rail">
    <div class="brand">IAMasC <small>$(ConvertTo-IamHtml $Context.Version)</small></div>
    <nav aria-label="Main">
      $($nav -join "`n      ")
    </nav>
    <div class="me">Signed in as <strong>$(ConvertTo-IamHtml $Context.User)</strong><br>Workspaces: <span class="mono">$workspaces</span></div>
  </aside>
  <main>
$Body
  </main>
</div>
</body>
</html>
"@
}
