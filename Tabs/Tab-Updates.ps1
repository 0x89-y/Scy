# ── Updates Tab ──────────────────────────────────────────────────
$outputUpdates     = Find "OutputUpdates"
$updateStatusDot   = Find "UpdateStatusDot"
$updateStatusTitle = Find "UpdateStatusTitle"
$updateStatusSub   = Find "UpdateStatusSub"
$updateStatusBadge = Find "UpdateStatusBadge"
$updateBadgeHint   = Find "UpdateBadgeHint"
$updatePkgList     = Find "UpdatePkgListBorder"
$updatePkgPanel    = Find "UpdatePkgStackPanel"
$updatePkgCount    = Find "UpdatePkgCountLabel"
$updateProgressBorder = Find "UpdateProgressBorder"
$updateProgressBar    = Find "UpdateProgressBar"
$updateProgressLabel  = Find "UpdateProgressLabel"


function Set-UpdateBadge {
    param([string]$State, [int]$Count = 0, [string]$Message = "")
    switch ($State) {
        "checking" {
            $updateStatusDot.Foreground  = $window.Resources["WarningBrush"]
            $updateStatusTitle.Text      = "Checking..."
            $updateStatusSub.Text        = "Scanning installed apps for available updates"
            $updateBadgeHint.Visibility  = "Collapsed"
            $updateStatusBadge.Cursor    = $null
        }
        "available" {
            $label = if ($Count -eq 1) { "1 update available" } else { "$Count updates available" }
            $updateStatusDot.Foreground  = $window.Resources["WarningBrush"]
            $updateStatusTitle.Text      = $label
            $updateStatusSub.Text        = "Click to view and select which updates to install"
            $updateBadgeHint.Visibility  = "Visible"
            $updateStatusBadge.Cursor    = [System.Windows.Input.Cursors]::Hand
        }
        "uptodate" {
            $updateStatusDot.Foreground  = $window.Resources["SuccessBrush"]
            $updateStatusTitle.Text      = "Up to date"
            $updateStatusSub.Text        = "All apps are up to date"
            $updateBadgeHint.Visibility  = "Collapsed"
            $updateStatusBadge.Cursor    = $null
            $updatePkgList.Visibility    = "Collapsed"
        }
        "updated" {
            $updateStatusDot.Foreground  = $window.Resources["SuccessBrush"]
            $updateStatusTitle.Text      = "Updated"
            $updateStatusSub.Text        = "Run 'Check for Updates' to verify all apps are current"
            $updateBadgeHint.Visibility  = "Collapsed"
            $updateStatusBadge.Cursor    = $null
            $updatePkgList.Visibility    = "Collapsed"
        }
        "error" {
            $updateStatusDot.Foreground  = $window.Resources["DangerBrush"]
            $updateStatusTitle.Text      = "Couldn't check for updates"
            $updateStatusSub.Text        = $Message
            $updateBadgeHint.Visibility  = "Collapsed"
            $updateStatusBadge.Cursor    = $null
            $updatePkgList.Visibility    = "Collapsed"
        }
    }
}

# Toggle the package list when badge is clicked (only when updates are available)
$updateStatusBadge.Add_MouseLeftButtonDown({
    if ($updatePkgList.Children.Count -gt 0 -or $updatePkgPanel.Children.Count -gt 0) {
        $updatePkgList.Visibility = if ($updatePkgList.Visibility -eq "Visible") { "Collapsed" } else { "Visible" }
        $updateBadgeHint.Text = if ($updatePkgList.Visibility -eq "Visible") { "▲  hide list" } else { "▼  view updates" }
    }
})

# Glyphs built from code points so this block stays ASCII-only.
$script:_uCheck   = [string][char]0x2714
$script:_uCross   = [string][char]0x2716
$script:_uDot     = [string][char]0x2022
$script:_uArrow   = [string][char]0x2192
$script:_uUpArrow = [string][char]0x25B2
$script:_uRun     = [string][char]0x25B6
$script:_uRule    = ([string][char]0x2500) * 60
$script:_uSepPat  = '^[-' + [char]0x2500 + ']{5,}'
$script:_uBarPat  = '[' + [char]0x2588 + [char]0x2592 + ']'

