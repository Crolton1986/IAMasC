#Requires -Version 7.4
# Guards for the repository itself: layout, config files, and CI supply-chain rules.

BeforeDiscovery {
    $root = Split-Path $PSScriptRoot -Parent
    $script:dataFiles = Get-ChildItem -Path $root -Recurse -File -Filter '*.psd1' |
        Where-Object { $_.FullName -notmatch '[\\/](out|dist|\.git)[\\/]' } |
        ForEach-Object { @{ Path = $_.FullName; Name = [IO.Path]::GetRelativePath($root, $_.FullName) } }
    $script:workflows = Get-ChildItem -Path (Join-Path $root '.github' 'workflows' '*') -File -Include '*.yml', '*.yaml' |
        ForEach-Object { @{ Path = $_.FullName; Name = $_.Name } }
}

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
}

Describe 'Repository layout' {
    It '<_> exists' -ForEach @(
        'README.md', 'LICENSE', 'CONTRIBUTING.md', 'SECURITY.md', 'CHANGELOG.md', 'build.ps1', 'iamasc.ps1', 'server.ps1',
        'requirements.psd1', 'PSScriptAnalyzerSettings.psd1',
        '.github/CODEOWNERS', '.github/pull_request_template.md',
        '.github/workflows/ci.yml', '.github/workflows/security.yml',
        '.github/workflows/release.yml', '.github/workflows/deploy.yml',
        '.github/rulesets/main.json'
    ) {
        Join-Path $root $_ | Should -Exist
    }
}

Describe 'PowerShell data files' {
    It '<Name> parses' -ForEach $dataFiles {
        { Import-PowerShellDataFile -Path $Path } | Should -Not -Throw
    }
}

Describe 'requirements.psd1' {
    It 'pins every module to an exact version' {
        $modules = (Import-PowerShellDataFile (Join-Path $root 'requirements.psd1')).Modules
        $modules | Should -Not -BeNullOrEmpty
        foreach ($m in $modules) {
            $m.Version | Should -Match '^\d+\.\d+\.\d+(\.\d+)?$' -Because "$($m.Name) must be pinned"
        }
    }
}

Describe 'Workflow <Name>' -ForEach $workflows {
    BeforeAll {
        $script:content = Get-Content -Path $Path -Raw
        $script:uses = [regex]::Matches($content, '(?m)^\s*-?\s*uses:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value }
    }

    It 'pins every third-party action to a full commit SHA' {
        foreach ($u in $uses | Where-Object { $_ -notmatch '^(\./|\$/)' }) {
            $u | Should -Match '@[0-9a-f]{40}$' -Because "'$u' must be pinned to a commit, not a tag or branch"
        }
    }

    It 'declares top-level permissions' {
        $content | Should -Match '(?m)^permissions:'
    }

    It 'never uses pull_request_target' {
        $content | Should -Not -Match 'pull_request_target'
    }
}

Describe 'main ruleset' {
    It 'is valid JSON and requires every gate' {
        $ruleset = Get-Content (Join-Path $root '.github' 'rulesets' 'main.json') -Raw | ConvertFrom-Json
        $checks = ($ruleset.rules | Where-Object type -EQ 'required_status_checks').parameters.required_status_checks.context
        foreach ($gate in 'lint', 'test (ubuntu)', 'test (windows)', 'docs', 'secrets-scan', 'vuln-scan', 'sast', 'workflow-audit', 'dependency-review', 'security-review') {
            $checks | Should -Contain $gate
        }
    }
}
