function Import-IamServerSetting {
    <#
    .SYNOPSIS
        Loads and validates the server settings file (kind: Server).
    .EXAMPLE
        Import-IamServerSetting -Path ./examples/server/iamasc-server.yaml
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string] $Path)

    $file = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $root = Split-Path $file -Parent
    $doc = Import-IamDocument -Path $file -Root $root
    $display = Split-Path $file -Leaf

    if ($doc.Kind -and $doc.Kind -ne 'Server') {
        $doc.Diagnostics.Add((ConvertTo-IamDiagnostic -Severity Error -File $display -Field 'kind' -Message "Expected kind Server, found $($doc.Kind)."))
        return $doc
    }

    $spec = if ($doc.Data) { $doc.Data['spec'] }
    if ($spec -and $spec['workspaces']) {
        $seen = @{}
        $i = 0
        foreach ($ws in @($spec['workspaces'])) {
            $name = if ($ws -is [Collections.IDictionary]) { $ws['name'] }
            if ($name -and $seen.ContainsKey($name)) {
                $doc.Diagnostics.Add((ConvertTo-IamDiagnostic -Severity Error -File $display -Field "spec.workspaces[$i].name" -Message "Workspace '$name' is listed twice."))
            }
            if ($name) { $seen[$name] = $true }
            $i++
        }
    }
    $doc
}
