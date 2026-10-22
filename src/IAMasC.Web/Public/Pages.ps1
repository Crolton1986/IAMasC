function Get-IamPersonRow {
    <# Flattens a person document into the fields the pages show. Status is worked out for $Now. #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [hashtable] $Context,
        [datetimeoffset] $Now = [datetimeoffset]::UtcNow
    )

    foreach ($ws in $Context.Workspaces) {
        foreach ($p in $ws.People) {
            $hr = $p.Data['spec']['hr']
            [pscustomobject]@{
                Workspace   = $ws.Name
                Id          = $p.Name
                Name        = "$($hr['preferredFirstName'] ?? $hr['firstName']) $($hr['lastName'])"
                Department  = $hr['department']
                Title       = $hr['title']
                Location    = $hr['location']
                Manager     = $hr['manager']
                StartDate   = ConvertTo-IamDate -Value $hr['startDate']
                Termination = ConvertTo-IamDate -Value $hr['terminationDate']
                Status      = Get-IamPersonStatus -Person $p -Now $Now
                Document    = $p
            }
        }
    }
}

function Format-IamDate {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] $Value)
    if ($null -eq $Value) { return '' }
    $Value.UtcDateTime.ToString('MMM d, yyyy', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-IamPersonLink {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] $Row)
    "/people/$(ConvertTo-IamUrlSegment $Row.Workspace)/$(ConvertTo-IamUrlSegment $Row.Id)"
}

function Get-IamDashboardPage {
    <# The dashboard: counts by status, starts and leavers in the next 14 days, config warnings. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [hashtable] $Context,
        [datetimeoffset] $Now = [datetimeoffset]::UtcNow
    )

    $rows = @(Get-IamPersonRow -Context $Context -Now $Now)
    $horizon = $Now.AddDays(14)
    $count = { param($s) @($rows | Where-Object Status -EQ $s).Count }

    $upcoming = @(
        foreach ($r in $rows) {
            if ($r.StartDate -and $r.StartDate -gt $Now -and $r.StartDate -le $horizon) {
                [pscustomobject]@{ Date = $r.StartDate; Row = $r; Change = 'Starting'; Class = 'info' }
            }
            if ($r.Termination -and $r.Termination -gt $Now -and $r.Termination -le $horizon) {
                [pscustomobject]@{ Date = $r.Termination; Row = $r; Change = 'Leaving'; Class = 'bad' }
            }
        }
    ) | Sort-Object Date

    $upcomingRows = if ($upcoming) {
        ($upcoming | ForEach-Object {
            "<tr><td class=`"nowrap num`">$(Format-IamDate $_.Date)</td><td><a href=`"$(Get-IamPersonLink $_.Row)`">$(ConvertTo-IamHtml $_.Row.Name)</a><span class=`"sub`">$(ConvertTo-IamHtml $_.Row.Department) &middot; $(ConvertTo-IamHtml $_.Row.Title)</span></td><td><span class=`"pill $($_.Class)`">$($_.Change)</span></td><td class=`"mono`">$(ConvertTo-IamHtml $_.Row.Workspace)</td></tr>"
        }) -join "`n"
    } else {
        '<tr><td colspan="4" class="empty">Nobody starts or leaves in the next 14 days.</td></tr>'
    }

    $warnings = @($Context.Workspaces | ForEach-Object { $ws = $_; $_.Diagnostics | Where-Object Severity -EQ 'Warning' | ForEach-Object { [pscustomobject]@{ Workspace = $ws.Name; Diagnostic = $_ } } })
    $warningHtml = if ($warnings) {
        $items = $warnings | ForEach-Object {
            "<li><span class=`"when`">$(ConvertTo-IamHtml $_.Workspace)</span><span><span class=`"mono`">$(ConvertTo-IamHtml $_.Diagnostic.File)</span> $(ConvertTo-IamHtml $_.Diagnostic.Field)<br>$(ConvertTo-IamHtml $_.Diagnostic.Message)</span></li>"
        }
        '<ul class="plan">' + ($items -join '') + '</ul>'
    } else {
        '<p class="muted">No configuration warnings.</p>'
    }

    $body = @"
    <section class="screen" aria-labelledby="h-dashboard">
      <div class="head">
        <div>
          <h1 id="h-dashboard">Dashboard</h1>
          <p>Who's starting, who's leaving, and anything in the configuration that needs a look. $(Format-IamDate $Now).</p>
        </div>
        <div class="actions"><a class="btn" href="/people">All people</a></div>
      </div>
      <div class="stats">
        <div class="stat info"><b>$(& $count 'Pending')</b><span>Pending (not started yet)</span></div>
        <div class="stat ok"><b>$(& $count 'Active')</b><span>Active</span></div>
        <div class="stat warn"><b>$(& $count 'Offboarding')</b><span>Leaving (termination scheduled)</span></div>
        <div class="stat"><b>$(& $count 'Terminated')</b><span>Terminated</span></div>
      </div>
      <div class="grid2">
        <div class="panel">
          <header><h2>Next 14 days</h2></header>
          <div class="table-wrap">
            <table>
              <thead><tr><th>Date</th><th>Person</th><th>Change</th><th>Workspace</th></tr></thead>
              <tbody>
