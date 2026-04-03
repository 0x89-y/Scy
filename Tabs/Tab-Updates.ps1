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

function New-ColorBrush([string]$hex) {
    New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
}

function Set-UpdateBadge {
    param([string]$State, [int]$Count = 0)
    switch ($State) {
        "checking" {
            $updateStatusDot.Foreground  = New-ColorBrush "#fdcb6e"
            $updateStatusTitle.Text      = "Checking..."
            $updateStatusSub.Text        = "Scanning installed packages for available updates"
            $updateBadgeHint.Visibility  = "Collapsed"
            $updateStatusBadge.Cursor    = $null
        }
        "available" {
            $label = if ($Count -eq 1) { "1 update available" } else { "$Count updates available" }
            $updateStatusDot.Foreground  = New-ColorBrush "#fdcb6e"
            $updateStatusTitle.Text      = $label
            $updateStatusSub.Text        = "Click to view and select which updates to install"
            $updateBadgeHint.Visibility  = "Visible"
            $updateStatusBadge.Cursor    = [System.Windows.Input.Cursors]::Hand
        }
        "uptodate" {
            $updateStatusDot.Foreground  = New-ColorBrush "#00b894"
            $updateStatusTitle.Text      = "Up to date"
            $updateStatusSub.Text        = "All packages are up to date"
            $updateBadgeHint.Visibility  = "Collapsed"
            $updateStatusBadge.Cursor    = $null
            $updatePkgList.Visibility    = "Collapsed"
        }
        "updated" {
            $updateStatusDot.Foreground  = New-ColorBrush "#00b894"
            $updateStatusTitle.Text      = "Updated"
            $updateStatusSub.Text        = "Run 'Check for Updates' to verify all packages are current"
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

# Unicode strings used inside runspace scripts - passed as variables to avoid encoding issues
$script:_uDone     = "`r`n" + [char]0x2714 + " Done.`r`n"
$script:_uCheck    = [string][char]0x2714
$script:_uCross    = [string][char]0x2716
$script:_uBullet   = [string][char]0x25CF
$script:_uDot      = [string][char]0x2022
$script:_uArrow    = [string][char]0x2192
$script:_uUpArrow  = [string][char]0x25B2
$script:_uSepPat   = '^[-' + [char]0x2500 + ']{5,}'
$script:_uBarPat   = '[' + [char]0x2588 + [char]0x2592 + ']'

(Find "BtnCheckUpdates").Add_Click({
    $statusIndicator.Text       = "● Checking for updates..."
    $statusIndicator.Foreground = New-ColorBrush "#fdcb6e"
    $footerStatus.Text          = "Scy - Checking for updates..."
    Set-UpdateBadge "checking"
    $updatePkgPanel.Children.Clear()
    $updatePkgList.Visibility = "Collapsed"

    Write-Output-Box $outputUpdates "`r`n▶ Running: winget upgrade`r`n$('─' * 60)" -Clear

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()

    $rs.SessionStateProxy.SetVariable("_win",              $window)
    $rs.SessionStateProxy.SetVariable("_box",              $outputUpdates)
    $rs.SessionStateProxy.SetVariable("_si",               $statusIndicator)
    $rs.SessionStateProxy.SetVariable("_fs",               $footerStatus)
    $rs.SessionStateProxy.SetVariable("_pkgPanel",         $updatePkgPanel)
    $rs.SessionStateProxy.SetVariable("_pkgList",          $updatePkgList)
    $rs.SessionStateProxy.SetVariable("_pkgCount",         $updatePkgCount)
    $rs.SessionStateProxy.SetVariable("_badgeHint",        $updateBadgeHint)
    $rs.SessionStateProxy.SetVariable("_statusDot",        $updateStatusDot)
    $rs.SessionStateProxy.SetVariable("_statusTitle",      $updateStatusTitle)
    $rs.SessionStateProxy.SetVariable("_statusSub",        $updateStatusSub)
    $rs.SessionStateProxy.SetVariable("_statusBadge",      $updateStatusBadge)
    $rs.SessionStateProxy.SetVariable("_uDone",            $script:_uDone)
    $rs.SessionStateProxy.SetVariable("_uCheck",           $script:_uCheck)
    $rs.SessionStateProxy.SetVariable("_uBullet",          $script:_uBullet)
    $rs.SessionStateProxy.SetVariable("_uDot",             $script:_uDot)
    $rs.SessionStateProxy.SetVariable("_uArrow",           $script:_uArrow)
    $rs.SessionStateProxy.SetVariable("_uUpArrow",         $script:_uUpArrow)
    $rs.SessionStateProxy.SetVariable("_uSepPat",          $script:_uSepPat)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    $ps.AddScript({
        function Ui([scriptblock]$sb) {
            $_win.Dispatcher.Invoke($sb, [System.Windows.Threading.DispatcherPriority]::Normal)
        }

        # Run winget upgrade in the background
        $raw = @(winget upgrade --accept-source-agreements 2>&1 | ForEach-Object {
            ([string]$_) -replace '\x1b\[[0-9;]*[A-Za-z]', ''
        })

        Ui {
            $_box.AppendText(($raw -join "`r`n") + "`r`n")
            $_box.AppendText($_uDone)
            $_box.ScrollToEnd()
        }

        # Check summary line
        $summaryCount = 0
        $summaryLine  = $raw | Where-Object { $_ -match '^\s*(\d+)\s' } | Select-Object -Last 1
        if ($summaryLine -match '^\s*(\d+)\s') { $summaryCount = [int]$Matches[1] }

        # Find separator
        $sepIdx = $null
        for ($i = 0; $i -lt $raw.Count; $i++) {
            if ($raw[$i] -match $_uSepPat) { $sepIdx = $i; break }
        }

        $packages = @()
        if ($null -ne $sepIdx -and ($sepIdx + 1) -lt $raw.Count) {
            $nameCol = 0; $idCol = -1; $verCol = -1; $availCol = -1
            for ($hi = $sepIdx - 1; $hi -ge [Math]::Max(0, $sepIdx - 3); $hi--) {
                $hdr = ($raw[$hi]) -replace '\r', ''
                $m   = [regex]::Matches($hdr, '\b(Name|Id|Version|Available)\b', 'IgnoreCase')
                if ($m.Count -ge 2) {
                    foreach ($match in $m) {
                        switch ($match.Value.ToLower()) {
                            'name'      { $nameCol  = $match.Index }
                            'id'        { $idCol    = $match.Index }
                            'version'   { $verCol   = $match.Index }
                            'available' { $availCol = $match.Index }
                        }
                    }
                    if ($idCol    -le $nameCol)  { $idCol    = -1 }
                    if ($verCol   -le $idCol)    { $verCol   = -1 }
                    if ($availCol -le $verCol)   { $availCol = -1 }
                    if ($availCol -eq -1 -and $verCol -gt 0 -and $hdr.Length -gt $verCol + 1) {
                        $afterVer = [regex]::Match($hdr.Substring($verCol + 1), '\s{2,}\S')
                        if ($afterVer.Success) { $availCol = $verCol + 1 + $afterVer.Index + $afterVer.Length - 1 }
                    }
                    break
                }
            }

            $raw[($sepIdx + 1)..($raw.Count - 1)] | Where-Object { $_.Trim() -ne '' } | ForEach-Object {
                $line = ($_.TrimEnd()) -replace '\r', ''
                if ($line -match '^\s*\d+\s')   { return }
                if ($line -match $_uSepPat)     { return }

                if ($idCol -gt 0 -and $line.Length -gt $idCol) {
                    $name  = $line.Substring($nameCol, [Math]::Min($idCol, $line.Length) - $nameCol).Trim()
                    $idEnd = if ($verCol  -gt 0) { [Math]::Min($verCol,   $line.Length) } else { $line.Length }
                    $id    = $line.Substring($idCol, $idEnd - $idCol).Trim()
                    $ver   = if ($verCol -gt 0 -and $line.Length -gt $verCol) {
                        $vEnd = if ($availCol -gt 0) { [Math]::Min($availCol, $line.Length) } else { $line.Length }
                        $line.Substring($verCol, $vEnd - $verCol).Trim()
                    } else { '?' }
                    $avail = if ($availCol -gt 0 -and $line.Length -gt $availCol) {
                        $line.Substring($availCol).Trim() -replace '\s.*$', ''
                    } else { '?' }
                } else {
                    $parts = @($line -split '\s{2,}' | Where-Object { $_ -ne '' })
                    if ($parts.Count -lt 2) { return }
                    $name = $parts[0]; $id = $parts[1]
                    $ver   = if ($parts.Count -gt 2) { $parts[2] } else { '?' }
                    $avail = if ($parts.Count -gt 3) { $parts[3] } else { '?' }
                }

                if ($name -ne '' -and $name -ne 'Name' -and $id -ne '' -and $id -notmatch '\s') {
                    $packages += [PSCustomObject]@{
                        Name      = $name
                        Id        = $id
                        Version   = $ver
                        Available = $avail
                    }
                }
            }
        }

        # Marshal all UI updates back to the dispatcher thread
        $capturedPkgs    = $packages
        $capturedSummary = $summaryCount
        Ui {
            function _NewColorBrush([string]$hex) {
                New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
            }

            if ($capturedPkgs.Count -eq 0 -and $capturedSummary -gt 0) {
                $_statusDot.Foreground  = _NewColorBrush "#fdcb6e"
                $_statusTitle.Text      = if ($capturedSummary -eq 1) { "1 update available" } else { "$capturedSummary updates available" }
                $_statusSub.Text        = "Click to view and select which updates to install"
                $_badgeHint.Visibility  = "Visible"
                $_statusBadge.Cursor    = [System.Windows.Input.Cursors]::Hand
                $_pkgCount.Text         = "$capturedSummary update$(if($capturedSummary -ne 1){'s'}) - enable Show Output for details"
                $_pkgList.Visibility    = "Visible"
                $_badgeHint.Text        = "$_uUpArrow  hide list"
            }

            if ($capturedPkgs.Count -gt 0) {
                foreach ($pkg in $capturedPkgs) {
                    $cb = New-Object System.Windows.Controls.CheckBox
                    $cb.IsChecked = $true
                    $cb.Tag       = $pkg.Id
                    $cb.Margin    = New-Object System.Windows.Thickness(0, 0, 0, 2)
                    $cb.Padding   = New-Object System.Windows.Thickness(6, 5, 0, 5)

                    $inner = New-Object System.Windows.Controls.StackPanel

                    $nameBlock = New-Object System.Windows.Controls.TextBlock
                    $nameBlock.Text       = $pkg.Name
                    $nameBlock.FontSize   = 12
                    $nameBlock.Foreground = _NewColorBrush "#e0e0e8"

                    $verBlock = New-Object System.Windows.Controls.TextBlock
                    $verBlock.Text       = "$($pkg.Id)  $_uDot  $($pkg.Version) $_uArrow $($pkg.Available)"
                    $verBlock.FontSize   = 11
                    $verBlock.Foreground = _NewColorBrush "#6b6b80"

                    $inner.Children.Add($nameBlock)
                    $inner.Children.Add($verBlock)
                    $cb.Content = $inner
                    $_pkgPanel.Children.Add($cb)
                }

                $_pkgCount.Text       = "$($capturedPkgs.Count) update$(if($capturedPkgs.Count -ne 1){'s'})"
                $_pkgList.Visibility  = "Visible"
                $_badgeHint.Text      = "$_uUpArrow  hide list"

                $_statusDot.Foreground  = _NewColorBrush "#fdcb6e"
                $_statusTitle.Text      = if ($capturedPkgs.Count -eq 1) { "1 update available" } else { "$($capturedPkgs.Count) updates available" }
                $_statusSub.Text        = "Click to view and select which updates to install"
                $_badgeHint.Visibility  = "Visible"
                $_statusBadge.Cursor    = [System.Windows.Input.Cursors]::Hand
            } elseif ($capturedSummary -eq 0) {
                $_statusDot.Foreground  = _NewColorBrush "#00b894"
                $_statusTitle.Text      = "Up to date"
                $_statusSub.Text        = "All packages are up to date"
                $_badgeHint.Visibility  = "Collapsed"
                $_statusBadge.Cursor    = $null
                $_pkgList.Visibility    = "Collapsed"
            }

            $_si.Text       = "$_uBullet Ready"
            $_si.Foreground = _NewColorBrush "#00b894"
            $_fs.Text       = "Ready"
        }
    }) | Out-Null

    $ps.BeginInvoke() | Out-Null
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
    $selected = @($updatePkgPanel.Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] -and $_.IsChecked })
    if ($selected.Count -eq 0) {
        Show-ThemedDialog "No updates selected." "Info" "OK" "Information"
        return
    }
    $confirm = Show-ThemedDialog "Install $($selected.Count) update$(if($selected.Count -ne 1){'s'})? This may take a while." "Confirm" "YesNo" "Question"
    if ($confirm -ne "Yes") { return }

    # Collect selected package IDs before entering the runspace
    $pkgIds = @($selected | ForEach-Object { $_.Tag })


    Write-Output-Box $outputUpdates "`r`n▶ Installing $($pkgIds.Count) selected update(s)...`r`n$('─' * 60)" -Clear

    $statusIndicator.Text       = "● Installing updates..."
    $statusIndicator.Foreground = New-ColorBrush "#fdcb6e"
    $footerStatus.Text          = "Scy - Installing updates..."

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()

    $rs.SessionStateProxy.SetVariable("_win",         $window)
    $rs.SessionStateProxy.SetVariable("_box",         $outputUpdates)
    $rs.SessionStateProxy.SetVariable("_si",          $statusIndicator)
    $rs.SessionStateProxy.SetVariable("_fs",          $footerStatus)
    $rs.SessionStateProxy.SetVariable("_pkgIds",      $pkgIds)
    $rs.SessionStateProxy.SetVariable("_statusDot",   $updateStatusDot)
    $rs.SessionStateProxy.SetVariable("_statusTitle", $updateStatusTitle)
    $rs.SessionStateProxy.SetVariable("_statusSub",   $updateStatusSub)
    $rs.SessionStateProxy.SetVariable("_badgeHint",   $updateBadgeHint)
    $rs.SessionStateProxy.SetVariable("_statusBadge", $updateStatusBadge)
    $rs.SessionStateProxy.SetVariable("_pkgList",     $updatePkgList)
    $rs.SessionStateProxy.SetVariable("_pkgPanel",    $updatePkgPanel)
    $rs.SessionStateProxy.SetVariable("_uCheck",          $script:_uCheck)
    $rs.SessionStateProxy.SetVariable("_uCross",          $script:_uCross)
    $rs.SessionStateProxy.SetVariable("_uBullet",         $script:_uBullet)
    $rs.SessionStateProxy.SetVariable("_uBarPat",         $script:_uBarPat)
    $rs.SessionStateProxy.SetVariable("_progressBorder",  $updateProgressBorder)
    $rs.SessionStateProxy.SetVariable("_progressBar",     $updateProgressBar)
    $rs.SessionStateProxy.SetVariable("_progressLabel",   $updateProgressLabel)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    $ps.AddScript({
        function Ui([scriptblock]$sb) {
            $_win.Dispatcher.Invoke($sb, [System.Windows.Threading.DispatcherPriority]::Normal)
        }
        function _NewColorBrush([string]$hex) {
            New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
        }

        $total = $_pkgIds.Count
        $i = 0
        Ui {
            $_progressBar.IsIndeterminate = $false
            $_progressBar.Maximum         = $total
            $_progressBar.Value           = 0
            $_progressLabel.Text          = "Installing 1 of $total..."
            $_progressBorder.Visibility   = "Visible"
        }

        foreach ($pkgId in $_pkgIds) {
            $i++
            Ui {
                $_si.Text             = "$_uBullet Installing $pkgId..."
                $_si.Foreground       = _NewColorBrush "#fdcb6e"
                $_fs.Text             = "Scy - Installing $pkgId..."
                $_progressLabel.Text  = "Installing $i of ${total}: $pkgId"
            }

            try {
                $hasProgressLine = $false
                & winget upgrade --id $pkgId --accept-package-agreements --accept-source-agreements 2>&1 | ForEach-Object {
                    $line = ([string]$_) -replace '\x1b\[[0-9;]*[A-Za-z]', '' -replace '\r', ''
                    if ($line -match '^\s*[-\\|/]\s*$') { return }
                    if ($line.Trim() -eq '') { return }

                    if ($line -match $_uBarPat) {
                        Ui {
                            if ($hasProgressLine) {
                                $txt   = $_box.Text
                                $cutAt = $txt.LastIndexOf("`r`n", $txt.Length - 3)
                                if ($cutAt -ge 0) { $_box.Text = $txt.Substring(0, $cutAt + 2) }
                            }
                            $_box.AppendText("  $($line.Trim())`r`n")
                            $_box.ScrollToEnd()
                        }
                        $hasProgressLine = $true
                    } else {
                        $hasProgressLine = $false
                        Ui {
                            $_box.AppendText("$line`r`n")
                            $_box.ScrollToEnd()
                        }
                    }
                }
                Ui {
                    $_box.AppendText("$_uCheck $pkgId done.`r`n")
                    $_box.ScrollToEnd()
                    $_progressBar.Value = $i
                }
            } catch {
                $errMsg = $_.ToString()
                Ui {
                    $_box.AppendText("$_uCross ${pkgId}: $errMsg`r`n")
                    $_box.ScrollToEnd()
                    $_progressBar.Value = $i
                }
            }
        }

        Ui {
            $_box.AppendText("`r`n$_uCheck All done.`r`n")
            $_box.ScrollToEnd()

            $_progressBorder.Visibility = "Collapsed"

            $_si.Text       = "$_uBullet Ready"
            $_si.Foreground = _NewColorBrush "#00b894"
            $_fs.Text       = "Ready"

            $_statusDot.Foreground  = _NewColorBrush "#00b894"
            $_statusTitle.Text      = "Updated"
            $_statusSub.Text        = "Run 'Check for Updates' to verify all packages are current"
            $_badgeHint.Visibility  = "Collapsed"
            $_statusBadge.Cursor    = $null
            $_pkgList.Visibility    = "Collapsed"
        }
    }) | Out-Null

    $ps.BeginInvoke() | Out-Null
})

(Find "BtnUpdateAll").Add_Click({
    $statusIndicator.Text       = "● Updating all packages..."
    $statusIndicator.Foreground = New-ColorBrush "#fdcb6e"
    $footerStatus.Text          = "Scy - Updating all packages..."

    Write-Output-Box $outputUpdates "`r`n▶ Running: winget upgrade --all`r`n$('─' * 60)" -Clear

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()

    $rs.SessionStateProxy.SetVariable("_win",         $window)
    $rs.SessionStateProxy.SetVariable("_box",         $outputUpdates)
    $rs.SessionStateProxy.SetVariable("_si",          $statusIndicator)
    $rs.SessionStateProxy.SetVariable("_fs",          $footerStatus)
    $rs.SessionStateProxy.SetVariable("_statusDot",   $updateStatusDot)
    $rs.SessionStateProxy.SetVariable("_statusTitle", $updateStatusTitle)
    $rs.SessionStateProxy.SetVariable("_statusSub",   $updateStatusSub)
    $rs.SessionStateProxy.SetVariable("_badgeHint",   $updateBadgeHint)
    $rs.SessionStateProxy.SetVariable("_statusBadge", $updateStatusBadge)
    $rs.SessionStateProxy.SetVariable("_pkgList",     $updatePkgList)
    $rs.SessionStateProxy.SetVariable("_pkgPanel",    $updatePkgPanel)
    $rs.SessionStateProxy.SetVariable("_uDone",          $script:_uDone)
    $rs.SessionStateProxy.SetVariable("_uBullet",        $script:_uBullet)
    $rs.SessionStateProxy.SetVariable("_progressBorder", $updateProgressBorder)
    $rs.SessionStateProxy.SetVariable("_progressBar",    $updateProgressBar)
    $rs.SessionStateProxy.SetVariable("_progressLabel",  $updateProgressLabel)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    $ps.AddScript({
        function Ui([scriptblock]$sb) {
            $_win.Dispatcher.Invoke($sb, [System.Windows.Threading.DispatcherPriority]::Normal)
        }
        function _NewColorBrush([string]$hex) {
            New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
        }

        Ui {
            $_progressBar.IsIndeterminate = $true
            $_progressLabel.Text          = "Updating all packages..."
            $_progressBorder.Visibility   = "Visible"
        }

        $result = & winget upgrade --all --include-unknown --accept-package-agreements --accept-source-agreements 2>&1 | Out-String

        Ui {
            $_box.AppendText($result + "`r`n")
            $_box.AppendText($_uDone)
            $_box.ScrollToEnd()

            $_progressBorder.Visibility = "Collapsed"
            $_progressBar.IsIndeterminate = $false

            $_si.Text       = "$_uBullet Ready"
            $_si.Foreground = _NewColorBrush "#00b894"
            $_fs.Text       = "Ready"

            $_pkgPanel.Children.Clear()
            $_statusDot.Foreground  = _NewColorBrush "#00b894"
            $_statusTitle.Text      = "Updated"
            $_statusSub.Text        = "Run 'Check for Updates' to verify all packages are current"
            $_badgeHint.Visibility  = "Collapsed"
            $_statusBadge.Cursor    = $null
            $_pkgList.Visibility    = "Collapsed"
        }
    }) | Out-Null

    $ps.BeginInvoke() | Out-Null
})
