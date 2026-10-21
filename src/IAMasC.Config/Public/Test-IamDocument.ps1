function Test-IamDocument {
    <#
    .SYNOPSIS
        Checks a loaded document against the JSON Schema for its kind and for plaintext secrets.
    .OUTPUTS
        Diagnostics. Nothing when the document is valid.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [pscustomobject] $Document,
        [string] $Root
    )

    process {
        $display = Get-IamRelativePath -Root $Root -Path $Document.Path
        if ($null -eq $Document.Data) { return }

        foreach ($problem in Test-IamJsonSchema -Value $Document.Data -Schema (Get-IamSchema -Kind $Document.Kind)) {
            ConvertTo-IamDiagnostic -Severity Error -File $display -Field $problem.Field -Message $problem.Message
        }

        foreach ($field in Find-IamPlaintextSecret -Node $Document.Data) {
            ConvertTo-IamDiagnostic -Severity Error -File $display -Field $field -Message 'Looks like a secret written in plain text. Store it in the vault and reference it as { secret: <name> }.'
        }
    }
}
