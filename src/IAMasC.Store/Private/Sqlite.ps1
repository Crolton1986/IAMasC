$script:SqliteReady = $false

function Get-IamRuntimeIdentifier {
    <# The NuGet runtime identifier for this machine, e.g. linux-x64 or win-arm64. #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $arch = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant()
    if ($IsWindows) { return "win-$arch" }
    if ($IsMacOS) { return "osx-$arch" }
    # Alpine and other musl-based distributions need the musl build.
    $musl = @(Get-ChildItem -Path '/lib' -Filter 'ld-musl-*' -ErrorAction SilentlyContinue).Count -gt 0
    if ($musl) { return "linux-musl-$arch" }
    "linux-$arch"
}

function Get-IamLibraryPath {
    <# Where the restored .NET assemblies live: $env:IAMASC_LIB, or lib/ at the repo or package root. #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:IAMASC_LIB) { return $env:IAMASC_LIB }
    Join-Path $PSScriptRoot '..' '..' '..' 'lib'
}

function Initialize-IamSqlite {
    <# Loads Microsoft.Data.Sqlite and the native SQLite library once per process. #>
    [CmdletBinding()]
    param()

    if ($script:SqliteReady) { return }
    $lib = Get-IamLibraryPath
    $managed = 'SQLitePCLRaw.core', 'SQLitePCLRaw.provider.e_sqlite3', 'SQLitePCLRaw.batteries_v2', 'Microsoft.Data.Sqlite'
    $missing = $managed | Where-Object { -not (Test-Path (Join-Path $lib "$_.dll")) }
    if ($missing) {
        throw "SQLite libraries not found in '$lib'. Run ./build.ps1 -Task Bootstrap, or set IAMASC_LIB."
    }

    $loaded = [AppDomain]::CurrentDomain.GetAssemblies().GetName().Name
    foreach ($name in $managed) {
        if ($name -notin $loaded) { $null = [Reflection.Assembly]::LoadFrom((Join-Path $lib "$name.dll")) }
    }

    # Load the native library by full path first, so the provider's DllImport finds it.
    $rid = Get-IamRuntimeIdentifier
    $file = if ($IsWindows) { 'e_sqlite3.dll' } elseif ($IsMacOS) { 'libe_sqlite3.dylib' } else { 'libe_sqlite3.so' }
    $native = Join-Path $lib 'runtimes' $rid 'native' $file
    if (-not (Test-Path $native)) { throw "No native SQLite build for $rid at '$native'." }
    $null = [Runtime.InteropServices.NativeLibrary]::Load($native)

    [SQLitePCL.Batteries_V2]::Init()
    $script:SqliteReady = $true
}

function Add-IamSqlParameter {
    <# Binds a hashtable of parameters to a command. Names may be given with or without '@'. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Command,
        [Collections.IDictionary] $Parameters
    )

    if (-not $Parameters) { return }
    foreach ($key in $Parameters.Keys) {
        $name = if ($key.StartsWith('@')) { $key } else { "@$key" }
        $value = $Parameters[$key]
        if ($null -eq $value) {
            $value = [DBNull]::Value
        } elseif ($value -is [datetime]) {
            $value = $value.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        } elseif ($value -is [datetimeoffset]) {
            $value = $value.UtcDateTime.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        } elseif ($value -is [bool]) {
            $value = [int]$value
        }
        $null = $Command.Parameters.AddWithValue($name, $value)
    }
}

function Invoke-IamSqlCommand {
    <#
    .SYNOPSIS
        Runs one statement and always disposes the command.
    .DESCRIPTION
        SQLite only closes the database file once every statement is finalized. A command left
        undisposed (for example after an exception) keeps the file open, which on Windows blocks
        deleting or moving it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string] $Sql,
        [Collections.IDictionary] $Parameters,
        $Transaction,
        [ValidateSet('NonQuery', 'Scalar')] [string] $Mode = 'NonQuery'
    )

    $cmd = $Connection.CreateCommand()
    try {
        if ($Transaction) { $cmd.Transaction = $Transaction }
        $cmd.CommandText = $Sql
        Add-IamSqlParameter -Command $cmd -Parameters $Parameters
        if ($Mode -eq 'Scalar') { $cmd.ExecuteScalar() } else { $cmd.ExecuteNonQuery() }
    } finally {
        $cmd.Dispose()
    }
}