# One winget operation at a time; the buttons ignore clicks while one runs.
$script:updatesBusy = $false

function Start-UpdatesOutput([string]$Title) {
    Write-Output-Box $outputUpdates ("`r`n" + $script:_uRun + " " + $Title + "`r`n" + $script:_uRule) -Clear
}

function Add-UpdatesOutput([string]$Text) {
    $outputUpdates.AppendText($Text + "`r`n")
    $outputUpdates.ScrollToEnd()
}

function Set-UpdatesStatus([string]$Text) {
    $footerStatus.Text          = "Scy - " + $Text
}

# Fill the selectable package list and the status badge from a check result.
function Show-UpdateResults {
    param([object[]]$Packages, [int]$Summary)
    $updatePkgPanel.Children.Clear()

    foreach ($pkg in $Packages) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.IsChecked = $true
        $cb.Tag       = $pkg.Id
        $cb.Margin    = New-Object System.Windows.Thickness(0, 0, 0, 2)
        $cb.Padding   = New-Object System.Windows.Thickness(6, 5, 0, 5)

        $inner = New-Object System.Windows.Controls.StackPanel

        $nameBlock = New-Object System.Windows.Controls.TextBlock
        $nameBlock.Text       = $pkg.Name
        $nameBlock.FontSize   = 12
        $nameBlock.Foreground = $window.Resources["FgBrush"]

        $verBlock = New-Object System.Windows.Controls.TextBlock
        $verBlock.Text       = "$($pkg.Id)  $($script:_uDot)  $($pkg.Version) $($script:_uArrow) $($pkg.Available)"
        $verBlock.FontSize   = 11
        $verBlock.Foreground = $window.Resources["MutedText"]

        $inner.Children.Add($nameBlock) | Out-Null
        $inner.Children.Add($verBlock)  | Out-Null
        $cb.Content = $inner
        $updatePkgPanel.Children.Add($cb) | Out-Null
    }

    # winget's summary line can report updates the table parser couldn't read
    $count = if ($Packages.Count -gt 0) { $Packages.Count } else { $Summary }
    if ($count -eq 0) { Set-UpdateBadge "uptodate"; return }

    Set-UpdateBadge "available" $count
    $plural = if ($count -ne 1) { "s" } else { "" }
    $updatePkgCount.Text = if ($Packages.Count -gt 0) { "$count update$plural" } else { "$count update$plural - enable Show Output for details" }
    $updatePkgList.Visibility = "Visible"
    $updateBadgeHint.Text     = "$($script:_uUpArrow)  hide list"
}

# Shared OnLine handler for the install/upgrade jobs. Messages are hashtables:
#   Kind 'line'  - a cleaned output line; Replace overwrites the previous progress bar line
#   Kind 'start' - package $Index of $Total is starting
#   Kind 'done'  - package finished; Ok / Code
$script:onUpdatesJobLine = {
    param($m, $ctx)
    switch ($m.Kind) {
        'line' {
            if ($m.Replace) {
                $txt   = $outputUpdates.Text
                $cutAt = $txt.LastIndexOf("`r`n", [Math]::Max(0, $txt.Length - 3))
                if ($cutAt -ge 0) { $outputUpdates.Text = $txt.Substring(0, $cutAt + 2) }
            }
            Add-UpdatesOutput $m.Text
        }
        'start' {
            Set-UpdatesStatus ("Installing " + $m.Id + "...")
            $updateProgressLabel.Text = "Installing $($m.Index) of $($m.Total): $($m.Id)"
        }
        'done' {
            $w = Get-WingetResult $m.Code
            if ($w.Ok) {
                if ($ctx -and $ctx.Ok) { $ctx.Ok.Value++ }
                Add-UpdatesOutput ("$($script:_uCheck) $($m.Id): $($w.Text)")
            } else {
                Add-UpdatesOutput ("$($script:_uCross) $($m.Id) failed: $($w.Text)")
            }
            $updateProgressBar.Value = $m.Index
        }
    }
}

