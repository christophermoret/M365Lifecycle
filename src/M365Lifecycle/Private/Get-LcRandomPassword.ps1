function Get-LcRandomPassword {
    <#
    .SYNOPSIS
        Generates a random temporary password that meets Entra ID complexity rules.
    .DESCRIPTION
        Uses the cryptographic random number generator rather than Get-Random.
        Look-alike characters (0/O, 1/l/I) are excluded so the password can be
        read out to a user over the phone. One character from each set is always
        included, then the result is shuffled.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateRange(12, 64)]
        [int]$Length = 16
    )

    $sets = @(
        'ABCDEFGHJKLMNPQRSTUVWXYZ'
        'abcdefghijkmnopqrstuvwxyz'
        '23456789'
        '!@#$%&*?-_'
    )
    $all = -join $sets
    $rng = [System.Security.Cryptography.RandomNumberGenerator]

    $chars = [System.Collections.Generic.List[char]]::new()
    foreach ($set in $sets) {
        $chars.Add($set[$rng::GetInt32($set.Length)])
    }
    while ($chars.Count -lt $Length) {
        $chars.Add($all[$rng::GetInt32($all.Length)])
    }

    # Fisher-Yates shuffle so the guaranteed characters are not always first
    for ($i = $chars.Count - 1; $i -gt 0; $i--) {
        $j = $rng::GetInt32($i + 1)
        $chars[$i], $chars[$j] = $chars[$j], $chars[$i]
    }

    -join $chars
}