$upcomingRows
              </tbody>
            </table>
          </div>
        </div>
        <div class="panel">
          <header><h2>Configuration warnings</h2><span class="muted">$($warnings.Count)</span></header>
          <div class="body">$warningHtml</div>
        </div>
      </div>
    </section>
"@
    Get-IamLayout -Title 'Dashboard' -Active dashboard -Body $body -Context $Context
}

function Get-IamPeoplePage {
    <# People list with free-text search and a status filter. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [hashtable] $Context,
        [string] $Query,
        [string] $Status,
        [datetimeoffset] $Now = [datetimeoffset]::UtcNow
    )

    $statuses = 'Pending', 'Active', 'Offboarding', 'Terminated'
    if ($Status -and $Status -notin $statuses) { $Status = '' }
    $all = @(Get-IamPersonRow -Context $Context -Now $Now)
    $rows = $all
    if ($Query) {
        # Plain substring match. -like would treat [ ] * ? in the query as wildcards.
        $q = $Query.Trim()
        $ic = [StringComparison]::OrdinalIgnoreCase
        $rows = @($rows | Where-Object {
                "$($_.Name)".Contains($q, $ic) -or "$($_.Id)".Contains($q, $ic) -or
                "$($_.Department)".Contains($q, $ic) -or "$($_.Title)".Contains($q, $ic)
            })
    }
    $filtered = if ($Status) { @($rows | Where-Object Status -EQ $Status) } else { $rows }

    $qs = if ($Query) { "q=$(ConvertTo-IamUrlSegment $Query)&" } else { '' }
    $chips = @("<a class=`"chip`" href=`"/people?$($qs.TrimEnd('&'))`"$(if (-not $Status) { ' aria-current="true"' })>All $($rows.Count)</a>")
    foreach ($s in $statuses) {
        $n = @($rows | Where-Object Status -EQ $s).Count
        $current = if ($Status -eq $s) { ' aria-current="true"' } else { '' }
        $chips += "<a class=`"chip`" href=`"/people?${qs}status=$s`"$current>$s $n</a>"
    }

    $tableRows = if ($filtered) {
        ($filtered | Sort-Object Name | ForEach-Object {
            $dates = switch ($_.Status) {
                'Pending' { "Starts $(Format-IamDate $_.StartDate)" }
                'Offboarding' { "Leaves $(Format-IamDate $_.Termination)" }
                'Terminated' { "Left $(Format-IamDate $_.Termination)" }
                default { "Started $(Format-IamDate $_.StartDate)" }
            }
            "<tr><td><a href=`"$(Get-IamPersonLink $_)`">$(ConvertTo-IamHtml $_.Name)</a></td><td class=`"mono`">$(ConvertTo-IamHtml $_.Id)</td><td>$(ConvertTo-IamHtml $_.Department)<span class=`"sub`">$(ConvertTo-IamHtml $_.Title)</span></td><td>$(Get-IamStatusPill $_.Status)</td><td class=`"num nowrap`">$dates</td><td class=`"mono`">$(ConvertTo-IamHtml $_.Workspace)</td></tr>"
        }) -join "`n"
    } else {
        '<tr><td colspan="6" class="empty">Nobody matches. Clear the search or pick another status.</td></tr>'
    }

    $body = @"
    <section class="screen" aria-labelledby="h-people">
      <div class="head">
        <div>
          <h1 id="h-people">People</h1>
          <p>Everyone with a person file in a loaded workspace. $($all.Count) in total.</p>
        </div>
      </div>
      <div class="toolbar">
        <form class="search-form" method="get" action="/people" role="search">
          <label class="sr-only" for="people-search">Search people</label>
          <input id="people-search" class="search" type="search" name="q" value="$(ConvertTo-IamHtml $Query)" placeholder="Name, employee ID, department, or title">
          $(if ($Status) { "<input type=`"hidden`" name=`"status`" value=`"$(ConvertTo-IamHtml $Status)`">" })
          <button class="btn" type="submit">Search</button>
        </form>
        <nav class="chips" aria-label="Filter by status">$($chips -join '')</nav>
      </div>
      <div class="panel">
        <div class="table-wrap">
          <table>
            <thead><tr><th>Name</th><th>Employee ID</th><th>Department / title</th><th>Status</th><th>Dates</th><th>Workspace</th></tr></thead>
            <tbody>
$tableRows
            </tbody>
          </table>
        </div>
      </div>
    </section>
"@
    Get-IamLayout -Title 'People' -Active people -Body $body -Context $Context
}

