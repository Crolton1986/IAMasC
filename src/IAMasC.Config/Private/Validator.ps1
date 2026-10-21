# A small JSON Schema validator for the keywords IAMasC's schemas use.
#
# Test-Json can't be relied on here: from PowerShell 7.6 it returns $false for nested failures
# without saying what failed. This validator gives the same answer on every PowerShell version
# and reports each problem with a field path. Units.Tests.ps1 fails if a schema uses a keyword
# that isn't listed in $script:SupportedSchemaKeywords.

$script:SupportedSchemaKeywords = @(
    '$schema', '$id', 'title', 'description', 'examples', 'default',
    'type', 'properties', 'required', 'additionalProperties', 'propertyNames',
    'minProperties', 'maxProperties', 'items', 'minItems', 'uniqueItems',
    'enum', 'const', 'pattern', 'minLength', 'minimum', 'anyOf', 'oneOf'
)

function Get-IamJsonType {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] $Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return 'boolean' }
    if ($Value -is [string]) { return 'string' }
    if ($Value -is [Collections.IDictionary]) { return 'object' }
    if ($Value -is [Collections.IList]) { return 'array' }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [short] -or $Value -is [byte] -or $Value -is [Numerics.BigInteger]) { return 'integer' }
    if ($Value -is [double] -or $Value -is [decimal] -or $Value -is [single]) {
        if ([Math]::Floor([double]$Value) -eq [double]$Value) { return 'integer' }
        return 'number'
    }
    'string'
}

function Join-IamFieldPath {
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Parent, $Child)
    if ($Child -is [int]) { return "$Parent[$Child]" }
    if ($Parent) { return "$Parent.$Child" }
    [string]$Child
}

function Format-IamJsonValue {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] $Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }
    [string]$Value
}

