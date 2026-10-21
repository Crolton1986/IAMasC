#Requires -Version 7.4
# Each case copies examples/corp-chicago, breaks one rule, and expects exactly that diagnostic.

BeforeAll {
    $script:repo = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
    Import-Module (Join-Path $repo 'src' 'IAMasC.Config' 'IAMasC.Config.psd1') -Force
    $script:example = Join-Path $repo 'examples' 'corp-chicago'

    function Copy-TestWorkspace {
        $target = Join-Path $TestDrive ([guid]::NewGuid())
        Copy-Item -Path $example -Destination $target -Recurse
        $target
    }

    function Edit-TestFile([string] $Workspace, [string] $Relative, [string] $Find, [string] $Replace) {
        $file = Join-Path $Workspace $Relative
        $text = Get-Content -Path $file -Raw
        if (-not $text.Contains($Find)) { throw "Test setup: '$Find' not found in $Relative" }
        Set-Content -Path $file -Value $text.Replace($Find, $Replace) -NoNewline
    }

    function Get-Error($Result) { @($Result.Diagnostics | Where-Object Severity -EQ 'Error') }
}

Describe 'Import-IamWorkspace' {
    Context 'the shipped example' {
        BeforeAll { $script:ws = Import-IamWorkspace -Path $example }

        It 'has no errors' {
            Get-Error $ws | Should -BeNullOrEmpty
        }

        It 'loads every file' {
            $ws.Name | Should -Be 'corp-chicago'
            $ws.People.Count | Should -Be 3
            $ws.Modules.Count | Should -Be 2
            $ws.Policies.Count | Should -Be 3
            $ws.Lifecycle | Should -Not -BeNullOrEmpty
            $ws.Approvals | Should -Not -BeNullOrEmpty
            $ws.Notifications | Should -Not -BeNullOrEmpty
            $ws.Lock | Should -Not -BeNullOrEmpty
        }

        It 'warns about managers outside the workspace' {
            @($ws.Diagnostics | Where-Object Field -EQ 'spec.hr.manager').Count | Should -Be 3
        }
    }

    Context 'schema errors' {
        It 'reports a misspelled field with its path' {
            $w = Copy-TestWorkspace
            Edit-TestFile $w 'people/E-004611.yaml' 'workerType: Employee' 'wokerType: Employee'
            # hr allows extra HR attributes, so use a closed object instead.
            Edit-TestFile $w 'lifecycle.yaml' 'preProvisionDays: 3' 'preProvisionDay: 3'
            $e = Get-Error (Import-IamWorkspace -Path $w)
            $e | Where-Object { $_.File -eq 'lifecycle.yaml' -and $_.Field -eq 'spec.preProvisionDay' -and $_.Message -like 'Unknown field*' } | Should -Not -BeNullOrEmpty
        }

        It 'reports a missing required field' {
            $w = Copy-TestWorkspace
            Edit-TestFile $w 'people/E-004611.yaml' '    startDate: 2026-11-02' ''
            $e = Get-Error (Import-IamWorkspace -Path $w)
            $e | Where-Object { $_.File -eq 'people/E-004611.yaml' -and $_.Message -like '*startDate*' } | Should -Not -BeNullOrEmpty
        }

        It 'requires an expiry on exceptions' {
            $w = Copy-TestWorkspace
            Edit-TestFile $w 'people/E-004127.yaml' '      expires: 2026-12-31' ''
            $e = Get-Error (Import-IamWorkspace -Path $w)
            $e | Where-Object { $_.Field -eq 'spec.exceptions[0]' -and $_.Message -like '*expires*' } | Should -Not -BeNullOrEmpty
        }

        It 'rejects an unknown kind' {
            $w = Copy-TestWorkspace
            Edit-TestFile $w 'policies/everyone.yaml' 'kind: Policy' 'kind: Polcy'
            $e = Get-Error (Import-IamWorkspace -Path $w)
            $e | Where-Object { $_.File -eq 'policies/everyone.yaml' -and $_.Field -eq 'kind' } | Should -Not -BeNullOrEmpty
        }

        It 'rejects the wrong kind for a folder' {
            $w = Copy-TestWorkspace
            Copy-Item (Join-Path $w 'policies' 'everyone.yaml') (Join-Path $w 'people' 'E-000001.yaml')
            $e = Get-Error (Import-IamWorkspace -Path $w)
            $e | Where-Object { $_.File -eq 'people/E-000001.yaml' -and $_.Message -like '*must be kind Person*' } | Should -Not -BeNullOrEmpty
        }

        It 'reports YAML that does not parse' {
            $w = Copy-TestWorkspace
            Add-Content -Path (Join-Path $w 'approvals.yaml') -Value "  bad: [unclosed"
            $e = Get-Error (Import-IamWorkspace -Path $w)
            $e | Where-Object { $_.File -eq 'approvals.yaml' -and $_.Message -like 'Not valid YAML*' } | Should -Not -BeNullOrEmpty
        }

        It 'requires iamasc.yaml' {
            $w = Copy-TestWorkspace
            Remove-Item (Join-Path $w 'iamasc.yaml')
            $e = Get-Error (Import-IamWorkspace -Path $w)
            $e | Where-Object File -EQ 'iamasc.yaml' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'secrets' {
        It 'rejects a plaintext secret' {
            $w = Copy-TestWorkspace
            Edit-TestFile $w 'iamasc.yaml' 'credential: { secret: sf-iamasc }' 'password: Hunter2-not-real'
            $e = Get-Error (Import-IamWorkspace -Path $w)
            $e | Where-Object { $_.Field -eq 'spec.providers.salesforce.password' -and $_.Message -like '*plain text*' } | Should -Not -BeNullOrEmpty
        }

        It 'accepts the { secret: name } reference form' {
            $ws = Import-IamWorkspace -Path $example
            $ws.Diagnostics | Where-Object Message -Like '*plain text*' | Should -BeNullOrEmpty
        }
    }

    Context 'cross-file checks' {
        It 'flags a provider missing from requiredProviders' {
            $w = Copy-TestWorkspace
            Edit-TestFile $w 'modules/hris-admin/module.yaml' '    workday:' '    workdayy:'
            $e = Get-Error (Import-IamWorkspace -Path $w)
            $e | Where-Object { $_.File -eq 'modules/hris-admin/module.yaml' -and $_.Field -eq 'spec.grants.workdayy' } | Should -Not -BeNullOrEmpty
        }

        It 'flags a person file whose name does not match' {
            $w = Copy-TestWorkspace
            Move-Item (Join-Path $w 'people' 'E-004611.yaml') (Join-Path $w 'people' 'E-999999.yaml')
            $e = Get-Error (Import-IamWorkspace -Path $w)
            $e | Where-Object { $_.File -eq 'people/E-999999.yaml' -and $_.Message -like 'File name must match*' } | Should -Not -BeNullOrEmpty
        }

        It 'flags duplicate policy names' {
            $w = Copy-TestWorkspace
            Copy-Item (Join-Path $w 'policies' 'everyone.yaml') (Join-Path $w 'policies' 'everyone-copy.yaml')
            $e = Get-Error (Import-IamWorkspace -Path $w)
            $e | Where-Object { $_.Message -like "Another policy already uses the name 'everyone'*" } | Should -Not -BeNullOrEmpty
        }

        It 'flags a module version that does not satisfy the constraint' {
            $w = Copy-TestWorkspace
            Edit-TestFile $w 'policies/finance.yaml' 'version: "1.2.0"' 'version: "~> 2.0"'
            $e = Get-Error (Import-IamWorkspace -Path $w)
            $e | Where-Object { $_.Field -eq 'spec.use[0].version' } | Should -Not -BeNullOrEmpty
        }

        It 'warns about a module that is not local' {
            $w = Copy-TestWorkspace
            Edit-TestFile $w 'policies/finance.yaml' 'module: corp/finance-analyst' 'module: corp/finance-lead'
            $ws = Import-IamWorkspace -Path $w
            $ws.Diagnostics | Where-Object { $_.Severity -eq 'Warning' -and $_.Field -eq 'spec.use[0].module' } | Should -Not -BeNullOrEmpty
            Get-Error $ws | Should -BeNullOrEmpty
        }

        It 'flags an approval rule with an unknown chain' {
            $w = Copy-TestWorkspace
            Edit-TestFile $w 'approvals.yaml' 'chain: privileged' 'chain: priviledged'
            $e = Get-Error (Import-IamWorkspace -Path $w)
            $e | Where-Object { $_.File -eq 'approvals.yaml' -and $_.Field -eq 'spec.rules[0].chain' } | Should -Not -BeNullOrEmpty
        }

        It 'flags a notification route with an unknown channel' {
            $w = Copy-TestWorkspace
            Edit-TestFile $w 'notifications.yaml' 'via: [email, teams-direct]' 'via: [email, teams]'
            $e = Get-Error (Import-IamWorkspace -Path $w)
            $e | Where-Object { $_.File -eq 'notifications.yaml' -and $_.Message -like "*'teams'*" } | Should -Not -BeNullOrEmpty
        }

        It 'warns about an expired exception' {
            $w = Copy-TestWorkspace
            Edit-TestFile $w 'people/E-004127.yaml' 'expires: 2026-12-31' 'expires: 2020-01-31'
            $ws = Import-IamWorkspace -Path $w
            $ws.Diagnostics | Where-Object { $_.Severity -eq 'Warning' -and $_.Field -eq 'spec.exceptions[0].expires' } | Should -Not -BeNullOrEmpty
        }

        It 'warns when a required provider is not in the lock file' {
            $w = Copy-TestWorkspace
            Edit-TestFile $w '.iamasc.lock.yaml' '  iamasc/workday:' '  iamasc/workday-old:'
            $ws = Import-IamWorkspace -Path $w
            $ws.Diagnostics | Where-Object { $_.Severity -eq 'Warning' -and $_.Field -eq 'providers.iamasc/workday' } | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Import-IamServerSetting' {
    It 'accepts the example' {
        $s = Import-IamServerSetting -Path (Join-Path $repo 'examples' 'server' 'iamasc-server.yaml')
        $s.Diagnostics | Should -BeNullOrEmpty
        $s.Kind | Should -Be 'Server'
    }

    It 'flags duplicate workspace names' {
        $file = Join-Path $TestDrive 'server.yaml'
        $text = Get-Content (Join-Path $repo 'examples' 'server' 'iamasc-server.yaml') -Raw
        Set-Content -Path $file -Value $text.Replace('name: corp-warehouse', 'name: corp-chicago')
        $s = Import-IamServerSetting -Path $file
        $s.Diagnostics | Where-Object Message -Like "*'corp-chicago' is listed twice*" | Should -Not -BeNullOrEmpty
    }

    It 'requires either repo or path for each workspace' {
        $file = Join-Path $TestDrive 'server2.yaml'
        $text = Get-Content (Join-Path $repo 'examples' 'server' 'iamasc-server.yaml') -Raw
        Set-Content -Path $file -Value $text.Replace('      repo: https://github.com/corp/iam-chicago.git', '')
        $s = Import-IamServerSetting -Path $file
        $s.Diagnostics | Where-Object Field -Like 'spec.workspaces*' | Should -Not -BeNullOrEmpty
    }
}
