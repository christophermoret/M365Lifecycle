function Invoke-LcRetry {
    <#
    .SYNOPSIS
        Runs a script block and retries it with an increasing delay if it fails.
    .DESCRIPTION
        Entra ID is eventually consistent: a user created a moment ago may not yet
        be visible to the licensing or group endpoints. Retrying with a short,
        growing delay handles that without hiding real errors, because the final
        failure is rethrown to the caller.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock]$ScriptBlock,

        [ValidateRange(1, 10)]
        [int]$MaxAttempts = 3,

        [ValidateRange(1, 60)]
        [int]$DelaySeconds = 5
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return (& $ScriptBlock)
        }
        catch {
            if ($attempt -eq $MaxAttempts) { throw }
            $wait = $DelaySeconds * $attempt
            Write-LcLog "Attempt $attempt of $MaxAttempts failed, retrying in $wait seconds. $($_.Exception.Message)" -Level WARN
            Start-Sleep -Seconds $wait
        }
    }
}