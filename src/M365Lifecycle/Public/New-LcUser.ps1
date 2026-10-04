function New-LcUser {
    <#
    .SYNOPSIS
        Creates Microsoft 365 users, assigns a license and adds them to groups.
    .DESCRIPTION
        Onboards one or more users through Microsoft Graph. Accepts pipeline input
        by property name, so a CSV can be piped straight in. Each user is handled
        independently: a failure on one user is logged and reported without
        stopping the others. License and group problems do not undo the account;
        they are reported in the Notes field instead.
        Requires an active connection from Connect-LcTenant.
    .PARAMETER UserPrincipalName
        Sign-in name of the new user, for example anna.keller@contoso.ch.
    .PARAMETER UsageLocation
        Two-letter country code, required by Microsoft before a license can be
        assigned. Defaults to CH.
    .PARAMETER LicenseSku
        SkuPartNumber of the license to assign, for example SPB for Microsoft 365
        Business Premium. List yours with: Get-MgSubscribedSku | Select-Object SkuPartNumber
    .PARAMETER Groups
        One or more group display names. A CSV cell can hold several names
        separated by semicolons.
    .EXAMPLE
        Import-Csv .\users.csv | New-LcUser -WhatIf
        Shows what would be created without changing anything.
    .EXAMPLE
        Import-Csv .\users.csv | New-LcUser -Verbose | Format-Table UserPrincipalName, Status, License, GroupsAdded, Notes
        Creates the users and shows a summary table.
    .EXAMPLE
        New-LcUser -GivenName Anna -Surname Keller -UserPrincipalName anna.keller@contoso.ch -LicenseSku SPB -Groups 'Sales'
    .OUTPUTS
        PSCustomObject with one result per user.
    .NOTES
        Mail-enabled security groups and distribution lists cannot be managed
        through Microsoft Graph; use the Exchange Online module for those.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$GivenName,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Surname,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
        [string]$UserPrincipalName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$DisplayName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Department,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$JobTitle,

        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidatePattern('^([A-Za-z]{2})?$')]
        [string]$UsageLocation = 'CH',

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$LicenseSku,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string[]]$Groups
    )

    begin {
        if (-not (Get-MgContext)) {
            throw 'Not connected to Microsoft Graph. Run Connect-LcTenant first.'
        }
        # Look up licenses once for the whole batch instead of once per user
        $skus = @(Get-MgSubscribedSku -All -ErrorAction Stop)
        $groupCache = @{}
    }

    process {
        # Work with local copies: pipeline-bound parameters keep their value from
        # the previous object if a property is missing, so never overwrite them.
        $location   = if ([string]::IsNullOrWhiteSpace($UsageLocation)) { 'CH' } else { $UsageLocation.ToUpper() }
        $name       = if ([string]::IsNullOrWhiteSpace($DisplayName)) { "$GivenName $Surname" } else { $DisplayName }
        $groupNames = @($Groups | ForEach-Object { $_ -split ';' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $notes      = [System.Collections.Generic.List[string]]::new()

        $result = [PSCustomObject]@{
            UserPrincipalName = $UserPrincipalName
            DisplayName       = $name
            Id                = $null
            Status            = 'Pending'
            License           = 'None requested'
            GroupsAdded       = @()
            Notes             = ''
            TemporaryPassword = $null
        }

        try {
            # Double any apostrophes so names like o'brien do not break the OData filter
            $upnFilter = $UserPrincipalName -replace "'", "''"
            $existing = Get-MgUser -Filter "userPrincipalName eq '$upnFilter'" -ErrorAction Stop
            if ($existing) {
                $result.Id = $existing.Id
                $result.Status = 'Skipped'
                $result.Notes = 'User already exists'
                Write-LcLog "Skipped $UserPrincipalName because the user already exists" -Level WARN
                return $result
            }

            if (-not $PSCmdlet.ShouldProcess($UserPrincipalName, 'Create user')) {
                $result.Status = 'WhatIf'
                return $result
            }

            # --- Create the account ---
            $password = Get-LcRandomPassword
            $userParams = @{
                AccountEnabled    = $true
                DisplayName       = $name
                GivenName         = $GivenName
                Surname           = $Surname
                UserPrincipalName = $UserPrincipalName
                MailNickname      = ($UserPrincipalName -split '@')[0]
                UsageLocation     = $location
                PasswordProfile   = @{
                    Password                      = $password
                    ForceChangePasswordNextSignIn = $true
                }
            }
            if ($Department) { $userParams.Department = $Department }
            if ($JobTitle)   { $userParams.JobTitle   = $JobTitle }

            $user = New-MgUser @userParams -ErrorAction Stop
            $result.Id = $user.Id
            $result.TemporaryPassword = $password
            $result.Status = 'Created'
            Write-LcLog "Created user $UserPrincipalName with id $($user.Id)"

            # --- Assign the license ---
            if ($LicenseSku) {
                try {
                    $sku = $skus | Where-Object SkuPartNumber -eq $LicenseSku
                    if (-not $sku) {
                        throw "SKU '$LicenseSku' was not found in this tenant"
                    }
                    if (($sku.PrepaidUnits.Enabled - $sku.ConsumedUnits) -lt 1) {
                        throw "no free '$LicenseSku' licenses left"
                    }
                    Invoke-LcRetry {
                        Set-MgUserLicense -UserId $user.Id -AddLicenses @(@{ SkuId = $sku.SkuId }) -RemoveLicenses @() -ErrorAction Stop | Out-Null
                    }
                    $sku.ConsumedUnits++   # keep the cached count accurate for the rest of the batch
                    $result.License = $LicenseSku
                    Write-LcLog "Assigned license $LicenseSku to $UserPrincipalName"
                }
                catch {
                    $result.License = 'Failed'
                    $notes.Add("License failed: $($_.Exception.Message)")
                    Write-LcLog "License assignment failed for $UserPrincipalName. $($_.Exception.Message)" -Level WARN
                }
            }

            # --- Add to groups ---
            foreach ($groupName in $groupNames) {
                try {
                    if (-not $groupCache.ContainsKey($groupName)) {
                        $groupFilter = $groupName -replace "'", "''"
                        $groupCache[$groupName] = @(Get-MgGroup -Filter "displayName eq '$groupFilter'" -ErrorAction Stop)
                    }
                    $match = $groupCache[$groupName]
                    if ($match.Count -ne 1) {
                        throw "expected exactly one group named '$groupName' but found $($match.Count)"
                    }
                    Invoke-LcRetry {
                        New-MgGroupMember -GroupId $match[0].Id -DirectoryObjectId $user.Id -ErrorAction Stop
                    }
                    $result.GroupsAdded += $groupName
                    Write-LcLog "Added $UserPrincipalName to group '$groupName'"
                }
                catch {
                    $notes.Add("Group '$groupName' failed: $($_.Exception.Message)")
                    Write-LcLog "Could not add $UserPrincipalName to group '$groupName'. $($_.Exception.Message)" -Level WARN
                }
            }

            if ($notes.Count -gt 0) {
                $result.Status = 'Created with warnings'
            }
        }
        catch {
            $result.Status = 'Failed'
            $notes.Add($_.Exception.Message)
            Write-LcLog "Failed to create $UserPrincipalName. $($_.Exception.Message)" -Level ERROR
            Write-Error -Message "Failed to create ${UserPrincipalName}: $($_.Exception.Message)"
        }

        $result.Notes = $notes -join '; '
        $result
    }
}