#Requires -Version 7.4

BeforeAll {
    $script:repo = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
    Import-Module (Join-Path $repo 'src' 'IAMasC.Store' 'IAMasC.Store.psd1') -Force

    function Open-TestStore {
        Open-IamStore -Path (Join-Path $TestDrive "$([guid]::NewGuid()).db")
    }
}

Describe 'Open-IamStore' {
    It 'creates the database and applies migrations once' {
        $path = Join-Path $TestDrive 'first.db'
        $s = Open-IamStore -Path $path
        $s.MigrationsApplied | Should -Be 1
        Close-IamStore $s
        Test-Path $path | Should -BeTrue

        $again = Open-IamStore -Path $path
        $again.MigrationsApplied | Should -Be 0
        @(Invoke-IamQuery -Store $again -Sql 'SELECT id, name FROM schema_migrations').name | Should -Be @('init')
        Close-IamStore $again
    }

    It 'turns on WAL and foreign keys' {
        $s = Open-TestStore
        (Invoke-IamQuery -Store $s -Sql 'PRAGMA journal_mode').journal_mode | Should -Be 'wal'
        (Invoke-IamQuery -Store $s -Sql 'PRAGMA foreign_keys').foreign_keys | Should -Be 1
        Close-IamStore $s
    }

    It 'creates the slice 1 tables' {
        $s = Open-TestStore
        $tables = @(Invoke-IamQuery -Store $s -Sql "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name").name
        $tables | Should -Be @('audit', 'hr_cache', 'schema_migrations', 'sessions')
        Close-IamStore $s
    }

    It 'opens an in-memory database' {
        $s = Open-IamStore -Path ':memory:'
        $s.MigrationsApplied | Should -Be 1
        Close-IamStore $s
    }
}

Describe 'Queries' {
    BeforeAll { $script:s = Open-TestStore }
    AfterAll { Close-IamStore $s }

    It 'binds parameters with or without @, including null, bool, and datetime' {
        $when = [datetime]::new(2026, 10, 21, 9, 0, 0, [DateTimeKind]::Utc)
        $n = Invoke-IamNonQuery -Store $s -Sql 'INSERT INTO hr_cache VALUES (@workspace, @id, @source, @data, @synced)' -Parameters @{
            '@workspace' = 'corp-chicago'; id = 'E-1'; source = 'adp'; data = '{}'; synced = $when
        }
        $n | Should -Be 1
        $row = Invoke-IamQuery -Store $s -Sql 'SELECT * FROM hr_cache WHERE employee_id = @id' -Parameters @{ id = 'E-1' }
        $row.workspace | Should -Be 'corp-chicago'
        $row.synced_at | Should -Be '2026-10-21T09:00:00.0000000Z'

        $r = Invoke-IamQuery -Store $s -Sql 'SELECT @a AS a, @b AS b' -Parameters @{ a = $null; b = $true }
        $r.a | Should -BeNullOrEmpty
        $r.b | Should -Be 1
    }

    It 'stores injection attempts as plain text' {
        $evil = "x'); DROP TABLE hr_cache; --"
        $null = Invoke-IamNonQuery -Store $s -Sql 'INSERT INTO hr_cache VALUES (@w, @e, @s, @d, @t)' -Parameters @{ w = 'w'; e = $evil; s = 'csv'; d = '{}'; t = [datetime]::UtcNow }
        (Invoke-IamQuery -Store $s -Sql 'SELECT employee_id FROM hr_cache WHERE employee_id = @e' -Parameters @{ e = $evil }).employee_id | Should -Be $evil
        (Invoke-IamQuery -Store $s -Sql "SELECT count(*) AS n FROM sqlite_master WHERE name = 'hr_cache'").n | Should -Be 1
    }

    It 'returns nothing for no rows' {
        @(Invoke-IamQuery -Store $s -Sql 'SELECT * FROM hr_cache WHERE employee_id = @e' -Parameters @{ e = 'nobody' }).Count | Should -Be 0
    }
}

