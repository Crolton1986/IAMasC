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

function ConvertTo-IamFieldPath {
    <# Turns a JSON pointer like /spec/roles/0/module into spec.roles[0].module. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Pointer)

    $path = ''
    foreach ($segment in ($Pointer -split '/' | Where-Object { $_ -ne '' })) {
        $segment = $segment.Replace('~1', '/').Replace('~0', '~')
        if ($segment -match '^\d+$') {
            $path += "[$segment]"
        } elseif ($path) {
            $path += ".$segment"
        } else {
            $path = $segment
        }
    }
    $path
}

function Get-IamRelativePath {
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Root, [string] $Path)
    if (-not $Root) { return $Path }
    [IO.Path]::GetRelativePath($Root, $Path) -replace '\\', '/'
}
