# Helpers for the Pester tests.
#
# Scy's code lives in WPF tab scripts that need a window to load, so the tests
# don't dot-source whole files. Get-ScySource pulls individual functions (and
# variable assignments) out of a source file by parse tree; the test then defines
# just those, e.g.:
#   . ([scriptblock]::Create((Get-ScySource 'Tabs\Tab-Hosts.ps1' -Function 'Test-HostsIp')))

function Get-ScySource {
    param(
        [Parameter(Mandatory)][string]$File,
        [string[]]$Function = @(),
        [string[]]$Variable = @()
    )
    $root = Split-Path $PSScriptRoot -Parent
    $ast  = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $File), [ref]$null, [ref]$null)
    $parts = @()
    foreach ($v in $Variable) {
        $a = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq $v }, $true)
        if (-not $a) { throw "Assignment to $v not found in $File" }
        $parts += $a.Extent.Text
    }
    foreach ($f in $Function) {
        $d = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $f }, $true)
        if (-not $d) { throw "Function $f not found in $File" }
        $parts += $d.Extent.Text
    }
    return ($parts -join "`n`n")
}

# Lines of a winget table, columns padded to the given widths (like winget does).
function New-WingetTable {
    param([int[]]$Widths, [string[]]$Header, [object[]]$Rows)
    $fmt = (0..($Widths.Count - 1) | ForEach-Object { if ($_ -lt $Widths.Count - 1) { "{$_,-$($Widths[$_])}" } else { "{$_}" } }) -join ''
    $lines = @($fmt -f $Header)
    $lines += ('-' * (($Widths | Measure-Object -Sum).Sum + 6))
    foreach ($r in $Rows) { $lines += ($fmt -f $r) }
    return $lines
}