Describe 'Invoke-IamTransaction' {
    BeforeAll {
        $script:s = Open-TestStore
        $script:insert = {
            param($id)
            $null = Invoke-IamNonQuery -Store $s -Sql 'INSERT INTO hr_cache VALUES (@w, @e, @s, @d, @t)' -Parameters @{ w = 'tx'; e = $id; s = 'csv'; d = '{}'; t = [datetime]::UtcNow }
        }
        $script:count = { (Invoke-IamQuery -Store $s -Sql "SELECT count(*) AS n FROM hr_cache WHERE workspace = 'tx'").n }
    }
    AfterAll { Close-IamStore $s }

    It 'commits when the block finishes' {
        Invoke-IamTransaction -Store $s { & $insert 'T1'; & $insert 'T2' }
        & $count | Should -Be 2
    }

    It 'rolls back everything when the block throws' {
        { Invoke-IamTransaction -Store $s { & $insert 'T3'; throw 'stop' } } | Should -Throw 'stop'
        & $count | Should -Be 2
    }

    It 'joins an outer transaction instead of nesting' {
        { Invoke-IamTransaction -Store $s { & $insert 'T4'; Invoke-IamTransaction -Store $s { & $insert 'T5' }; throw 'outer fails' } } | Should -Throw
        & $count | Should -Be 2
    }

    It 'leaves the connection usable after a rollback' {
        & $insert 'T6'
        & $count | Should -Be 3
    }
}

