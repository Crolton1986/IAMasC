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

        $json = $Document.Data | ConvertTo-Json -Depth 64 -Compress
        $errors = $null
        $null = Test-Json -Json $json -Schema (Get-IamSchema -Kind $Document.Kind) -ErrorVariable errors -ErrorAction SilentlyContinue
        foreach ($e in $errors) {
            $parsed = ConvertTo-IamSchemaMessage -Raw $e.Exception.Message
            ConvertTo-IamDiagnostic -Severity Error -File $display -Field $parsed.Field -Message $parsed.Message
        }

        foreach ($field in Find-IamPlaintextSecret -Node $Document.Data) {
            ConvertTo-IamDiagnostic -Severity Error -File $display -Field $field -Message 'Looks like a secret written in plain text. Store it in the vault and reference it as { secret: <name> }.'
        }
    }
}
