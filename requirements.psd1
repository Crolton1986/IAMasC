# Pinned PowerShell module dependencies. Exact versions only.
# build.ps1 -Task Bootstrap installs these; tools/Test-ModuleRequirements.ps1 audits them in CI.
@{
    Modules = @(
        @{ Name = 'Pester';           Version = '5.6.1';  Purpose = 'Tests' }
        @{ Name = 'PSScriptAnalyzer'; Version = '1.25.0'; Purpose = 'Lint' }
        @{ Name = 'InjectionHunter';  Version = '1.0.0';  Purpose = 'Lint (code injection rules)' }
    )
}
