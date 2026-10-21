function Find-IamPlaintextSecret {
    <# Returns field paths whose key names a credential but whose value is a plain string. #>
    [CmdletBinding()]
    [OutputType([string])]
    param($Node, [string] $Path = '')

    $sensitive = '(?i)(password|passwd|secret|token|apikey|api_key|privatekey|private_key|clientsecret|connectionstring)$'
    if ($Node -is [Collections.IDictionary]) {
        foreach ($key in $Node.Keys) {
            $child = if ($Path) { "$Path.$key" } else { [string]$key }
            $value = $Node[$key]
            # { secret: name } is the reference form, not a secret.
            $isReference = $key -eq 'secret' -and $Node.Count -eq 1
            if ($value -is [string] -and $key -match $sensitive -and -not $isReference) {
                $child
            } else {
                Find-IamPlaintextSecret -Node $value -Path $child
            }
        }
    } elseif ($Node -is [Collections.IList]) {
        for ($i = 0; $i -lt $Node.Count; $i++) {
            Find-IamPlaintextSecret -Node $Node[$i] -Path "$Path[$i]"
        }
    }
}
