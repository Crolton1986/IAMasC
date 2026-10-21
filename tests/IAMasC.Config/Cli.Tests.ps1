#Requires -Version 7.4

BeforeAll {
    $script:repo = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
    $script:cli = Join-Path $repo 'iamasc.ps1'
    $script:pwsh = (Get-Process -Id $PID).Path

    function Invoke-Cli([string[]] $Arguments) {
        $output = & $pwsh -NoLogo -NoProfile -File $cli @Arguments 2>&1
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
    }
}

Describe 'iamasc validate' {
    It 'passes the example workspace' {
        $r = Invoke-Cli @('validate', (Join-Path $repo 'examples' 'corp-chicago'))
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match 'OK  workspace corp-chicago: 0 error\(s\), 3 warning\(s\)'
    }

    It 'fails on warnings with -Strict' {
        $r = Invoke-Cli @('validate', (Join-Path $repo 'examples' 'corp-chicago'), '-Strict')
        $r.ExitCode | Should -Be 1
    }

    It 'passes the example server settings as JSON' {
        $r = Invoke-Cli @('validate', (Join-Path $repo 'examples' 'server' 'iamasc-server.yaml'), '-Format', 'json')
        $r.ExitCode | Should -Be 0
        $json = $r.Output | ConvertFrom-Json
        $json.valid | Should -BeTrue
        $json.errors | Should -Be 0
    }

    It 'fails a broken workspace and names the problem' {
        $w = Join-Path $TestDrive 'ws'
        Copy-Item (Join-Path $repo 'examples' 'corp-chicago') $w -Recurse
        $file = Join-Path $w 'approvals.yaml'
        (Get-Content $file -Raw).Replace('chain: privileged', 'chain: missing') | Set-Content $file -NoNewline
        $r = Invoke-Cli @('validate', $w)
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match "No chain named 'missing'"
    }

    It 'returns 2 for a path that does not exist' {
        $r = Invoke-Cli @('validate', (Join-Path $TestDrive 'nope'))
        $r.ExitCode | Should -Be 2
    }
}
