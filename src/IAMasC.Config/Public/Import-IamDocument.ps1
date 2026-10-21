function Import-IamDocument {
    <#
    .SYNOPSIS
        Reads one IAMasC YAML file and checks it against the schema for its kind.
    .OUTPUTS
        An object with Path, ApiVersion, Kind, Name, Data (ordered dictionary), and Diagnostics.
        Data is $null when the file can't be parsed.
    .EXAMPLE
        Import-IamDocument -Path ./people/E-004611.yaml
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string] $Path,

        # Diagnostics show file paths relative to this folder.
        [string] $Root
    )

    process {
        $display = Get-IamRelativePath -Root $Root -Path $Path
        $result = [pscustomobject]@{
            PSTypeName  = 'IAMasC.Document'
            Path        = $Path
            ApiVersion  = $null
            Kind        = $null
            Name        = $null
            Data        = $null
            Diagnostics = [Collections.Generic.List[object]]::new()
        }

        try {
            $documents = @(ConvertFrom-Yaml -Yaml (Get-Content -Path $Path -Raw) -AllDocuments -Ordered)
        } catch {
            $result.Diagnostics.Add((ConvertTo-IamDiagnostic -Severity Error -File $display -Message "Not valid YAML: $($_.Exception.Message)"))
            return $result
        }

        if ($documents.Count -ne 1 -or $documents[0] -isnot [Collections.IDictionary]) {
            $result.Diagnostics.Add((ConvertTo-IamDiagnostic -Severity Error -File $display -Message 'Each file must hold exactly one YAML document with apiVersion and kind.'))
            return $result
        }

        $data = $documents[0]
        $result.Data = $data
        $result.ApiVersion = $data['apiVersion']
        $result.Kind = $data['kind']
        if ($data['metadata'] -is [Collections.IDictionary]) {
            $result.Name = $data['metadata']['name']
        }

        if (-not $script:KnownKinds.Contains([string]$result.Kind)) {
            $known = $script:KnownKinds.Keys -join ', '
            $result.Diagnostics.Add((ConvertTo-IamDiagnostic -Severity Error -File $display -Field 'kind' -Message "Unknown kind '$($result.Kind)'. Expected one of: $known."))
            return $result
        }

        foreach ($d in Test-IamDocument -Document $result -Root $Root) { $result.Diagnostics.Add($d) }
        $result
    }
}
