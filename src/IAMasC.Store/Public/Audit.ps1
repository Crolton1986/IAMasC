function Write-IamAudit {
    <#
    .SYNOPSIS
        Appends one entry to the audit log. Entries can never be changed or deleted.
    .EXAMPLE
        Write-IamAudit -Store $store -Actor jlee -Action person.created -Workspace corp-chicago `
            -Target person/E-004611 -After @{ department = 'Human Resources' }
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Store,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Actor,
        [Parameter(Mandatory)] [ValidatePattern('^[a-z][a-z0-9]*(\.[a-z][a-zA-Z0-9]*)+$')] [string] $Action,
        [string] $Workspace,
        [string] $Target,
        $Before,
        $After,
        [string] $CorrelationId
    )

    $toJson = { param($v) if ($null -eq $v) { $null } else { $v | ConvertTo-Json -Depth 32 -Compress } }
    $null = Invoke-IamNonQuery -Store $Store -Sql @'
INSERT INTO audit (at, actor, action, workspace, target, before_json, after_json, correlation_id)
VALUES (@at, @actor, @action, @workspace, @target, @before, @after, @correlation)
'@ -Parameters @{
        at          = [datetime]::UtcNow
        actor       = $Actor
        action      = $Action
        workspace   = $Workspace
        target      = $Target
        before      = & $toJson $Before
        after       = & $toJson $After
        correlation = $CorrelationId
    }
    (Invoke-IamQuery -Store $Store -Sql 'SELECT last_insert_rowid() AS id').id
}

function Get-IamAudit {
    <#
    .SYNOPSIS
        Reads audit entries, newest first.
    .EXAMPLE
        Get-IamAudit -Store $store -Target person/E-004611
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Store,
        [string] $Target,
        [string] $Workspace,
        [string] $Actor,
        [datetime] $Since,
        [ValidateRange(1, 10000)] [int] $Limit = 100
    )

    $where = [Collections.Generic.List[string]]::new()
    $params = @{ limit = $Limit }
    if ($Target) { $where.Add('target = @target'); $params.target = $Target }
    if ($Workspace) { $where.Add('workspace = @workspace'); $params.workspace = $Workspace }
    if ($Actor) { $where.Add('actor = @actor'); $params.actor = $Actor }
    if ($PSBoundParameters.ContainsKey('Since')) { $where.Add('at >= @since'); $params.since = $Since }
    $clause = if ($where.Count) { 'WHERE ' + ($where -join ' AND ') } else { '' }

    foreach ($row in Invoke-IamQuery -Store $Store -Sql "SELECT * FROM audit $clause ORDER BY id DESC LIMIT @limit" -Parameters $params) {
        [pscustomobject]@{
            PSTypeName    = 'IAMasC.AuditEntry'
            Id            = $row.id
            At            = [datetime]::Parse($row.at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            Actor         = $row.actor
            Action        = $row.action
            Workspace     = $row.workspace
            Target        = $row.target
            Before        = if ($row.before_json) { $row.before_json | ConvertFrom-Json } else { $null }
            After         = if ($row.after_json) { $row.after_json | ConvertFrom-Json } else { $null }
            CorrelationId = $row.correlation_id
        }
    }
}
