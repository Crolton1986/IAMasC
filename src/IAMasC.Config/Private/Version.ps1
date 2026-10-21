function Test-IamVersionConstraint {
    <#
    .SYNOPSIS
        Returns $true when a SemVer version satisfies a constraint.
    .DESCRIPTION
        Supported forms: "1.2.3" or "= 1.2.3" (exact), ">= 1.2" (minimum), and the pessimistic
        "~> 1.2" (>= 1.2, < 2.0) and "~> 1.2.3" (>= 1.2.3, < 1.3.0).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Version,
        [Parameter(Mandatory)] [string] $Constraint
    )

    if ($Constraint -notmatch '^\s*(?<op>~>|>=|=)?\s*(?<ver>\d+(\.\d+){0,2})\s*$') { return $false }
    $op = $Matches.op
    $parts = $Matches.ver.Split('.')
    $floor = [version]((($parts + @('0', '0'))[0..2]) -join '.')
    $actual = [version]$Version

    switch ($op) {
        '>=' { return $actual -ge $floor }
        '~>' {
            if ($parts.Count -le 2) {
                $ceiling = [version]"$([int]$parts[0] + 1).0.0"
            } else {
                $ceiling = [version]"$($parts[0]).$([int]$parts[1] + 1).0"
            }
            return ($actual -ge $floor) -and ($actual -lt $ceiling)
        }
        default { return $actual -eq $floor }
    }
}
