#Requires -Version 7.4

BeforeAll {
    $script:repo = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
    Import-Module (Join-Path $repo 'src' 'IAMasC.Config' 'IAMasC.Config.psd1') -Force
}

Describe 'Schemas' {
    BeforeDiscovery {
        $folder = Join-Path $PSScriptRoot '..' '..' 'src' 'IAMasC.Config' 'schemas'
        $script:schemas = Get-ChildItem -Path $folder -Filter '*.schema.json' | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    }

    It '<Name> is a usable JSON Schema' -ForEach $schemas {
        $schema = Get-Content -Path $Path -Raw
        { Test-Json -Json '{}' -Schema $schema -ErrorAction SilentlyContinue } | Should -Not -Throw
        ($schema | ConvertFrom-Json).'$schema' | Should -Be 'https://json-schema.org/draft/2020-12/schema'
    }
}

Describe 'Test-IamVersionConstraint' {
    It '<Version> satisfies <Constraint>: <Expected>' -ForEach @(
        @{ Version = '1.2.0'; Constraint = '1.2.0'; Expected = $true }
        @{ Version = '1.2.1'; Constraint = '1.2.0'; Expected = $false }
        @{ Version = '1.4.0'; Constraint = '~> 1.0'; Expected = $true }
        @{ Version = '2.0.0'; Constraint = '~> 1.0'; Expected = $false }
        @{ Version = '1.2.9'; Constraint = '~> 1.2.3'; Expected = $true }
        @{ Version = '1.3.0'; Constraint = '~> 1.2.3'; Expected = $false }
        @{ Version = '1.2.2'; Constraint = '~> 1.2.3'; Expected = $false }
        @{ Version = '3.0.0'; Constraint = '>= 1.5'; Expected = $true }
        @{ Version = '1.4.9'; Constraint = '>= 1.5'; Expected = $false }
        @{ Version = '1.0.0'; Constraint = 'latest'; Expected = $false }
    ) {
        InModuleScope IAMasC.Config -Parameters $_ {
            Test-IamVersionConstraint -Version $Version -Constraint $Constraint | Should -Be $Expected
        }
    }
}

Describe 'ConvertTo-IamFieldPath' {
    It 'turns <Pointer> into <Expected>' -ForEach @(
        @{ Pointer = ''; Expected = '' }
        @{ Pointer = '/spec'; Expected = 'spec' }
        @{ Pointer = '/spec/roles/0/module'; Expected = 'spec.roles[0].module' }
        @{ Pointer = '/providers/iamasc~1workday'; Expected = 'providers.iamasc/workday' }
    ) {
        InModuleScope IAMasC.Config -Parameters $_ {
            ConvertTo-IamFieldPath -Pointer $Pointer | Should -Be $Expected
        }
    }
}

Describe 'Find-IamPlaintextSecret' {
    It 'finds plain strings under credential-like keys and ignores references' {
        InModuleScope IAMasC.Config {
            $node = [ordered]@{
                a = [ordered]@{ password = 'x'; token = [ordered]@{ secret = 'vault-name' } }
                b = @([ordered]@{ clientSecret = 'y' })
                c = [ordered]@{ secret = 'reference-only' }
            }
            @(Find-IamPlaintextSecret -Node $node) | Should -Be @('a.password', 'b[0].clientSecret')
        }
    }
}
