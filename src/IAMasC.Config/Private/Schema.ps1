$script:SchemaCache = @{}
$script:SchemaFolder = Join-Path $PSScriptRoot '..' 'schemas'

# Kinds this release understands, mapped to their schema file.
$script:KnownKinds = [ordered]@{
    Workspace      = 'workspace'
    Lifecycle      = 'lifecycle'
    ApprovalPolicy = 'approvalpolicy'
    Notifications  = 'notifications'
    Policy         = 'policy'
    Module         = 'module'
    Person         = 'person'
    Lock           = 'lock'
    Server         = 'server'
}

function Get-IamSchema {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Kind)

    $file = $script:KnownKinds[$Kind]
    if (-not $file) { throw "No schema for kind '$Kind'." }
    if (-not $script:SchemaCache.ContainsKey($file)) {
        $script:SchemaCache[$file] = Get-Content -Path (Join-Path $script:SchemaFolder "$file.schema.json") -Raw
    }
    $script:SchemaCache[$file]
}

function ConvertTo-IamSchemaMessage {
    <# Rewrites Test-Json messages into something a person editing YAML can act on. #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string] $Raw)

    $prefix = 'The JSON is not valid with the schema:'
    $text = if ($Raw.StartsWith($prefix)) { $Raw.Substring($prefix.Length).Trim() } else { $Raw }
    $pointer = ''
    if ($text -match "^(?<msg>.*) at '(?<ptr>[^']*)'$") {
        $text = $Matches.msg
        $pointer = $Matches.ptr
    }
    if ($text -match 'fail against the false schema') {
        $text = 'Unknown field. Check the spelling, or remove it.'
    } elseif ($text -match '^Required properties \[(?<names>[^\]]*)\] are not present$') {
        $text = "Missing required field(s): $($Matches.names.Replace('"', ''))."
    }
    [pscustomobject]@{ Field = ConvertTo-IamFieldPath -Pointer $pointer; Message = $text }
}
