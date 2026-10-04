function Write-LcLog {
    <#
    .SYNOPSIS
        Writes a timestamped line to the M365Lifecycle log file.
    .DESCRIPTION
        Logs go to %LOCALAPPDATA%\M365Lifecycle\logs, outside the repository, so
        they are never committed. INFO lines are also sent to the verbose stream
        and WARN lines to the warning stream. ERROR lines are only logged, because
        the calling function is responsible for raising the error itself.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',

        [string]$Path = (Join-Path -Path $env:LOCALAPPDATA -ChildPath ('M365Lifecycle\logs\M365Lifecycle_{0:yyyy-MM-dd}.log' -f (Get-Date)))
    )

    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1,-5}] {2}' -f (Get-Date), $Level, $Message

    try {
        $folder = Split-Path -Path $Path -Parent
        if (-not (Test-Path -Path $folder)) {
            # -WhatIf:$false so logging still happens when the caller runs with -WhatIf
            New-Item -ItemType Directory -Path $folder -Force -WhatIf:$false -Confirm:$false | Out-Null
        }
        Add-Content -Path $Path -Value $line -WhatIf:$false -Confirm:$false
    }
    catch {
        Write-Warning "Could not write to log file '$Path'. $($_.Exception.Message)"
    }

    switch ($Level) {
        'WARN'  { Write-Warning $Message }
        default { Write-Verbose $line }
    }
}