function Get-IamPersonPage {
    <# One person: HR details, roles, exceptions, and the person file. Returns $null when not found. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [hashtable] $Context,
        [Parameter(Mandatory)] [string] $Workspace,
        [Parameter(Mandatory)] [string] $Id,
        [datetimeoffset] $Now = [datetimeoffset]::UtcNow
    )

    $row = Get-IamPersonRow -Context $Context -Now $Now | Where-Object { $_.Workspace -ceq $Workspace -and $_.Id -ceq $Id } | Select-Object -First 1
    if (-not $row) { return $null }
    $spec = $row.Document.Data['spec']
    $hr = $spec['hr']

    $hrItems = foreach ($key in $hr.Keys) {
        "<dt>$(ConvertTo-IamHtml $key)</dt><dd>$(ConvertTo-IamHtml $hr[$key])</dd>"
    }

    $roles = @($spec['roles'] | Where-Object { $_ })
    $roleRows = if ($roles) {
        ($roles | ForEach-Object {
            $approvals = @($_['approvals'] | Where-Object { $_ } | ForEach-Object { "$($_['step']) by $($_['by'])" }) -join ', '
            "<tr><td class=`"mono`">$(ConvertTo-IamHtml $_['module'])</td><td class=`"mono`">$(ConvertTo-IamHtml $_['version'])</td><td class=`"num nowrap`">$(ConvertTo-IamHtml $_['from'])</td><td>$(ConvertTo-IamHtml $approvals)</td></tr>"
        }) -join "`n"
    } else { '<tr><td colspan="4" class="empty">No roles beyond baseline access.</td></tr>' }

    $exceptions = @($spec['exceptions'] | Where-Object { $_ })
    $exceptionRows = if ($exceptions) {
        ($exceptions | ForEach-Object {
            $privileged = if ($_['privileged']) { ' <span class="pill bad">Privileged</span>' } else { '' }
            $providers = @($_['grants'].Keys) -join ', '
            "<tr><td>$(ConvertTo-IamHtml $_['name'])$privileged<span class=`"sub`">$(ConvertTo-IamHtml $_['reason'])</span></td><td class=`"mono`">$(ConvertTo-IamHtml $providers)</td><td class=`"mono`">$(ConvertTo-IamHtml $_['ticket'])</td><td class=`"num nowrap`">$(ConvertTo-IamHtml $_['expires'])</td></tr>"
        }) -join "`n"
    } else { '<tr><td colspan="4" class="empty">No exceptions.</td></tr>' }

    $fileText = Get-Content -LiteralPath $row.Document.Path -Raw
    $relative = [IO.Path]::GetRelativePath(($Context.Workspaces | Where-Object Name -EQ $Workspace).Path, $row.Document.Path) -replace '\\', '/'
    $initials = (($row.Name -split '\s+' | Where-Object { $_ } | ForEach-Object { $_.Substring(0, 1) }) -join '').ToUpperInvariant()

    $body = @"
    <section class="screen" aria-labelledby="h-person">
      <div class="head">
        <div class="person-head">
          <div class="avatar" aria-hidden="true">$(ConvertTo-IamHtml $initials)</div>
          <div>
            <h1 id="h-person">$(ConvertTo-IamHtml $row.Name)</h1>
            <p>$(ConvertTo-IamHtml $row.Title), $(ConvertTo-IamHtml $row.Department) &middot; <span class="mono">$(ConvertTo-IamHtml $row.Id)</span> &middot; $(Get-IamStatusPill $row.Status) &middot; <span class="mono">$(ConvertTo-IamHtml $row.Workspace)</span></p>
          </div>
        </div>
        <div class="actions"><a class="btn" href="/people">Back to people</a></div>
      </div>
      <nav class="section-nav" aria-label="On this page"><a href="#access">Access</a><a href="#roles">Roles and exceptions</a><a href="#hr">HR record</a><a href="#file">Person file</a></nav>

      <div class="panel" id="access">
        <header><h2>Access</h2></header>
        <p class="empty">No providers are configured yet, so there are no accounts to show. Access appears here per application once a provider is added.</p>
      </div>

      <div class="panel" id="roles">
        <header><h2>Roles</h2></header>
        <div class="table-wrap"><table>
          <thead><tr><th>Module</th><th>Version</th><th>From</th><th>Approved</th></tr></thead>
          <tbody>
$roleRows
          </tbody>
        </table></div>
        <div class="sub-h"><h3>Exceptions</h3></div>
        <div class="table-wrap"><table>
          <thead><tr><th>Exception</th><th>Applications</th><th>Ticket</th><th>Expires</th></tr></thead>
          <tbody>
$exceptionRows
          </tbody>
        </table></div>
      </div>

      <div class="panel" id="hr">
        <header><h2>HR record</h2><span class="muted">From $(ConvertTo-IamHtml $hr['source'])</span></header>
        <div class="body"><dl class="kv">$($hrItems -join '')</dl></div>
      </div>

      <div class="panel" id="file">
        <header><h2 class="mono">$(ConvertTo-IamHtml $relative)</h2><span class="muted">Read only. Changes go through HR or an approved request.</span></header>
        <div class="body"><pre class="yaml">$(ConvertTo-IamHtml $fileText)</pre></div>
      </div>
    </section>
"@
    Get-IamLayout -Title $row.Name -Active people -Body $body -Context $Context
}

function Get-IamNotFoundPage {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [hashtable] $Context, [string] $What = 'page')
    $body = @"
    <section class="screen" aria-labelledby="h-404">
      <div class="head"><div><h1 id="h-404">Not found</h1><p>That $(ConvertTo-IamHtml $What) doesn't exist, or it isn't in a loaded workspace.</p></div></div>
      <div class="actions"><a class="btn" href="/people">Go to people</a></div>
    </section>
"@
    Get-IamLayout -Title 'Not found' -Body $body -Context $Context
}
