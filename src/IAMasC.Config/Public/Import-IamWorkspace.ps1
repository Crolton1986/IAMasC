function Import-IamWorkspace {
    <#
    .SYNOPSIS
        Loads every IAMasC file in a workspace folder, validates each one, and checks that they agree.
    .DESCRIPTION
        Expected layout (see docs/concept.md):
            iamasc.yaml, lifecycle.yaml, approvals.yaml, notifications.yaml, .iamasc.lock.yaml,
            policies/*.yaml, modules/*/module.yaml, people/*.yaml
        Only iamasc.yaml is required. Every problem is returned as a diagnostic; nothing throws
        for invalid configuration.
    .EXAMPLE
        $ws = Import-IamWorkspace -Path ./examples/corp-chicago
        $ws.Diagnostics | Where-Object Severity -EQ Error
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string] $Path)

    $root = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $diagnostics = [Collections.Generic.List[object]]::new()
    $add = { param($d) foreach ($x in $d) { $diagnostics.Add($x) } }

    function Read-One([string] $relative, [string] $expectedKind, [bool] $required) {
        $file = Join-Path $root $relative
        if (-not (Test-Path -LiteralPath $file)) {
            if ($required) {
                & $add (ConvertTo-IamDiagnostic -Severity Error -File $relative -Message 'Missing. Every workspace needs this file.')
            }
            return $null
        }
        $doc = Import-IamDocument -Path $file -Root $root
        & $add $doc.Diagnostics
        if ($doc.Kind -and $doc.Kind -ne $expectedKind) {
            & $add (ConvertTo-IamDiagnostic -Severity Error -File $relative -Field 'kind' -Message "Expected kind $expectedKind in this file, found $($doc.Kind).")
            return $null
        }
        $doc
    }

    function Read-Many([string[]] $files, [string] $expectedKind) {
        foreach ($file in $files) {
            $relative = Get-IamRelativePath -Root $root -Path $file
            $doc = Import-IamDocument -Path $file -Root $root
            & $add $doc.Diagnostics
            if ($doc.Kind -and $doc.Kind -ne $expectedKind) {
                & $add (ConvertTo-IamDiagnostic -Severity Error -File $relative -Field 'kind' -Message "Files in this folder must be kind $expectedKind, found $($doc.Kind).")
                continue
            }
            if ($doc.Data) { $doc }
        }
    }

    $yamlIn = { param($folder) Get-ChildItem -LiteralPath (Join-Path $root $folder) -File -ErrorAction SilentlyContinue | Where-Object Extension -In '.yaml', '.yml' | Sort-Object Name }

    $workspace = Read-One 'iamasc.yaml' 'Workspace' $true
    $lifecycle = Read-One 'lifecycle.yaml' 'Lifecycle' $false
    $approvals = Read-One 'approvals.yaml' 'ApprovalPolicy' $false
    $notifications = Read-One 'notifications.yaml' 'Notifications' $false
    $lock = Read-One '.iamasc.lock.yaml' 'Lock' $false
    $policies = @(Read-Many (& $yamlIn 'policies').FullName 'Policy')
    $moduleFiles = Get-ChildItem -LiteralPath (Join-Path $root 'modules') -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'module.yaml' } | Where-Object { Test-Path -LiteralPath $_ }
    $modules = @(Read-Many $moduleFiles 'Module')
    $people = @(Read-Many (& $yamlIn 'people').FullName 'Person')

    if (-not $lifecycle) {
        & $add (ConvertTo-IamDiagnostic -Severity Warning -File 'lifecycle.yaml' -Message 'Missing. Without it IAMasC uses the default lifecycle.')
    }

    $context = @{
        Root          = $root
        Workspace     = $workspace
        Lifecycle     = $lifecycle
        Approvals     = $approvals
        Notifications = $notifications
        Lock          = $lock
        Policies      = $policies
        Modules       = $modules
        People        = $people
    }
    & $add (Test-IamWorkspaceConsistency -Context $context)

    [pscustomobject]@{
        PSTypeName    = 'IAMasC.Workspace'
        Path          = $root
        Name          = if ($workspace) { $workspace.Name } else { $null }
        Workspace     = $workspace
        Lifecycle     = $lifecycle
        Approvals     = $approvals
        Notifications = $notifications
        Lock          = $lock
        Policies      = $policies
        Modules       = $modules
        People        = $people
        Diagnostics   = $diagnostics
    }
}
