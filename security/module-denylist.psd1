# PowerShell modules (or specific versions) that must never be used.
# Add an entry when an advisory, typosquat, or compromised release is reported.
# Omit Version to block every version of a module.
@{
    Entries = @(
        # @{ Name = 'Example.Module'; Version = '1.2.3'; Reason = 'CVE-XXXX-YYYY'; Reference = 'https://...' }
    )
}