Describe 'Audit log' {
    BeforeAll { $script:s = Open-TestStore }
    AfterAll { Close-IamStore $s }

    It 'round-trips an entry with before and after values' {
        $id = Write-IamAudit -Store $s -Actor 'jlee' -Action 'person.updated' -Workspace 'corp-chicago' -Target 'person/E-004127' `
            -Before @{ department = 'Finance' } -After @{ department = 'Treasury' } -CorrelationId 'req-1'
        $id | Should -BeGreaterThan 0
        $e = Get-IamAudit -Store $s -Target 'person/E-004127'
        $e.Actor | Should -Be 'jlee'
        $e.Action | Should -Be 'person.updated'
        $e.Before.department | Should -Be 'Finance'
        $e.After.department | Should -Be 'Treasury'
        $e.CorrelationId | Should -Be 'req-1'
        $e.At.Kind | Should -Be 'Utc'
    }

    It 'returns newest first and honors filters and limits' {
        foreach ($i in 1..3) { $null = Write-IamAudit -Store $s -Actor 'scheduler' -Action 'plan.created' -Workspace 'corp-warehouse' -Target "run/$i" }
        $rows = @(Get-IamAudit -Store $s -Workspace 'corp-warehouse')
        $rows.Target | Should -Be @('run/3', 'run/2', 'run/1')
        @(Get-IamAudit -Store $s -Actor 'scheduler' -Limit 2).Count | Should -Be 2
        @(Get-IamAudit -Store $s -Since ([datetime]::UtcNow.AddMinutes(1))).Count | Should -Be 0
    }

    It 'refuses to change or delete entries' {
        { Invoke-IamNonQuery -Store $s -Sql "UPDATE audit SET actor = 'someone-else'" } | Should -Throw '*append-only*'
        { Invoke-IamNonQuery -Store $s -Sql 'DELETE FROM audit' } | Should -Throw '*append-only*'
    }

    It 'rejects malformed action names' {
        { Write-IamAudit -Store $s -Actor 'x' -Action 'Person Created' } | Should -Throw
    }
}

Describe 'Migrations' {
    It 'refuses an applied migration that was edited' {
        InModuleScope IAMasC.Store -Parameters @{ Folder = (Join-Path $TestDrive 'mig-edit'); Db = (Join-Path $TestDrive 'edit.db') } {
            $null = New-Item -ItemType Directory -Path $Folder
            Set-Content -Path (Join-Path $Folder '0001_first.sql') -Value 'CREATE TABLE t (a TEXT);'
            Initialize-IamSqlite
            $c = [Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$Db"); $c.Open()
            Invoke-IamMigration -Connection $c -Folder $Folder | Should -Be 1
            Set-Content -Path (Join-Path $Folder '0001_first.sql') -Value 'CREATE TABLE t (a TEXT, b TEXT);'
            { Invoke-IamMigration -Connection $c -Folder $Folder } | Should -Throw '*has changed since it was applied*'
            $c.Dispose()
        }
    }

    It 'ignores line-ending differences' {
        InModuleScope IAMasC.Store -Parameters @{ Folder = (Join-Path $TestDrive 'mig-crlf'); Db = (Join-Path $TestDrive 'crlf.db') } {
            $null = New-Item -ItemType Directory -Path $Folder
            [IO.File]::WriteAllText((Join-Path $Folder '0001_first.sql'), "CREATE TABLE t (a TEXT);`nCREATE TABLE u (b TEXT);`n")
            Initialize-IamSqlite
            $c = [Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$Db"); $c.Open()
            Invoke-IamMigration -Connection $c -Folder $Folder | Should -Be 1
            [IO.File]::WriteAllText((Join-Path $Folder '0001_first.sql'), "CREATE TABLE t (a TEXT);`r`nCREATE TABLE u (b TEXT);`r`n")
            Invoke-IamMigration -Connection $c -Folder $Folder | Should -Be 0
            $c.Dispose()
        }
    }

    It 'refuses a database from a newer release' {
        $path = Join-Path $TestDrive 'newer.db'
        $s = Open-IamStore -Path $path
        $null = Invoke-IamNonQuery -Store $s -Sql "INSERT INTO schema_migrations VALUES (9999, 'future', 'x', '2030-01-01')"
        Close-IamStore $s
        { Open-IamStore -Path $path } | Should -Throw '*newer IAMasC*'
    }

    It 'rolls back a failing migration and names it' {
        InModuleScope IAMasC.Store -Parameters @{ Folder = (Join-Path $TestDrive 'mig-bad'); Db = (Join-Path $TestDrive 'bad.db') } {
            $null = New-Item -ItemType Directory -Path $Folder
            Set-Content -Path (Join-Path $Folder '0001_good.sql') -Value 'CREATE TABLE ok (a TEXT);'
            Set-Content -Path (Join-Path $Folder '0002_bad.sql') -Value 'CREATE TABLE half (a TEXT); THIS IS NOT SQL;'
            Initialize-IamSqlite
            $c = [Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$Db"); $c.Open()
            { Invoke-IamMigration -Connection $c -Folder $Folder } | Should -Throw '*Migration 2 (bad) failed*'
            $cmd = $c.CreateCommand()
            $cmd.CommandText = "SELECT count(*) FROM sqlite_master WHERE name = 'half'"
            $cmd.ExecuteScalar() | Should -Be 0
            $cmd.CommandText = 'SELECT count(*) FROM schema_migrations'
            $cmd.ExecuteScalar() | Should -Be 1
            $c.Dispose()
        }
    }

    It 'rejects a badly named migration file' {
        InModuleScope IAMasC.Store -Parameters @{ Folder = (Join-Path $TestDrive 'mig-name') } {
            $null = New-Item -ItemType Directory -Path $Folder
            Set-Content -Path (Join-Path $Folder 'add-table.sql') -Value 'SELECT 1;'
            { @(Get-IamMigration -Folder $Folder) } | Should -Throw '*must be named NNNN_name.sql*'
        }
    }
}

Describe 'Native library loading' {
    It 'picks a runtime identifier for this machine' {
        InModuleScope IAMasC.Store {
            Get-IamRuntimeIdentifier | Should -Match '^(win|osx|linux|linux-musl)-(x64|arm64|x86|arm)$'
        }
    }

    It 'explains how to fix missing libraries' {
        InModuleScope IAMasC.Store -Parameters @{ Empty = (Join-Path $TestDrive 'nolib') } {
            $null = New-Item -ItemType Directory -Path $Empty -Force
            $saved = $env:IAMASC_LIB
            $script:SqliteReady = $false
            try {
                $env:IAMASC_LIB = $Empty
                { Initialize-IamSqlite } | Should -Throw '*Run ./build.ps1 -Task Bootstrap*'
            } finally {
                $env:IAMASC_LIB = $saved
                Initialize-IamSqlite
            }
        }
    }
}
