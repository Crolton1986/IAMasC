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
    <# Returns the parsed schema for a kind, cached per session. #>
    [CmdletBinding()]
    [OutputType([Collections.IDictionary])]
    param([Parameter(Mandatory)] [string] $Kind)

    $file = $script:KnownKinds[$Kind]
    if (-not $file) { throw "No schema for kind '$Kind'." }
    if (-not $script:SchemaCache.ContainsKey($file)) {
        $path = Join-Path $script:SchemaFolder "$file.schema.json"
        $script:SchemaCache[$file] = Get-Content -Path $path -Raw | ConvertFrom-Json -AsHashtable
    }
    $script:SchemaCache[$file]
}
