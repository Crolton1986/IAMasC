#Requires -Version 7.4
<#
.SYNOPSIS
    Downloads the .NET packages listed in deps/IAMasC.Deps.csproj, verifies their SHA-512, and
    extracts the assemblies IAMasC loads into lib/.

.DESCRIPTION
    No .NET SDK is needed. For each PackageReference:
      - lib/net8.0/*.dll, or lib/netstandard2.0/*.dll when there's no net8.0 build, go to lib/
      - runtimes/<rid>/native/* for the platforms IAMasC supports go to lib/runtimes/<rid>/native/
    A package whose hash doesn't match the Sha512 attribute is rejected and nothing is extracted from it.
#>
[CmdletBinding()]
param(
    [string] $Project = (Join-Path $PSScriptRoot '..' 'deps' 'IAMasC.Deps.csproj'),
    [string] $Destination = (Join-Path $PSScriptRoot '..' 'lib'),
    [string] $Cache = (Join-Path $PSScriptRoot '..' 'out' 'nuget-cache'),
    [string[]] $RuntimeIdentifier = @('win-x64', 'win-arm64', 'linux-x64', 'linux-arm64', 'linux-musl-x64', 'osx-x64', 'osx-arm64')
)

$ErrorActionPreference = 'Stop'
[xml] $xml = Get-Content -Path $Project -Raw
$packages = @($xml.Project.ItemGroup.PackageReference | Where-Object { $_ })
if (-not $packages) { throw "No PackageReference entries in $Project." }

$null = New-Item -ItemType Directory -Path $Cache, $Destination -Force

foreach ($p in $packages) {
    $id = $p.Include.ToLowerInvariant()
    $version = $p.Version
    $expected = "$($p.Sha512)".ToLowerInvariant()
    if ($expected -notmatch '^[0-9a-f]{128}$') { throw "$($p.Include) $version has no valid Sha512 attribute." }

    $file = Join-Path $Cache "$id.$version.nupkg"
    if (-not (Test-Path $file)) {
        $uri = "https://api.nuget.org/v3-flatcontainer/$id/$version/$id.$version.nupkg"
        Invoke-WebRequest -Uri $uri -OutFile $file
    }
    $actual = (Get-FileHash -Path $file -Algorithm SHA512).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        Remove-Item $file -Force
        throw "$($p.Include) $version failed its SHA-512 check. Expected $expected, got $actual."
    }

    $zip = [IO.Compression.ZipFile]::OpenRead($file)
    try {
        $entries = $zip.Entries
        $net8 = @($entries | Where-Object FullName -Like 'lib/net8.0/*.dll')
        $managed = @(if ($net8) { $net8 } else { $entries | Where-Object FullName -Like 'lib/netstandard2.0/*.dll' })
        $native = @($entries | Where-Object { $_.FullName -match '^runtimes/([^/]+)/native/[^/]+$' -and $Matches[1] -in $RuntimeIdentifier })

        foreach ($entry in $managed) {
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $Destination $entry.Name), $true)
        }
        foreach ($entry in $native) {
            $target = Join-Path $Destination $entry.FullName.Replace('/', [IO.Path]::DirectorySeparatorChar)
            $null = New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
        }
        Write-Information "OK  $($p.Include) $version ($($managed.Count) assemblies, $($native.Count) native)" -InformationAction Continue
    } finally {
        $zip.Dispose()
    }
}
