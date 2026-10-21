#Requires -Version 7.4
# Downloads one small package from nuget.org.

BeforeAll {
    $script:tool = Join-Path $PSScriptRoot '..' '..' 'tools' 'Restore-NuGetPackage.ps1'
    $script:cache = Join-Path $PSScriptRoot '..' '..' 'out' 'nuget-cache'

    function Write-TestProject([string] $Sha512) {
        $file = Join-Path $TestDrive "$([guid]::NewGuid()).csproj"
        Set-Content -Path $file -Value @"
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="SQLitePCLRaw.core" Version="2.1.13" Sha512="$Sha512" />
  </ItemGroup>
</Project>
"@
        $file
    }
}

Describe 'Restore-NuGetPackage' {
    It 'extracts a package whose hash matches' {
        $sha = '0cd8e19fb092ed60e7067adc211fba88a2d66602233318ffd579cf335dc8b9d146935223ab8d409bd7c14e26b22aeff37c80524ad6eebafc807ab67c8d43f175'
        $out = Join-Path $TestDrive 'good'
        & $tool -Project (Write-TestProject $sha) -Destination $out -Cache $cache 6>$null
        Join-Path $out 'SQLitePCLRaw.core.dll' | Should -Exist
    }

    It 'rejects a package whose hash does not match and extracts nothing' {
        $out = Join-Path $TestDrive 'bad'
        $badCache = Join-Path $TestDrive 'cache'
        { & $tool -Project (Write-TestProject ('0' * 128)) -Destination $out -Cache $badCache 6>$null } | Should -Throw '*failed its SHA-512 check*'
        Join-Path $out 'SQLitePCLRaw.core.dll' | Should -Not -Exist
        @(Get-ChildItem $badCache -Filter '*.nupkg').Count | Should -Be 0
    }

    It 'rejects a reference without a hash' {
        { & $tool -Project (Write-TestProject '') -Destination (Join-Path $TestDrive 'none') -Cache $cache } | Should -Throw '*no valid Sha512*'
    }
}
