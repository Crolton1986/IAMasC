#Requires -Version 7.4

BeforeAll {
    $script:repo = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
    $script:server = Join-Path $repo 'server.ps1'
    $script:pwsh = (Get-Process -Id $PID).Path

    function Get-FreePort {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $listener.Start()
        try { $listener.LocalEndpoint.Port } finally { $listener.Stop() }
    }

    # Copies the example workspace and writes dev settings pointing at it.
    function Initialize-TestServer([string] $Folder, [string] $Address = '127.0.0.1') {
        $ws = Join-Path $Folder 'ws'
        Copy-Item (Join-Path $repo 'examples' 'corp-chicago') $ws -Recurse
        $settings = Join-Path $Folder 'settings.yaml'
        @"
apiVersion: iamasc.dev/v1
kind: Server
metadata:
  name: test
spec:
  listen: { address: "$Address", port: 8080 }
  dataPath: data
  auth: { mode: dev }
  workspaces:
    - name: corp-chicago
      path: ws
      match: { companyCode: "100" }
"@ | Set-Content -LiteralPath $settings
        $settings
    }

    # Runs server.ps1 to completion. Only for settings it should refuse.
    function Invoke-Server([string] $Settings) {
        $output = & $pwsh -NoLogo -NoProfile -File $server -Settings $Settings -Port (Get-FreePort) 2>&1
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
    }
}

Describe 'server.ps1 refuses bad configuration' {
    It 'refuses a non-loopback address in dev mode' {
        $settings = Initialize-TestServer -Folder (Join-Path $TestDrive 'any') -Address '0.0.0.0'
        $r = Invoke-Server $settings
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match "dev mode only listens on 127\.0\.0\.1, ::1, or localhost, not '0\.0\.0\.0'"
    }

    It 'refuses invalid settings and names the field' {
        $settings = Initialize-TestServer -Folder (Join-Path $TestDrive 'bad-settings')
        (Get-Content $settings -Raw).Replace('mode: dev', 'mode: kerberos') | Set-Content $settings -NoNewline
        $r = Invoke-Server $settings
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match 'the settings file has errors'
        $r.Output | Should -Match 'spec\.auth\.mode'
    }

    It 'refuses a workspace with errors' {
        $folder = Join-Path $TestDrive 'bad-ws'
        $settings = Initialize-TestServer -Folder $folder
        $file = Join-Path $folder 'ws' 'approvals.yaml'
        (Get-Content $file -Raw).Replace('chain: privileged', 'chain: missing') | Set-Content $file -NoNewline
        $r = Invoke-Server $settings
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match "workspace 'corp-chicago' has errors"
        $r.Output | Should -Match 'missing'
    }

    It 'refuses a settings file that does not exist' {
        $r = Invoke-Server (Join-Path $TestDrive 'nope.yaml')
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match 'not found'
    }
}

