function Get-IamMigration {
    <# Lists migration files in order with their number and a checksum of their contents. #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string] $Folder)

    foreach ($file in Get-ChildItem -Path $Folder -Filter '*.sql' | Sort-Object Name) {
        if ($file.Name -notmatch '^(?<id>\d{4})_(?<name>[a-z0-9_]+)\.sql$') {
            throw "Migration file '$($file.Name)' must be named NNNN_name.sql."
        }
        # Normalize line endings so a Windows checkout doesn't look like a changed migration.
        $sql = (Get-Content -Path $file.FullName -Raw).Replace("`r`n", "`n")
        $bytes = [Text.Encoding]::UTF8.GetBytes($sql)
        [pscustomobject]@{
            Id       = [int]$Matches.id
            Name     = $Matches.name
            Sql      = $sql
            Checksum = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        }
    }
}

function Invoke-IamMigration {
    <#
    .SYNOPSIS
        Brings the database schema up to date, one transaction per migration.
    .DESCRIPTION
        Refuses to run when an applied migration's file has changed, or when the database has
        migrations this release doesn't know (it was opened by a newer IAMasC).
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string] $Folder
    )

    $null = Invoke-IamSqlCommand -Connection $Connection -Sql 'CREATE TABLE IF NOT EXISTS schema_migrations (id INTEGER PRIMARY KEY, name TEXT NOT NULL, checksum TEXT NOT NULL, applied_at TEXT NOT NULL)'

    $applied = @{}
    $read = $Connection.CreateCommand()
    try {
        $read.CommandText = 'SELECT id, name, checksum FROM schema_migrations'
        $reader = $read.ExecuteReader()
        try {
            while ($reader.Read()) { $applied[[int]$reader.GetInt64(0)] = @{ Name = $reader.GetString(1); Checksum = $reader.GetString(2) } }
        } finally {
            $reader.Dispose()
        }
    } finally {
        $read.Dispose()
    }

    $migrations = @(Get-IamMigration -Folder $Folder)
    $known = @($migrations.Id)
    $unknown = @($applied.Keys | Where-Object { $_ -notin $known })
    if ($unknown) {
        throw "The database has migration(s) $($unknown -join ', ') that this release doesn't know. It was opened by a newer IAMasC; upgrade instead of downgrading."
    }

    $count = 0
    foreach ($m in $migrations) {
        if ($applied.ContainsKey($m.Id)) {
            if ($applied[$m.Id].Checksum -ne $m.Checksum) {
                throw "Migration $($m.Id) ($($m.Name)) has changed since it was applied. Applied migrations must never be edited; add a new one."
            }
            continue
        }

        $tx = $Connection.BeginTransaction()
        try {
            $null = Invoke-IamSqlCommand -Connection $Connection -Transaction $tx -Sql $m.Sql
            $null = Invoke-IamSqlCommand -Connection $Connection -Transaction $tx `
                -Sql 'INSERT INTO schema_migrations (id, name, checksum, applied_at) VALUES (@id, @name, @checksum, @at)' `
                -Parameters @{ id = $m.Id; name = $m.Name; checksum = $m.Checksum; at = [datetime]::UtcNow }
            $tx.Commit()
            $count++
        } catch {
            $tx.Rollback()
            throw "Migration $($m.Id) ($($m.Name)) failed and was rolled back: $($_.Exception.Message)"
        } finally {
            $tx.Dispose()
        }
    }
    $count
}
