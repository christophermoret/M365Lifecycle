#Requires -Modules Pester

# These tests need no tenant and no Graph modules, so they run anywhere,
# including the GitHub Actions runner. Graph calls are replaced with mocks.

BeforeAll {
    $script:moduleRoot   = Join-Path -Path $PSScriptRoot -ChildPath '..\src\M365Lifecycle'
    $script:manifestPath = Join-Path -Path $moduleRoot -ChildPath 'M365Lifecycle.psd1'

    # Import the .psm1 directly so the RequiredModules in the manifest
    # (Graph, Exchange) do not have to be installed on the CI runner.
    Import-Module (Join-Path -Path $moduleRoot -ChildPath 'M365Lifecycle.psm1') -Force

    # If the Graph SDK is not installed, create an empty stand-in so it can be mocked.
    if (-not (Get-Command -Name Get-MgContext -ErrorAction SilentlyContinue)) {
        function global:Get-MgContext { [CmdletBinding()] param() }
    }
}

AfterAll {
    Remove-Module -Name M365Lifecycle -ErrorAction SilentlyContinue
}

Describe 'Module manifest' {
    BeforeAll {
        $script:manifest = Import-PowerShellDataFile -Path $manifestPath
    }

    It 'has a RootModule that matches a file name exactly, including case' {
        $psm1Files = (Get-ChildItem -Path $moduleRoot -Filter '*.psm1').Name
        ($psm1Files -ccontains $manifest.RootModule) | Should -BeTrue
    }

    It 'does not use wildcards in <_>' -ForEach @('CmdletsToExport', 'VariablesToExport', 'AliasesToExport') {
        ($manifest[$_] -contains '*') | Should -BeFalse
    }
}

Describe 'Exported commands' {
    It 'exports the public function <_>' -ForEach @('Connect-LcTenant', 'New-LcUser') {
        Get-Command -Name $_ -Module M365Lifecycle | Should -Not -BeNullOrEmpty
    }

    It 'keeps the helper <_> private' -ForEach @('Write-LcLog', 'Invoke-LcRetry', 'Get-LcRandomPassword') {
        Get-Command -Name $_ -Module M365Lifecycle -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It '<_> has comment-based help with a description and an example' -ForEach @('Connect-LcTenant', 'New-LcUser') {
        $help = Get-Help -Name $_ -Full
        $help.Description | Should -Not -BeNullOrEmpty
        @($help.Examples.Example).Count | Should -BeGreaterThan 0
    }
}

Describe 'Get-LcRandomPassword' {
    BeforeAll {
        $script:passwords = InModuleScope M365Lifecycle {
            1..50 | ForEach-Object { Get-LcRandomPassword }
        }
    }

    It 'returns the requested length' {
        InModuleScope M365Lifecycle { (Get-LcRandomPassword -Length 20).Length } | Should -Be 20
    }

    It 'always contains upper case, lower case, a digit and a symbol' {
        foreach ($password in $passwords) {
            $password | Should -MatchExactly '[A-Z]'
            $password | Should -MatchExactly '[a-z]'
            $password | Should -Match '[0-9]'
            $password | Should -Match '[^A-Za-z0-9]'
        }
    }

    It 'never uses look-alike characters (0, O, 1, l, I)' {
        foreach ($password in $passwords) {
            $password | Should -Not -MatchExactly '[0O1lI]'
        }
    }

    It 'does not repeat itself' {
        @($passwords | Select-Object -Unique).Count | Should -Be 50
    }

    It 'refuses lengths shorter than 12' {
        { InModuleScope M365Lifecycle { Get-LcRandomPassword -Length 8 } } | Should -Throw
    }
}

Describe 'New-LcUser' {
    It 'stops with a clear message when not connected to Graph' {
        Mock -ModuleName M365Lifecycle -CommandName Get-MgContext -MockWith { $null }

        { New-LcUser -GivenName 'Test' -Surname 'User' -UserPrincipalName 'test.user@example.com' } |
            Should -Throw -ExpectedMessage '*Connect-LcTenant*'
    }
}