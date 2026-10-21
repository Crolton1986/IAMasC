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

    It '<Name> is draft 2020-12 JSON Schema' -ForEach $schemas {
        (Get-Content -Path $Path -Raw | ConvertFrom-Json).'$schema' | Should -Be 'https://json-schema.org/draft/2020-12/schema'
    }

    It '<Name> only uses keywords the validator supports' -ForEach $schemas {
        $schema = Get-Content -Path $Path -Raw | ConvertFrom-Json -AsHashtable
        InModuleScope IAMasC.Config -Parameters @{ Schema = $schema } {
            function Get-Keyword($node) {
                if ($node -is [Collections.IDictionary]) {
                    foreach ($k in $node.Keys) {
                        $k
                        $v = $node[$k]
                        if ($k -in 'properties') { foreach ($p in $v.Values) { Get-Keyword $p } }
                        elseif ($k -in 'anyOf', 'oneOf') { foreach ($b in $v) { Get-Keyword $b } }
                        elseif ($k -in 'items', 'additionalProperties', 'propertyNames') { Get-Keyword $v }
                    }
                }
            }
            $unsupported = @(Get-Keyword $Schema | Where-Object { $_ -notin $script:SupportedSchemaKeywords } | Select-Object -Unique)
            $unsupported | Should -BeNullOrEmpty -Because 'Validator.ps1 would silently ignore them'
        }
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

Describe 'Test-IamJsonSchema' {
    It 'reports <Case>' -ForEach @(
        @{ Case = 'a wrong type'; Value = 'x'; Schema = @{ type = 'integer' }; Field = ''; Message = 'Expected integer, found string.' }
        @{ Case = 'a missing field'; Value = [ordered]@{}; Schema = @{ type = 'object'; required = @('a', 'b') }; Field = ''; Message = 'Missing required field(s): a, b.' }
        @{ Case = 'an unknown field'; Value = [ordered]@{ zz = 1 }; Schema = @{ type = 'object'; properties = @{}; additionalProperties = $false }; Field = 'zz'; Message = 'Unknown field*' }
        @{ Case = 'a nested problem with its path'; Value = [ordered]@{ a = @([ordered]@{ b = 5 }) }; Schema = @{ properties = @{ a = @{ items = @{ properties = @{ b = @{ type = 'string' } } } } } }; Field = 'a[0].b'; Message = 'Expected string*' }
        @{ Case = 'a value outside an enum'; Value = 'x'; Schema = @{ enum = @('a', 'b') }; Field = ''; Message = 'Must be one of: a, b.' }
        @{ Case = 'a pattern mismatch'; Value = 'abc'; Schema = @{ type = 'string'; pattern = '^\d+$' }; Field = ''; Message = "'abc' isn't in the expected format*" }
        @{ Case = 'a duplicate in a unique list'; Value = @('a', 'a'); Schema = @{ uniqueItems = $true }; Field = ''; Message = "'a' is listed more than once." }
        @{ Case = 'no anyOf branch matching'; Value = 5; Schema = @{ anyOf = @(@{ type = 'string' }, @{ type = 'null' }) }; Field = ''; Message = 'Expected string or null, found integer.' }
        @{ Case = 'two oneOf branches matching'; Value = [ordered]@{ repo = 'r'; path = 'p' }; Schema = @{ oneOf = @(@{ required = @('repo') }, @{ required = @('path') }) }; Field = ''; Message = 'Matches more than one*' }
        @{ Case = 'a bad property name'; Value = [ordered]@{ Bogus = 1 }; Schema = @{ propertyNames = @{ enum = @('Pending') } }; Field = 'Bogus'; Message = "Name isn't allowed here*" }
    ) {
        InModuleScope IAMasC.Config -Parameters $_ {
            $problems = @(Test-IamJsonSchema -Value $Value -Schema $Schema)
            $problems.Count | Should -Be 1
            $problems[0].Field | Should -Be $Field
            $problems[0].Message | Should -BeLike $Message
        }
    }

    It 'accepts <Case>' -ForEach @(
        @{ Case = 'an integer where a number is allowed'; Value = 3; Schema = @{ type = 'number' } }
        @{ Case = 'a whole double as an integer'; Value = [double]3; Schema = @{ type = 'integer' } }
        @{ Case = 'one matching anyOf branch'; Value = 'never'; Schema = @{ anyOf = @(@{ type = 'string'; pattern = '^[0-9]+d$' }, @{ const = 'never' }) } }
        @{ Case = 'null where null is allowed'; Value = $null; Schema = @{ type = @('string', 'null') } }
    ) {
        InModuleScope IAMasC.Config -Parameters $_ {
            @(Test-IamJsonSchema -Value $Value -Schema $Schema) | Should -BeNullOrEmpty
        }
    }
}

Describe 'Join-IamFieldPath' {
    It 'joins <Parent> and <Child> into <Expected>' -ForEach @(
        @{ Parent = ''; Child = 'spec'; Expected = 'spec' }
        @{ Parent = 'spec'; Child = 'roles'; Expected = 'spec.roles' }
        @{ Parent = 'spec.roles'; Child = 0; Expected = 'spec.roles[0]' }
    ) {
        InModuleScope IAMasC.Config -Parameters $_ {
            Join-IamFieldPath -Parent $Parent -Child $Child | Should -Be $Expected
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
