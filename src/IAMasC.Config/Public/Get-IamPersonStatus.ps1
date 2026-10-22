function Get-IamPersonStatus {
    <#
    .SYNOPSIS
        Works out a person's lifecycle status from the dates in their HR block.
    .DESCRIPTION
        Pending      start date is in the future
        Offboarding  a termination date is set and still in the future
        Terminated   the termination date has passed
        Active       otherwise
    .EXAMPLE
        Get-IamPersonStatus -Person $ws.People[0]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [pscustomobject] $Person,
        [datetimeoffset] $Now = [datetimeoffset]::UtcNow
    )

    process {
        $hr = $Person.Data['spec']['hr']
        $termination = ConvertTo-IamDate -Value $hr['terminationDate']
        $start = ConvertTo-IamDate -Value $hr['startDate']

        if ($termination -and $termination -le $Now) { return 'Terminated' }
        if ($termination) { return 'Offboarding' }
        if ($start -and $start -gt $Now) { return 'Pending' }
        'Active'
    }
}

function ConvertTo-IamDate {
    <#
    .SYNOPSIS
        Parses an HR date or timestamp. Dates without a time or offset are read as midnight UTC.
    #>
    [CmdletBinding()]
    [OutputType([datetimeoffset])]
    param([AllowNull()] $Value)

    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    if ($Value -is [datetimeoffset]) { return $Value }
    if ($Value -is [datetime]) { return [datetimeoffset]::new($Value.ToUniversalTime()) }
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    $parsed = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref] $parsed)) {
        return $parsed
    }
    $null
}
