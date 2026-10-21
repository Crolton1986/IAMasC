@{
    RootModule           = 'IAMasC.Store.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '0f4c9a52-7e1b-4d63-8a2e-5b9d1c3e7f40'
    Author               = 'IAMasC contributors'
    Description          = 'SQLite store for IAMasC: migrations, parameterized queries, transactions, and the audit log.'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @(
        'Open-IamStore', 'Close-IamStore', 'Invoke-IamQuery', 'Invoke-IamNonQuery', 'Invoke-IamTransaction',
        'Write-IamAudit', 'Get-IamAudit'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{ PSData = @{ LicenseUri = 'https://github.com/Crolton1986/IAMasC/blob/main/LICENSE' } }
}
