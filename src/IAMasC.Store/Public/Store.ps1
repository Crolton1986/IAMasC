function Open-IamStore {
    <#
    .SYNOPSIS
        Opens (or creates) the IAMasC database and brings its schema up to date.
    .EXAMPLE
        $store = Open-IamStore -Path ./data/iamasc.db
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # Database file. Use ':memory:' for a throwaway in-memory database (tests).
        [Parameter(Mandatory)] [string] $Path
    )

    Initialize-IamSqlite

    if ($Path -ne ':memory:') {
        $Path = [IO.Path]::GetFullPath($Path)
        $null = New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force
    }

    $builder = [Microsoft.Data.Sqlite.SqliteConnectionStringBuilder]::new()
    $builder.DataSource = $Path
    $builder.Mode = [Microsoft.Data.Sqlite.SqliteOpenMode]::ReadWriteCreate
    $builder.Pooling = $false
    $connection = [Microsoft.Data.Sqlite.SqliteConnection]::new($builder.ToString())
    $connection.Open()

    try {
        $pragma = $connection.CreateCommand()
        $pragma.CommandText = 'PRAGMA busy_timeout = 5000; PRAGMA foreign_keys = ON;'
        $null = $pragma.ExecuteNonQuery()
        if ($Path -ne ':memory:') {
            # WAL lets the web pages read while the scheduler writes.
            $pragma.CommandText = 'PRAGMA journal_mode = WAL;'
            $null = $pragma.ExecuteNonQuery()
        }
        $applied = Invoke-IamMigration -Connection $connection -Folder (Join-Path $PSScriptRoot '..' 'migrations')
    } catch {
        $connection.Dispose()
        throw
    }

    [pscustomobject]@{
        PSTypeName        = 'IAMasC.Store'
        Path              = $Path
        Connection        = $connection
        MigrationsApplied = $applied
    }
}

function Close-IamStore {
    <# Closes the database connection. #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)] [pscustomobject] $Store)
    process {
        $Store.Connection.Dispose()
    }
}

function Invoke-IamQuery {
    <#
    .SYNOPSIS
        Runs a SELECT and returns one object per row. Always parameterized.
    .EXAMPLE
        Invoke-IamQuery -Store $store -Sql 'SELECT * FROM audit WHERE target = @t' -Parameters @{ t = 'person/E-004611' }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Store,
        [Parameter(Mandatory)] [string] $Sql,
        [Collections.IDictionary] $Parameters
    )

    $cmd = $Store.Connection.CreateCommand()
    $cmd.Transaction = Get-IamActiveTransaction -Connection $Store.Connection
    $cmd.CommandText = $Sql
    Add-IamSqlParameter -Command $cmd -Parameters $Parameters
    $reader = $cmd.ExecuteReader()
    try {
        while ($reader.Read()) {
            $row = [ordered]@{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $row[$reader.GetName($i)] = if ($reader.IsDBNull($i)) { $null } else { $reader.GetValue($i) }
            }
            [pscustomobject]$row
        }
    } finally {
        $reader.Dispose()
        $cmd.Dispose()
    }
}

function Invoke-IamNonQuery {
    <# Runs INSERT, UPDATE, or DELETE and returns the number of rows changed. Always parameterized. #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Store,
        [Parameter(Mandatory)] [string] $Sql,
        [Collections.IDictionary] $Parameters
    )

    $cmd = $Store.Connection.CreateCommand()
    $cmd.Transaction = Get-IamActiveTransaction -Connection $Store.Connection
    $cmd.CommandText = $Sql
    Add-IamSqlParameter -Command $cmd -Parameters $Parameters
    try {
        $cmd.ExecuteNonQuery()
    } finally {
        $cmd.Dispose()
    }
}

function Invoke-IamTransaction {
    <#
    .SYNOPSIS
        Runs a script block in one transaction: commits if it finishes, rolls back if it throws.
    .EXAMPLE
        Invoke-IamTransaction -Store $store -ScriptBlock {
            Invoke-IamNonQuery -Store $store -Sql '...'
            Write-IamAudit -Store $store -Actor jlee -Action person.created -Target person/E-004611
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Store,
        [Parameter(Mandatory)] [scriptblock] $ScriptBlock
    )

    $existing = $null
    if ($script:ActiveTransaction.TryGetValue($Store.Connection, [ref] $existing)) {
        # Already inside a transaction on this connection: join it.
        return & $ScriptBlock
    }

    $tx = $Store.Connection.BeginTransaction()
    $script:ActiveTransaction.Add($Store.Connection, $tx)
    try {
        & $ScriptBlock
        $tx.Commit()
    } catch {
        $tx.Rollback()
        throw
    } finally {
        $null = $script:ActiveTransaction.Remove($Store.Connection)
        $tx.Dispose()
    }
}