function Test-IamJsonSchema {
    <#
    .SYNOPSIS
        Validates a value against a schema. Returns @{ Field; Message } for each problem.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()] $Value,
        [Parameter(Mandatory)] [Collections.IDictionary] $Schema,
        [string] $Field = ''
    )

    $actual = Get-IamJsonType -Value $Value

    if ($Schema.Contains('type')) {
        $allowed = @($Schema['type'])
        $ok = $allowed -contains $actual -or ($actual -eq 'integer' -and $allowed -contains 'number')
        if (-not $ok) {
            @{ Field = $Field; Message = "Expected $($allowed -join ' or '), found $actual." }
            return
        }
    }

    if ($Schema.Contains('const') -and (Format-IamJsonValue $Value) -cne (Format-IamJsonValue $Schema['const'])) {
        @{ Field = $Field; Message = "Must be '$(Format-IamJsonValue $Schema['const'])'." }
    }
    if ($Schema.Contains('enum') -and -not (@($Schema['enum'] | ForEach-Object { Format-IamJsonValue $_ }) -ccontains (Format-IamJsonValue $Value))) {
        @{ Field = $Field; Message = "Must be one of: $(@($Schema['enum'] | ForEach-Object { Format-IamJsonValue $_ }) -join ', ')." }
    }

    if ($actual -eq 'string') {
        if ($Schema.Contains('minLength') -and $Value.Length -lt $Schema['minLength']) {
            @{ Field = $Field; Message = 'Must not be empty.' }
        }
        if ($Schema.Contains('pattern') -and $Value -cnotmatch $Schema['pattern']) {
            @{ Field = $Field; Message = "'$Value' isn't in the expected format ($($Schema['pattern']))." }
        }
    }

    if (($actual -eq 'integer' -or $actual -eq 'number') -and $Schema.Contains('minimum') -and [double]$Value -lt [double]$Schema['minimum']) {
        @{ Field = $Field; Message = "Must be at least $($Schema['minimum'])." }
    }

    if ($actual -eq 'object') {
        $properties = if ($Schema.Contains('properties')) { $Schema['properties'] } else { @{} }

        $missing = @($Schema['required'] | Where-Object { $_ -and -not $Value.Contains($_) })
        if ($missing) {
            @{ Field = $Field; Message = "Missing required field(s): $($missing -join ', ')." }
        }
        if ($Schema.Contains('minProperties') -and $Value.Count -lt $Schema['minProperties']) {
            @{ Field = $Field; Message = "Needs at least $($Schema['minProperties']) entr$(if ($Schema['minProperties'] -eq 1) { 'y' } else { 'ies' })." }
        }
        if ($Schema.Contains('maxProperties') -and $Value.Count -gt $Schema['maxProperties']) {
            @{ Field = $Field; Message = "Allows at most $($Schema['maxProperties']) entr$(if ($Schema['maxProperties'] -eq 1) { 'y' } else { 'ies' })." }
        }

        foreach ($key in @($Value.Keys)) {
            $child = Join-IamFieldPath -Parent $Field -Child ([string]$key)
            if ($Schema.Contains('propertyNames')) {
                foreach ($p in Test-IamJsonSchema -Value ([string]$key) -Schema $Schema['propertyNames'] -Field $child) {
                    @{ Field = $child; Message = "Name isn't allowed here. $($p.Message)" }
                }
            }
            if ($properties.Contains($key)) {
                Test-IamJsonSchema -Value $Value[$key] -Schema $properties[$key] -Field $child
            } elseif ($Schema.Contains('additionalProperties')) {
                $extra = $Schema['additionalProperties']
                if ($extra -is [bool]) {
                    if (-not $extra) { @{ Field = $child; Message = 'Unknown field. Check the spelling, or remove it.' } }
                } else {
                    Test-IamJsonSchema -Value $Value[$key] -Schema $extra -Field $child
                }
            }
        }
    }

    if ($actual -eq 'array') {
        if ($Schema.Contains('minItems') -and $Value.Count -lt $Schema['minItems']) {
            @{ Field = $Field; Message = "Needs at least $($Schema['minItems']) item(s)." }
        }
        if ($Schema['uniqueItems']) {
            $seen = @{}
            foreach ($item in $Value) {
                $k = Format-IamJsonValue $item
                if ($seen.ContainsKey($k)) { @{ Field = $Field; Message = "'$k' is listed more than once." } }
                $seen[$k] = $true
            }
        }
        if ($Schema.Contains('items')) {
            for ($i = 0; $i -lt $Value.Count; $i++) {
                Test-IamJsonSchema -Value $Value[$i] -Schema $Schema['items'] -Field (Join-IamFieldPath -Parent $Field -Child $i)
            }
        }
    }

    foreach ($keyword in 'anyOf', 'oneOf') {
        if (-not $Schema.Contains($keyword)) { continue }
        $passing = 0
        $closest = $null
        foreach ($branch in $Schema[$keyword]) {
            $problems = [Collections.Generic.List[object]]::new()
            foreach ($p in Test-IamJsonSchema -Value $Value -Schema $branch -Field $Field) { $problems.Add($p) }
            if ($problems.Count -eq 0) { $passing++; continue }
            # The closest branch is one whose own type check passed, with the fewest problems.
            $wrongType = $false
            foreach ($p in $problems) {
                if ($p.Field -eq $Field -and $p.Message -like 'Expected *, found *') { $wrongType = $true }
            }
            if (-not $wrongType -and ($null -eq $closest -or $problems.Count -lt $closest.Count)) { $closest = $problems }
        }
        if ($keyword -eq 'oneOf' -and $passing -gt 1) {
            @{ Field = $Field; Message = 'Matches more than one allowed form. Use only one of the alternatives.' }
        } elseif ($passing -eq 0) {
            if ($closest) {
                $closest
            } else {
                $types = @($Schema[$keyword] | ForEach-Object { if ($_.Contains('type')) { $_['type'] } elseif ($_.Contains('const')) { "'$($_['const'])'" } } | Select-Object -Unique)
                @{ Field = $Field; Message = "Expected $($types -join ' or '), found $actual." }
            }
        }
    }
}
