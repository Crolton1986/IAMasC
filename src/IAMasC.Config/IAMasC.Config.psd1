@{
    RootModule           = 'IAMasC.Config.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '6b1d2f0e-3c4a-4e5b-9a71-2d8f0c6e4b13'
    Author               = 'IAMasC contributors'
    Description          = 'Loads and validates IAMasC workspace configuration.'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')
    RequiredModules      = @(@{ ModuleName = 'powershell-yaml'; RequiredVersion = '0.4.12' })
    FunctionsToExport    = @('Import-IamDocument', 'Test-IamDocument', 'Import-IamWorkspace', 'Import-IamServerSetting')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{ PSData = @{ LicenseUri = 'https://github.com/Crolton1986/IAMasC/blob/main/LICENSE' } }
}
