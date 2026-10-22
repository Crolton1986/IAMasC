@{
    RootModule           = 'IAMasC.Web.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '3d8e5b71-2c4f-4a96-b0d7-9e1f6a2c8b54'
    Author               = 'IAMasC contributors'
    Description          = 'Server-rendered pages for the IAMasC web UI.'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @('Get-IamDashboardPage', 'Get-IamPeoplePage', 'Get-IamPersonPage', 'Get-IamNotFoundPage', 'Get-IamPersonRow', 'ConvertTo-IamHtml')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{ PSData = @{ LicenseUri = 'https://github.com/Crolton1986/IAMasC/blob/main/LICENSE' } }
}
