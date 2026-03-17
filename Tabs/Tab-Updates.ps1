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

(Find "BtnCheckUpdates").Add_Click({
    $statusIndicator.Text       = "● Checking for updates..."
    $statusIndicator.Foreground = New-ColorBrush "#fdcb6e"
    $footerStatus.Text          = "Scy - Checking for updates..."
    Set-UpdateBadge "checking"
    $updatePkgPanel.Children.Clear()
    $updatePkgList.Visibility = "Collapsed"
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

    Write-Output-Box $outputUpdates "`r`n▶ Running: winget upgrade`r`n$('─' * 60)" -Clear
    try {
        $raw = @(winget upgrade --accept-source-agreements 2>&1 | ForEach-Object {
            ([string]$_) -replace '\x1b\[[0-9;]*[A-Za-z]', ''
        })
        Write-Output-Box $outputUpdates ($raw -join "`r`n")
        Write-Output-Box $outputUpdates "`r`n✔ Done."

        # Check summary line - winget may localise this text, so match any line
        # that starts with a digit followed by whitespace (e.g. "3 upgrades available.")
        $summaryCount = 0
        $summaryLine  = $raw | Where-Object { $_ -match '^\s*(\d+)\s' } | Select-Object -Last 1
        if ($summaryLine -match '^\s*(\d+)\s') { $summaryCount = [int]$Matches[1] }

        # Find separator - winget may use ASCII hyphens (-) or Unicode box chars (─)
        $sepIdx = $null
        for ($i = 0; $i -lt $raw.Count; $i++) {
            if ($raw[$i] -match '^[-─\u2500]{5,}') { $sepIdx = $i; break }
        }

        $packages = @()
        if ($null -ne $sepIdx -and ($sepIdx + 1) -lt $raw.Count) {
            # Find column positions from the header line (line above the separator).
            # Strip \r in case winget progress output left carriage returns in the line.
            $nameCol = 0; $idCol = -1; $verCol = -1; $availCol = -1
            # Search backwards from separator for a line containing the column headers
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
                    # If Available column not found (e.g. German "Verfügbar" not matched),
                    # infer its position by finding the next 2+-space gap after $verCol
                    if ($availCol -eq -1 -and $verCol -gt 0 -and $hdr.Length -gt $verCol + 1) {
                        $afterVer = [regex]::Match($hdr.Substring($verCol + 1), '\s{2,}\S')
                        if ($afterVer.Success) { $availCol = $verCol + 1 + $afterVer.Index + $afterVer.Length - 1 }
                    }
                    break
                }
            }

            $raw[($sepIdx + 1)..($raw.Count - 1)] | Where-Object { $_.Trim() -ne '' } | ForEach-Object {
                $line = ($_.TrimEnd()) -replace '\r', ''
                if ($line -match '^\s*\d+\s')        { return }   # summary / progress line
                if ($line -match '^[-─\u2500]{5,}')  { return }   # repeated separator

                # Column-position slice when we have a valid header parse
                if ($idCol -gt 0 -and $line.Length -gt $idCol) {
                    $name  = $line.Substring($nameCol, [Math]::Min($idCol, $line.Length) - $nameCol).Trim()
                    $idEnd = if ($verCol  -gt 0) { [Math]::Min($verCol,   $line.Length) } else { $line.Length }
                    $id    = $line.Substring($idCol, $idEnd - $idCol).Trim()
                    $ver   = if ($verCol -gt 0 -and $line.Length -gt $verCol) {
                        $vEnd = if ($availCol -gt 0) { [Math]::Min($availCol, $line.Length) } else { $line.Length }
                        $line.Substring($verCol, $vEnd - $verCol).Trim()
                    } else { '?' }
                    $avail = if ($availCol -gt 0 -and $line.Length -gt $availCol) {
                        $line.Substring($availCol).Trim() -replace '\s.*$', ''  # strip Source column
                    } else { '?' }
                } else {
                    # Fallback: split on 2+ spaces
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

        # If summary says updates exist but parsing found none, trust the summary count
        if ($packages.Count -eq 0 -and $summaryCount -gt 0) {
            Set-UpdateBadge "available" -Count $summaryCount
            $updatePkgCount.Text = "$summaryCount update$(if($summaryCount -ne 1){'s'}) - enable Show Output for details"
            $updatePkgList.Visibility = "Visible"
            $updateBadgeHint.Text = "▲  hide list"
        }

        if ($packages.Count -gt 0) {
            # Build checkbox rows
            foreach ($pkg in $packages) {
                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.IsChecked = $true
                $cb.Tag       = $pkg.Id
                $cb.Margin    = New-Object System.Windows.Thickness(0, 0, 0, 2)
                $cb.Padding   = New-Object System.Windows.Thickness(6, 5, 0, 5)

                $inner = New-Object System.Windows.Controls.StackPanel

                $nameBlock = New-Object System.Windows.Controls.TextBlock
                $nameBlock.Text       = $pkg.Name
                $nameBlock.FontSize   = 12
                $nameBlock.Foreground = New-ColorBrush "#e0e0e8"

                $verBlock = New-Object System.Windows.Controls.TextBlock
                $verBlock.Text       = "$($pkg.Id)  •  $($pkg.Version) → $($pkg.Available)"
                $verBlock.FontSize   = 11
                $verBlock.Foreground = New-ColorBrush "#6b6b80"

                $inner.Children.Add($nameBlock)
                $inner.Children.Add($verBlock)
                $cb.Content = $inner
                $updatePkgPanel.Children.Add($cb)
            }

            $updatePkgCount.Text  = "$($packages.Count) update$(if($packages.Count -ne 1){'s'})"
            $updatePkgList.Visibility = "Visible"
            $updateBadgeHint.Text = "▲  hide list"
            Set-UpdateBadge "available" -Count $packages.Count
        } elseif ($summaryCount -eq 0) {
            Set-UpdateBadge "uptodate"
        }
    } catch {
        Write-Output-Box $outputUpdates "`r`n✖ Error: $_"
        Set-UpdateBadge "uptodate"
    }

    $statusIndicator.Text       = "● Ready"
    $statusIndicator.Foreground = New-ColorBrush "#00b894"
    $footerStatus.Text          = "Ready"
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

    # Show output panel
    $outBorder = Find "OutBorderUpdates"
    $outBorder.Visibility = "Visible"
    (Find "BtnToggleUpdates").Content = "Hide output"

    Write-Output-Box $outputUpdates "`r`n▶ Installing $($selected.Count) selected update(s)...`r`n$('─' * 60)" -Clear

    foreach ($cb in $selected) {
        $pkgId = $cb.Tag
        $statusIndicator.Text       = "● Installing $pkgId..."
        $statusIndicator.Foreground = New-ColorBrush "#fdcb6e"
        $footerStatus.Text          = "Scy - Installing $pkgId..."
        $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

        try {
            $hasProgressLine = $false
            & winget upgrade --id $pkgId --accept-package-agreements --accept-source-agreements 2>&1 | ForEach-Object {
                $line = ([string]$_) -replace '\x1b\[[0-9;]*[A-Za-z]', '' -replace '\r', ''
                # Skip spinner-only and blank lines
                if ($line -match '^\s*[-\\|/]\s*$') { return }
                if ($line.Trim() -eq '') { return }

                if ($line -match '[█▒]') {
                    # Replace the previous progress bar line in-place
                    if ($hasProgressLine) {
                        $txt   = $outputUpdates.Text
                        $cutAt = $txt.LastIndexOf("`r`n", $txt.Length - 3)
                        if ($cutAt -ge 0) { $outputUpdates.Text = $txt.Substring(0, $cutAt + 2) }
                    }
                    $outputUpdates.AppendText("  $($line.Trim())`r`n")
                    $outputUpdates.ScrollToEnd()
                    $hasProgressLine = $true
                } else {
                    $hasProgressLine = $false
                    Write-Output-Box $outputUpdates $line
                }
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
            }
            Write-Output-Box $outputUpdates "✔ $pkgId done."
        } catch {
            Write-Output-Box $outputUpdates "✖ $pkgId`: $_`r`n"
        }
    }

    Write-Output-Box $outputUpdates "`r`n✔ All done."
    $statusIndicator.Text       = "● Ready"
    $statusIndicator.Foreground = New-ColorBrush "#00b894"
    $footerStatus.Text          = "Ready"
    Set-UpdateBadge "updated"
})

(Find "BtnUpdateAll").Add_Click({
    Run-Command $outputUpdates { winget upgrade --all --include-unknown --accept-package-agreements --accept-source-agreements } "winget upgrade --all" "Updating all packages..."
    $updatePkgPanel.Children.Clear()
    Set-UpdateBadge "updated"
})
