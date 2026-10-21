# Tracks the open transaction per connection so queries inside Invoke-IamTransaction join it.
$script:ActiveTransaction = [Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()

function Get-IamActiveTransaction {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Connection)
    $tx = $null
    if ($script:ActiveTransaction.TryGetValue($Connection, [ref] $tx)) { $tx } else { $null }
}