# Streams one winget invocation's output through $emit. Defined as text so it
# can be handed to the worker runspace (functions don't cross runspaces).
$script:wingetStreamFn = @'
function Invoke-WingetStreamed {
    param([string[]]$WingetArgs, $Emit, [string]$BarPattern)
    $hasProgress = $false
    & winget @WingetArgs 2>&1 | ForEach-Object {
        $line = (([string]$_) -replace '\x1b\[[0-9;]*[A-Za-z]', '') -replace '\r', ''
        if ($line -match '^\s*[-\\|/]\s*$' -or $line.Trim() -eq '') { return }
        $isBar = $line -match $BarPattern
        $text  = if ($isBar) { "  " + $line.Trim() } else { $line }
        & $Emit @{ Kind = 'line'; Text = $text; Replace = ($isBar -and $hasProgress) }
        $hasProgress = $isBar
    }
    return $LASTEXITCODE
}
'@

# Parse `winget upgrade` output into packages, table by table: the main list and
# the "needs explicit targeting" list each get column positions from their own
# header. Column starts are where the header words begin; winget's upgrade tables
# are always Name, Id, Version, Available, Source in that order, so this works in
# any UI language and with single-space gaps in narrow tables.
# Runs inside the check job (its text is handed over), and is unit-tested.
function ConvertFrom-WingetUpgradeOutput {
    param([string[]]$Lines, [string]$SeparatorPattern)
    $raw          = @($Lines)
    $packages     = @()
    $seenIds      = @{}
    $summaryCount = 0
    $seenTable    = $false
    $i = 0
    while ($i -lt $raw.Count) {
        $line = ([string]$raw[$i]) -replace '\r', ''
        if ($i -gt 0 -and $line -match $SeparatorPattern) {
            $seenTable = $true
            $hdr  = ([string]$raw[$i - 1]) -replace '\r', ''
            $cols = @(0)
            for ($c = 1; $c -lt $hdr.Length; $c++) {
                if ($hdr[$c] -ne ' ' -and $hdr[$c - 1] -eq ' ') { $cols += $c }
            }
            $nameCol  = 0
            $idCol    = if ($cols.Count -gt 1) { $cols[1] } else { -1 }
            $verCol   = if ($cols.Count -gt 2) { $cols[2] } else { -1 }
            $availCol = if ($cols.Count -gt 3) { $cols[3] } else { -1 }

            # Rows run until a blank line, a summary line or another separator
            $i++
            while ($i -lt $raw.Count) {
                $row = (([string]$raw[$i]).TrimEnd()) -replace '\r', ''
                if ($row.Trim() -eq '' -or $row -match '^\s*\d+\s' -or $row -match $SeparatorPattern) { break }
                $i++

                if ($idCol -gt 0 -and $row.Length -gt $idCol) {
                    $name  = $row.Substring($nameCol, [Math]::Min($idCol, $row.Length) - $nameCol).Trim()
                    $idEnd = if ($verCol -gt 0) { [Math]::Min($verCol, $row.Length) } else { $row.Length }
                    $id    = $row.Substring($idCol, $idEnd - $idCol).Trim()
                    $ver   = if ($verCol -gt 0 -and $row.Length -gt $verCol) {
                        $vEnd = if ($availCol -gt 0) { [Math]::Min($availCol, $row.Length) } else { $row.Length }
                        $row.Substring($verCol, $vEnd - $verCol).Trim()
                    } else { '?' }
                    # First word only: version strings never contain spaces, and this
                    # stays right even if the Source column doesn't line up exactly
                    $avail = if ($availCol -gt 0 -and $row.Length -gt $availCol) {
                        $row.Substring($availCol).Trim() -replace '\s.*$', ''
                    } else { '?' }
                } else {
                    $parts = @($row -split '\s{2,}' | Where-Object { $_ -ne '' })
                    if ($parts.Count -lt 2) { continue }
                    $name = $parts[0]; $id = $parts[1]
                    $ver   = if ($parts.Count -gt 2) { $parts[2] } else { '?' }
                    $avail = if ($parts.Count -gt 3) { $parts[3] } else { '?' }
                }

                # Notice sentences that run straight into a table have spaces in the "Id" slice
                if ($name -ne '' -and $name -ne 'Name' -and $id -ne '' -and $id -notmatch '\s' -and -not $seenIds.ContainsKey($id)) {
                    $seenIds[$id] = $true
                    $packages += [PSCustomObject]@{ Name = $name; Id = $id; Version = $ver; Available = $avail }
                }
            }
            continue
        }
        # The first number-led line after a table is its count ("9 upgrades available.")
        if ($seenTable -and $summaryCount -eq 0 -and $line -match '^\s*(\d+)\s') { $summaryCount = [int]$Matches[1] }
        $i++
    }
    return @{ Packages = $packages; Summary = $summaryCount }
}

