function Connect-LcTenant {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with certificate-based app authentication.
    .DESCRIPTION
        Reads the tenant ID, client ID and certificate thumbprint from a local
        config file (by default %LOCALAPPDATA%\M365Lifecycle\config.json, outside
        the repository), or takes them as parameters. No secrets are stored in code.
    .PARAMETER ConfigPath
        Path to a JSON file with TenantId, ClientId and CertificateThumbprint.
    .EXAMPLE
        Connect-LcTenant
        Connects using the default config file.
    .EXAMPLE
        Connect-LcTenant -TenantId $tid -ClientId $cid -CertificateThumbprint $thumb
        Connects with explicit values.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Config')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'Config')]
        [string]$ConfigPath = (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'M365Lifecycle\config.json'),

        [Parameter(Mandatory, ParameterSetName = 'Explicit')]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(Mandatory, ParameterSetName = 'Explicit')]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [Parameter(Mandatory, ParameterSetName = 'Explicit')]
        [ValidateNotNullOrEmpty()]
        [string]$CertificateThumbprint
    )

    if ($PSCmdlet.ParameterSetName -eq 'Config') {
        if (-not (Test-Path -Path $ConfigPath)) {
            throw "Config file not found at '$ConfigPath'. Copy config.example.json there and fill in your values."
        }
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        $TenantId              = $config.TenantId
        $ClientId              = $config.ClientId
        $CertificateThumbprint = $config.CertificateThumbprint
    }

    try {
        Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome -ErrorAction Stop
        $context = Get-MgContext
        Write-LcLog "Connected to tenant $($context.TenantId) as app '$($context.AppName)'"

        [PSCustomObject]@{
            TenantId = $context.TenantId
            AppName  = $context.AppName
            AuthType = $context.AuthType
            Scopes   = $context.Scopes -join ', '
        }
    }
    catch {
        Write-LcLog "Connection to Microsoft Graph failed. $($_.Exception.Message)" -Level ERROR
        throw
    }
}