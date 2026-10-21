function ConvertTo-IamDiagnostic {
    <# Builds one diagnostic record. Severity is Error or Warning. #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateSet('Error', 'Warning')] [string] $Severity,
        [Parameter(Mandatory)] [string] $File,
        [string] $Field = '',
        [Parameter(Mandatory)] [string] $Message
    )
    [pscustomobject]@{
        PSTypeName = 'IAMasC.Diagnostic'
        Severity   = $Severity
        File       = $File
        Field      = $Field
        Message    = $Message
    }
}

function Get-IamRelativePath {
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Root, [string] $Path)
    if (-not $Root) { return $Path }
    [IO.Path]::GetRelativePath($Root, $Path) -replace '\\', '/'
}