(Find "BtnCheckUpdates").Add_Click({
    if ($script:updatesBusy) { return }
    $script:updatesBusy = $true
    Set-UpdatesStatus "Checking for updates..."
    Set-UpdateBadge "checking"
    $updatePkgPanel.Children.Clear()
    $updatePkgList.Visibility = "Collapsed"
    Start-UpdatesOutput "Running: winget upgrade"

    Start-ScyJob `
        -Variables @{ sepPat = $script:_uSepPat; parseFn = "function ConvertFrom-WingetUpgradeOutput {${function:ConvertFrom-WingetUpgradeOutput}}" } `
        -Work {
            param($emit)
            # (The WinGet PowerShell module was tried here, but its IsUpdateAvailable
            # flag skipped real updates, so the CLI stays the source.)
            . ([scriptblock]::Create($parseFn))
            $raw = @(winget upgrade --accept-source-agreements 2>&1 | ForEach-Object {
                ([string]$_) -replace '\x1b\[[0-9;]*[A-Za-z]', ''
            })
            $parsed = ConvertFrom-WingetUpgradeOutput -Lines $raw -SeparatorPattern $sepPat
            return @{ Raw = $raw; Packages = $parsed.Packages; Summary = $parsed.Summary }
        } `
        -OnComplete {
            param($result, $err, $ctx)
            $script:updatesBusy = $false
            Set-ReadyStatus
            if ($err) {
                Add-UpdatesOutput ("$($script:_uCross) " + $err.Exception.Message)
                Set-UpdateBadge "error" -Message "winget could not be run. Is App Installer installed?"
                return
            }
            Add-UpdatesOutput ($result.Raw -join "`r`n")
            Add-UpdatesOutput "`r`n$($script:_uCheck) Done."
            Show-UpdateResults -Packages @($result.Packages) -Summary $result.Summary
        } | Out-Null
})

(Find "BtnSelectAllUpdates").Add_Click({
    foreach ($cb in $updatePkgPanel.Children) {
        if ($cb -is [System.Windows.Controls.CheckBox]) { $cb.IsChecked = $true }
    }
})

(Find "BtnDeselectAllUpdates").Add_Click({
    foreach ($cb in $updatePkgPanel.Children) {
        if ($cb -is [System.Windows.Controls.CheckBox]) { $cb.IsChecked = $false }
    }
})

(Find "BtnInstallUpdates").Add_Click({
    if ($script:updatesBusy) { return }
    $selected = @($updatePkgPanel.Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] -and $_.IsChecked })
    if ($selected.Count -eq 0) {
        Show-ThemedDialog "No updates selected." "Info" "OK" "Information"
        return
    }
    $confirm = Show-ThemedDialog "Install $($selected.Count) update$(if($selected.Count -ne 1){'s'})? This may take a while." "Confirm" "YesNo" "Question"
    if ($confirm -ne "Yes") { return }

    $pkgIds = @($selected | ForEach-Object { [string]$_.Tag })
    $script:updatesBusy = $true
    Start-UpdatesOutput "Installing $($pkgIds.Count) selected update(s)..."
    Set-UpdatesStatus "Installing updates..."
    Show-ScyProgress -Border $updateProgressBorder -Bar $updateProgressBar -Label $updateProgressLabel `
                     -Text "Installing 1 of $($pkgIds.Count)..." -Value 0 -Max $pkgIds.Count

    Start-ScyJob `
        -Variables @{ pkgIds = $pkgIds; barPat = $script:_uBarPat; streamFn = $script:wingetStreamFn } `
        -Context   @{ Ok = [ref]0 } `
        -Work {
            param($emit)
            . ([scriptblock]::Create($streamFn))
            $total = $pkgIds.Count; $i = 0
            foreach ($pkgId in $pkgIds) {
                $i++
                & $emit @{ Kind = 'start'; Id = $pkgId; Index = $i; Total = $total }
                $code = Invoke-WingetStreamed -Emit $emit -BarPattern $barPat -WingetArgs @(
                    'upgrade', '--id', $pkgId, '--exact', '--accept-package-agreements', '--accept-source-agreements')
                # Success is judged on the UI side (Get-WingetResult): "already up to date" isn't a failure
                & $emit @{ Kind = 'done'; Id = $pkgId; Index = $i; Code = $code }
            }
            return @{ Total = $total }
        } `
        -OnLine $script:onUpdatesJobLine `
        -OnComplete {
            param($result, $err, $ctx)
            $script:updatesBusy = $false
            Hide-ScyProgress $updateProgressBorder $updateProgressBar
            Set-ReadyStatus
            if ($err) {
                Add-UpdatesOutput ("$($script:_uCross) " + $err.Exception.Message)
                return
            }
            $ok = $ctx.Ok.Value
            Add-UpdatesOutput "`r`n$($script:_uCheck) All done: $ok of $($result.Total) updated."
            $updatePkgPanel.Children.Clear()
            Set-UpdateBadge "updated"
            Show-ScyToast -Title "Scy" -Body "Updates finished: $ok of $($result.Total) installed."
        } | Out-Null
})

(Find "BtnUpdateAll").Add_Click({
    if ($script:updatesBusy) { return }
    $script:updatesBusy = $true
    Set-UpdatesStatus "Updating all packages..."
    Start-UpdatesOutput "Running: winget upgrade --all"
    Show-ScyProgress -Border $updateProgressBorder -Bar $updateProgressBar -Label $updateProgressLabel `
                     -Text "Updating all packages..." -Value $null

    Start-ScyJob `
        -Variables @{ barPat = $script:_uBarPat; streamFn = $script:wingetStreamFn } `
        -Work {
            param($emit)
            . ([scriptblock]::Create($streamFn))
            $code = Invoke-WingetStreamed -Emit $emit -BarPattern $barPat -WingetArgs @(
                # Same scope as "Check for updates" (no --include-unknown), so it updates what the list showed
                'upgrade', '--all', '--accept-package-agreements', '--accept-source-agreements')
            return @{ ExitCode = $code }
        } `
        -OnLine $script:onUpdatesJobLine `
        -OnComplete {
            param($result, $err, $ctx)
            $script:updatesBusy = $false
            Hide-ScyProgress $updateProgressBorder $updateProgressBar
            Set-ReadyStatus
            if ($err) {
                Add-UpdatesOutput ("$($script:_uCross) " + $err.Exception.Message)
                return
            }
            Add-UpdatesOutput "`r`n$($script:_uCheck) Done."
            $updatePkgPanel.Children.Clear()
            Set-UpdateBadge "updated"
            Show-ScyToast -Title "Scy" -Body "Update all finished."
        } | Out-Null
})
