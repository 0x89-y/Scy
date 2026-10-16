# Runs Scy's checks: PSScriptAnalyzer (with PSScriptAnalyzerSettings.psd1) and
# the Pester tests in this folder. Used by CI (.github/workflows/ci.yml); run it
# locally from Windows PowerShell 5.1 the same way:
#   powershell -NoProfile -File Tests\Invoke-ScyChecks.ps1
# Needs Pester 5.x and PSScriptAnalyzer on the module path:
#   Install-Module Pester -RequiredVersion 5.9.1 -Scope CurrentUser -SkipPublisherCheck
#   Install-Module PSScriptAnalyzer -Scope CurrentUser
# Exits non-zero when anything fails.

param([switch]$SkipAnalyzer, [switch]$SkipTests)

$ErrorActionPreference = 'Stop'
$root   = Split-Path $PSScriptRoot -Parent
$failed = $false

if (-not $SkipAnalyzer) {
    Import-Module PSScriptAnalyzer
    Write-Host "== PSScriptAnalyzer" -ForegroundColor Cyan
    $settings = Import-PowerShellDataFile (Join-Path $root 'PSScriptAnalyzerSettings.psd1')
    # Pester shares variables from BeforeAll/BeforeDiscovery with It blocks, which
    # the analyzer reads as "assigned but never used" - relax that rule for tests only.
    $testSettings = @{ ExcludeRules = @($settings.ExcludeRules) + 'PSUseDeclaredVarsMoreThanAssignments' }

    $findings = @(
        Get-ChildItem $root -Recurse -Include *.ps1, *.psm1, *.psd1 -File |
            Where-Object { $_.FullName -notlike '*\.git\*' } |
            ForEach-Object {
                $s = if ($_.FullName -like "$PSScriptRoot\*") { $testSettings } else { $settings }
                Invoke-ScriptAnalyzer -Path $_.FullName -Settings $s
            }
    )
    if ($findings.Count) {
        $findings | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize -Wrap | Out-String -Width 250 | Write-Host
        Write-Host "$($findings.Count) finding(s)" -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "No findings" -ForegroundColor Green
    }
}

if (-not $SkipTests) {
    Import-Module Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99
    Write-Host "== Pester" -ForegroundColor Cyan
    $config = New-PesterConfiguration
    $config.Run.Path          = $PSScriptRoot
    $config.Run.PassThru      = $true
    $config.Output.Verbosity  = 'Normal'
    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') { $failed = $true }
}

if ($failed) { exit 1 }
