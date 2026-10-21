# Loads private helpers first, then the public commands listed in the manifest.
foreach ($folder in 'Private', 'Public') {
    foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' | Sort-Object Name) {
        . $file.FullName
    }
}
