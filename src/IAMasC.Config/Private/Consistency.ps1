function Test-IamWorkspaceConsistency {
    <# Checks that the files in one workspace agree with each other. Returns diagnostics. #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [hashtable] $Context)

    $root = $Context.Root
    $rel = { param($doc) Get-IamRelativePath -Root $root -Path $doc.Path }
    $spec = { param($doc) if ($doc -and $doc.Data) { $doc.Data['spec'] } }

    $wsSpec = & $spec $Context.Workspace
    $declared = @()
    if ($wsSpec -and $wsSpec['requiredProviders'] -is [Collections.IDictionary]) {
        $declared = @($wsSpec['requiredProviders'].Keys)
    }

    # Every provider named in configuration must be declared in requiredProviders.
    $checkProviders = {
        param($doc, $map, [string] $field)
        if ($map -isnot [Collections.IDictionary] -or -not $Context.Workspace) { return }
        foreach ($key in $map.Keys) {
            if ($key -notin $declared) {
                ConvertTo-IamDiagnostic -Severity Error -File (& $rel $doc) -Field "$field.$key" -Message "Provider '$key' isn't in requiredProviders in iamasc.yaml."
            }
        }
    }
    if ($wsSpec) {
        & $checkProviders $Context.Workspace $wsSpec['providers'] 'spec.providers'
        & $checkProviders $Context.Workspace $wsSpec['naming'] 'spec.naming'
        if ($wsSpec['retention'] -is [Collections.IDictionary]) {
            & $checkProviders $Context.Workspace $wsSpec['retention']['overrides'] 'spec.retention.overrides'
        }
    }
    foreach ($p in $Context.Policies) { & $checkProviders $p (& $spec $p)['grants'] 'spec.grants' }
    foreach ($m in $Context.Modules) { & $checkProviders $m (& $spec $m)['grants'] 'spec.grants' }
    foreach ($person in $Context.People) {
        $i = 0
        foreach ($ex in @((& $spec $person)['exceptions'])) {
            if ($ex -is [Collections.IDictionary]) { & $checkProviders $person $ex['grants'] "spec.exceptions[$i].grants" }
            $i++
        }
    }

    # Duplicate names.
    foreach ($group in @(
            @{ Label = 'policy'; Docs = $Context.Policies; Key = { param($d) $d.Name } }
            @{ Label = 'module'; Docs = $Context.Modules; Key = { param($d) "$($d.Data['metadata']['namespace'])/$($d.Name)" } }
            @{ Label = 'person'; Docs = $Context.People; Key = { param($d) $d.Name } }
        )) {
        $seen = @{}
        foreach ($d in $group.Docs) {
            $k = & $group.Key $d
            if (-not $k) { continue }
            if ($seen.ContainsKey($k)) {
                ConvertTo-IamDiagnostic -Severity Error -File (& $rel $d) -Field 'metadata.name' -Message "Another $($group.Label) already uses the name '$k' ($($seen[$k]))."
            } else {
                $seen[$k] = & $rel $d
            }
        }
    }

    # Person files are named after the person.
    foreach ($person in $Context.People) {
        $base = [IO.Path]::GetFileNameWithoutExtension($person.Path)
        if ($person.Name -and $base -ne $person.Name) {
            ConvertTo-IamDiagnostic -Severity Error -File (& $rel $person) -Field 'metadata.name' -Message "File name must match the employee ID: rename to $($person.Name).yaml or fix metadata.name."
        }
    }

    # Module references resolve, and local modules satisfy the version constraint.
    $local = @{}
    foreach ($m in $Context.Modules) { $local["$($m.Data['metadata']['namespace'])/$($m.Name)"] = $m }
    $checkModule = {
        param($doc, [string] $field, $ref)
        if ($ref -isnot [Collections.IDictionary] -or -not $ref['module']) { return }
        $found = $local[$ref['module']]
        if (-not $found) {
            ConvertTo-IamDiagnostic -Severity Warning -File (& $rel $doc) -Field "$field.module" -Message "Module '$($ref['module'])' isn't in this workspace. It must come from a shared module repo or the registry."
        } elseif ($ref['version'] -and -not (Test-IamVersionConstraint -Version $found.Data['metadata']['version'] -Constraint ([string]$ref['version']))) {
            ConvertTo-IamDiagnostic -Severity Error -File (& $rel $doc) -Field "$field.version" -Message "Module '$($ref['module'])' is version $($found.Data['metadata']['version']) here, which doesn't satisfy '$($ref['version'])'."
        }
    }
    foreach ($p in $Context.Policies) {
        $i = 0
        foreach ($u in @((& $spec $p)['use'])) { & $checkModule $p "spec.use[$i]" $u; $i++ }
    }
    $ids = @($Context.People | ForEach-Object Name)
    $today = (Get-Date).ToString('yyyy-MM-dd')
    foreach ($person in $Context.People) {
        $s = & $spec $person
        $i = 0
        foreach ($r in @($s['roles'])) { & $checkModule $person "spec.roles[$i]" $r; $i++ }

        $manager = if ($s['hr'] -is [Collections.IDictionary]) { $s['hr']['manager'] }
        if ($manager -and $manager -notin $ids) {
            ConvertTo-IamDiagnostic -Severity Warning -File (& $rel $person) -Field 'spec.hr.manager' -Message "Manager '$manager' has no person file in this workspace. Approvals that need the manager will wait until they're found."
        }

        $i = 0
        foreach ($ex in @($s['exceptions'])) {
            if ($ex -is [Collections.IDictionary] -and $ex['expires'] -and ([string]$ex['expires']).Substring(0, 10) -lt $today) {
                ConvertTo-IamDiagnostic -Severity Warning -File (& $rel $person) -Field "spec.exceptions[$i].expires" -Message "Expired on $($ex['expires']). The next plan removes this access."
            }
            $i++
        }
    }

    # Approval rules point at chains that exist.
    $apSpec = & $spec $Context.Approvals
    if ($apSpec -and $apSpec['chains'] -is [Collections.IDictionary]) {
        $i = 0
        foreach ($rule in @($apSpec['rules'])) {
            if ($rule -is [Collections.IDictionary] -and $rule['chain'] -and -not $apSpec['chains'].Contains($rule['chain'])) {
                ConvertTo-IamDiagnostic -Severity Error -File (& $rel $Context.Approvals) -Field "spec.rules[$i].chain" -Message "No chain named '$($rule['chain'])' in spec.chains."
            }
            $i++
        }
    }

    # Notification routes use channels that exist.
    $nSpec = & $spec $Context.Notifications
    if ($nSpec -and $nSpec['channels'] -is [Collections.IDictionary]) {
        $i = 0
        foreach ($route in @($nSpec['routes'])) {
            if ($route -is [Collections.IDictionary]) {
                foreach ($via in @($route['via'])) {
                    if ($via -and -not $nSpec['channels'].Contains($via)) {
                        ConvertTo-IamDiagnostic -Severity Error -File (& $rel $Context.Notifications) -Field "spec.routes[$i].via" -Message "No channel named '$via' in spec.channels."
                    }
                }
            }
            $i++
        }
    }

    # Every required provider is pinned in the lock file.
    if ($wsSpec -and $Context.Lock) {
        $locked = $Context.Lock.Data['providers']
        foreach ($name in $declared) {
            $source = $wsSpec['requiredProviders'][$name]['source']
            if ($locked -isnot [Collections.IDictionary] -or -not $locked.Contains($source)) {
                ConvertTo-IamDiagnostic -Severity Warning -File '.iamasc.lock.yaml' -Field "providers.$source" -Message "Not pinned. Run 'iamasc init' to lock it."
            }
        }
    }
}
