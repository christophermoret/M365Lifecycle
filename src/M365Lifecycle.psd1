New-ModuleManifest -Path .\src\M365Lifecycle\M365Lifecycle.psd1 `
  -RootModule 'M365Lifecycle.psm1' -ModuleVersion '0.1.0' -Author 'Christopher Moret' `
  -Description 'User lifecycle and tenant health toolkit for Microsoft 365' `
  -PowerShellVersion '7.2' `
  -RequiredModules @('Microsoft.Graph.Authentication','ExchangeOnlineManagement') `
  -FunctionsToExport @('New-LcUser','Remove-LcUser','Get-LcLicenseReport','Get-LcSecurityReport')