Describe 'Running server' {
    BeforeAll {
        $folder = Join-Path $TestDrive 'running'
        $settings = Initialize-TestServer -Folder $folder
        $script:dataPath = Join-Path $folder 'data'

        # A person whose HR data tries to inject markup.
        $people = Join-Path $folder 'ws' 'people'
        $evil = (Get-Content (Join-Path $people 'E-004611.yaml') -Raw).Replace('E-004611', 'E-999999')
        $evil = $evil.Replace('firstName: Grace', "firstName: '<script>alert(1)</script>'")
        $evil = $evil.Replace('title: HR Generalist', 'title: "\"><img src=x onerror=alert(2)>"')
        Set-Content -LiteralPath (Join-Path $people 'E-999999.yaml') -Value $evil -NoNewline

        $port = Get-FreePort
        $script:base = "http://127.0.0.1:$port"
        $script:stdout = Join-Path $folder 'stdout.txt'
        $script:stderr = Join-Path $folder 'stderr.txt'
        $script:proc = Start-Process -FilePath $pwsh -PassThru -NoNewWindow `
            -ArgumentList @('-NoLogo', '-NoProfile', '-File', $server, '-Settings', $settings, '-Port', $port) `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr

        $deadline = [datetime]::UtcNow.AddSeconds(90)
        $up = $false
        while (-not $up -and [datetime]::UtcNow -lt $deadline -and -not $proc.HasExited) {
            try {
                $null = Invoke-WebRequest "$base/health" -TimeoutSec 2
                $up = $true
            } catch {
                Start-Sleep -Milliseconds 250
            }
        }
        if (-not $up) {
            $log = (Get-Content $stdout, $stderr -Raw -ErrorAction SilentlyContinue) -join "`n"
            throw "server did not start:`n$log"
        }

        function Get-Page([string] $Path) {
            Invoke-WebRequest "$base$Path" -SkipHttpErrorCheck -TimeoutSec 10
        }
    }

    AfterAll {
        if ($proc -and -not $proc.HasExited) {
            $proc.Kill($true)
            $proc.WaitForExit(10000)
        }
    }

    It '/health reports ok and lists the workspace' {
        $r = Get-Page '/health'
        $r.StatusCode | Should -Be 200
        $json = $r.Content | ConvertFrom-Json
        $json.status | Should -Be 'ok'
        $json.database | Should -Be 'ok'
        $json.workspaces[0].name | Should -Be 'corp-chicago'
        $json.workspaces[0].people | Should -Be 4
    }

    It 'renders the dashboard' {
        $r = Get-Page '/'
        $r.StatusCode | Should -Be 200
        $r.Content | Should -Match 'Dev mode'
        $r.Content | Should -Match 'Dan Whitfield'
    }

    It 'lists people' {
        $r = Get-Page '/people'
        $r.StatusCode | Should -Be 200
        foreach ($name in 'Grace Lindqvist', 'Dan Whitfield', 'E-003318') { $r.Content | Should -Match $name }
    }

    It 'searches people' {
        $r = Get-Page '/people?q=whitfield'
        $r.StatusCode | Should -Be 200
        $r.Content | Should -Match 'Dan Whitfield'
        $r.Content | Should -Not -Match 'Grace Lindqvist'
    }

    It 'filters people by status' {
        $r = Get-Page '/people?status=Offboarding'
        $r.StatusCode | Should -Be 200
        $r.Content | Should -Match 'Dan Whitfield'
        $r.Content | Should -Not -Match 'Grace Lindqvist'
    }

    It 'shows a person' {
        $r = Get-Page '/people/corp-chicago/E-004611'
        $r.StatusCode | Should -Be 200
        $r.Content | Should -Match 'Grace Lindqvist'
        $r.Content | Should -Match 'corp/hris-admin'
        $r.Content | Should -Match 'No providers are configured yet'
    }

    It 'escapes markup from person files' -ForEach @(
        @{ Path = '/people' }
        @{ Path = '/people/corp-chicago/E-999999' }
        @{ Path = '/people?q=%3Cscript%3E' }
    ) {
        $r = Get-Page $Path
        $r.StatusCode | Should -Be 200
        $r.Content | Should -Not -Match '<script'
        $r.Content | Should -Not -Match '<img'
    }

    It 'shows the escaped values as text' {
        $r = Get-Page '/people/corp-chicago/E-999999'
        $r.Content | Should -Match ([regex]::Escape('&lt;script&gt;alert(1)&lt;/script&gt;'))
    }

    It 'escapes the search box value' {
        $r = Get-Page '/people?q=%22%3E%3Cb%3Ex'
        $r.Content | Should -Not -Match '"><b>x'
        $r.Content | Should -Match ([regex]::Escape('&quot;&gt;&lt;b&gt;x'))
    }

    It 'returns 404 for an unknown person without internals' {
        $r = Get-Page '/people/corp-chicago/NOPE'
        $r.StatusCode | Should -Be 404
        $r.Content | Should -Match 'not found'
        $r.Content | Should -Not -Match 'at line|\.ps1|Exception'
    }

    It 'returns 404 for an unknown route' {
        (Get-Page '/no/such/page').StatusCode | Should -Be 404
    }

    It 'serves the stylesheet' {
        $r = Get-Page '/static/iamasc.css'
        $r.StatusCode | Should -Be 200
        $r.Content | Should -Match '\.devbanner'
    }

    It 'sends security headers on <Path>' -ForEach @(
        @{ Path = '/' }
        @{ Path = '/people/corp-chicago/NOPE' }
        @{ Path = '/no/such/page' }
        @{ Path = '/health' }
    ) {
        $r = Get-Page $Path
        $csp = "$($r.Headers['Content-Security-Policy'])"
        $csp | Should -Match "default-src 'self'"
        $csp | Should -Match "frame-ancestors 'none'"
        $csp | Should -Not -Match 'unsafe-inline'
        "$($r.Headers['X-Content-Type-Options'])" | Should -Be 'nosniff'
        "$($r.Headers['Referrer-Policy'])" | Should -Be 'no-referrer'
        "$($r.Headers['X-Frame-Options'])" | Should -Be 'DENY'
        $r.Headers.ContainsKey('Server') | Should -BeFalse
    }

    It 'writes server.started to the audit log' {
        Import-Module (Join-Path $repo 'src' 'IAMasC.Store' 'IAMasC.Store.psd1') -Force
        $s = Open-IamStore -Path (Join-Path $dataPath 'iamasc.db')
        try {
            $entries = @(Get-IamAudit -Store $s -Actor 'system' | Where-Object Action -EQ 'server.started')
        } finally {
            Close-IamStore $s
        }
        $entries.Count | Should -Be 1
        $entries[0].Actor | Should -Be 'system'
    }
}
