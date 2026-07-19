# ── Apps > Installed ──────────────────────────────────────────────
# One scan feeds both jobs this pane does: list what's installed (for export
# or copy) and uninstall a selection. Scanning is async and the rows render in
# batches (Invoke-ExportRenderBatch) - ~4k rows at once froze the UI thread.
$exportResultsPanel  = Find "ExportResultsPanel"
$exportStatus        = Find "ExportStatus"
$exportSummary       = Find "ExportSummary"
$exportFilterCount   = Find "ExportFilterCount"
$exportFilterBox     = Find "ExportFilterBox"
$exportFilterPlaceholder = Find "ExportFilterPlaceholder"
$exportFilterClear   = Find "ExportFilterClear"
$btnExportScan       = Find "BtnExportScan"
$btnExport           = Find "BtnExport"
$btnExportCopy       = Find "BtnExportCopy"

# Store scan results on the panel's Tag so they survive across runspace boundaries
# Tag = @{ Software = [array]; Rows = [arraylist] }
$exportResultsPanel.Tag = @{ Software = @(); Rows = @() }

# ── Filter placeholder ────────────────────────────────────────────
$exportFilterBox.Add_GotFocus({  $exportFilterPlaceholder.Visibility = "Collapsed" })
$exportFilterBox.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($exportFilterBox.Text)) {
        $exportFilterPlaceholder.Visibility = "Visible"
    }
})

# ── Live filter ──────────────────────────────────────────────────
$exportFilterBox.Add_TextChanged({
    $tagData = $exportResultsPanel.Tag
    if (-not $tagData -or -not $tagData.Rows) { return }
    $q = $exportFilterBox.Text.ToLower()
    $exportFilterClear.Visibility = if ($q) { "Visible" } else { "Collapsed" }
    $visible = 0
    foreach ($item in $tagData.Rows) {
        $show = ($q -eq '' -or $item.Tag.ToLower().Contains($q))
        $item.Border.Visibility = if ($show) { "Visible" } else { "Collapsed" }
        if ($show) { $visible++ }
    }
    $total = $tagData.Rows.Count
    if ($total -gt 0 -and $q -ne '') {
        $exportFilterCount.Text = "$visible of $total shown"
    } else {
        $exportFilterCount.Text = ""
    }
})
$exportFilterClear.Add_Click({
    $exportFilterBox.Text = ""
    $exportFilterBox.Focus()
})

# ── Scan ─────────────────────────────────────────────────────────
# The merged Installed list drives both uninstall and export, so keep the count
# label + Uninstall button in sync with the checked winget rows.
function Update-UninstallSelectionCount {
    $sel   = @($script:uninstallItems | Where-Object { $_.CheckBox.IsChecked -eq $true })
    $total = @($script:uninstallItems).Count
    $lbl   = Find "PkgCountLabel"
    if ($lbl) {
        $lbl.Text = if ($sel.Count -gt 0) { "$($sel.Count) of $total selected" } else { "$total apps" }
    }
    $btn = Find "BtnUninstallSelected"
    if ($btn) { $btn.IsEnabled = ($sel.Count -gt 0) }
}

$btnExportScan.Add_Click({
    Set-BusyStatus "Scanning installed apps..."
    $exportResultsPanel.Children.Clear()
    $exportStatus.Text = "Scanning..."
    $exportResultsPanel.Tag = @{ Software = @(); Rows = @() }
    # Rows are rebuilt below; drop the old uninstall registrations
    $script:uninstallItems.Clear()
    (Find "BtnUninstallSelected").IsEnabled = $false

    # Disable buttons during scan
    $btnExport.IsEnabled = $false; $btnExport.Opacity = 0.4
    $btnExportCopy.IsEnabled = $false; $btnExportCopy.Opacity = 0.4

    Start-ScyJob `
        -Work {
            param($emit)
            $allSoftware = @{}

            # ── Winget list ──────────────────────────────────────
            try {
                $wingetOut = & winget list --accept-source-agreements 2>$null
                if ($wingetOut) {
                    $lines = @($wingetOut | ForEach-Object { ($_ -replace '\x1B\[[0-9;]*[mK]', '') -replace '\r', '' })

                    $sepIdx = -1
                    for ($i = 0; $i -lt $lines.Count; $i++) {
                        if ($lines[$i] -match '^-{10,}\s*$') { $sepIdx = $i; break }
                    }

                    if ($sepIdx -gt 0) {
                        $header    = $lines[$sepIdx - 1]
                        $colStarts = @(0)
                        for ($i = 1; $i -lt $header.Length; $i++) {
                            if ($header[$i] -ne ' ' -and $header[$i - 1] -eq ' ') { $colStarts += $i }
                        }

                        for ($r = $sepIdx + 1; $r -lt $lines.Count; $r++) {
                            $line = $lines[$r]
                            if ($line.Trim().Length -lt 2) { continue }

                            $vals = @()
                            for ($ci = 0; $ci -lt $colStarts.Count; $ci++) {
                                $cs = $colStarts[$ci]
                                if ($cs -ge $line.Length) { $vals += ''; continue }
                                $ce = if ($ci + 1 -lt $colStarts.Count) { $colStarts[$ci + 1] } else { $line.Length }
                                $ce = [Math]::Min($ce, $line.Length)
                                $vals += $line.Substring($cs, $ce - $cs).TrimEnd()
                            }

                            $name    = if ($vals.Count -ge 1) { $vals[0].Trim() } else { "" }
                            $id      = if ($vals.Count -ge 2) { $vals[1].Trim() } else { "" }
                            $version = if ($vals.Count -ge 3) { $vals[2].Trim() } else { "" }

                            if ($name -and $name -ne "Name" -and $name -notmatch '^-+$') {
                                $key = $name.ToLower()
                                if (-not $allSoftware.ContainsKey($key)) {
                                    $allSoftware[$key] = [PSCustomObject]@{
                                        Name    = $name
                                        Id      = $id
                                        Version = $version
                                        Source  = "Winget"
                                    }
                                }
                            }
                        }
                    }
                }
            } catch { }

            # ── Registry (traditional installs) ──────────────────
            $regPaths = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
            )
            foreach ($path in $regPaths) {
                try {
                    $items = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                             Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne "" }
                    foreach ($item in $items) {
                        $name    = $item.DisplayName.Trim()
                        $version = if ($item.DisplayVersion) { $item.DisplayVersion.Trim() } else { "" }
                        $pub     = if ($item.Publisher) { $item.Publisher.Trim() } else { "" }
                        $key     = $name.ToLower()

                        if (-not $allSoftware.ContainsKey($key)) {
                            $allSoftware[$key] = [PSCustomObject]@{
                                Name      = $name
                                Id        = ""
                                Version   = $version
                                Source    = "Registry"
                                Publisher = $pub
                                InstallDate     = if ($item.InstallDate) { $item.InstallDate } else { "" }
                                InstallLocation = if ($item.InstallLocation) { $item.InstallLocation } else { "" }
                            }
                        } else {
                            $existing = $allSoftware[$key]
                            if (-not $existing.Publisher -and $pub) {
                                $existing | Add-Member -NotePropertyName "Publisher" -NotePropertyValue $pub -Force
                            }
                            if (-not $existing.InstallDate -and $item.InstallDate) {
                                $existing | Add-Member -NotePropertyName "InstallDate" -NotePropertyValue $item.InstallDate -Force
                            }
                            if (-not $existing.InstallLocation -and $item.InstallLocation) {
                                $existing | Add-Member -NotePropertyName "InstallLocation" -NotePropertyValue $item.InstallLocation -Force
                            }
                        }
                    }
                } catch { }
            }

            $sorted      = @($allSoftware.Values | Sort-Object Name)
            $wingetCount = @($sorted | Where-Object { $_.Source -eq "Winget" }).Count
            $regCount    = @($sorted | Where-Object { $_.Source -eq "Registry" }).Count

            return @{ Sorted = $sorted; WingetCount = $wingetCount; RegCount = $regCount }
        } `
        -OnComplete {
            param($result, $err, $ctx)
            if ($err) {
                $exportStatus.Text = "Scan failed: $($err.Exception.Message)"
                Set-ReadyStatus
                return
            }

            $exportResultsPanel.Children.Clear()

            # Header row
            $hdr = New-Object System.Windows.Controls.Border
            $hdr.Padding = [System.Windows.Thickness]::new(10, 8, 10, 8)
            $hdr.Margin  = [System.Windows.Thickness]::new(0, 0, 0, 4)

            $hGrid = New-Object System.Windows.Controls.Grid
            $hc0 = New-Object System.Windows.Controls.ColumnDefinition; $hc0.Width = New-Object System.Windows.GridLength(3, [System.Windows.GridUnitType]::Star)
            $hc1 = New-Object System.Windows.Controls.ColumnDefinition; $hc1.Width = New-Object System.Windows.GridLength(2, [System.Windows.GridUnitType]::Star)
            $hc2 = New-Object System.Windows.Controls.ColumnDefinition; $hc2.Width = New-Object System.Windows.GridLength(1.5, [System.Windows.GridUnitType]::Star)
            $hc3 = New-Object System.Windows.Controls.ColumnDefinition; $hc3.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
            # Spacer column matching the row checkbox
            $hcChk = New-Object System.Windows.Controls.ColumnDefinition; $hcChk.Width = [System.Windows.GridLength]::Auto
            $hGrid.ColumnDefinitions.Add($hcChk)
            $hGrid.ColumnDefinitions.Add($hc0); $hGrid.ColumnDefinitions.Add($hc1)
            $hGrid.ColumnDefinitions.Add($hc2); $hGrid.ColumnDefinitions.Add($hc3)

            $hSpacer = New-Object System.Windows.Controls.Border
            $hSpacer.Width = 25   # checkbox (15) + its 10px right margin
            [System.Windows.Controls.Grid]::SetColumn($hSpacer, 0)
            $hGrid.Children.Add($hSpacer) | Out-Null

            foreach ($colDef in @(
                @{ T = "Name"; C = 1 }, @{ T = "Publisher"; C = 2 },
                @{ T = "Version"; C = 3 }, @{ T = "Source"; C = 4 }
            )) {
                $h = New-Object System.Windows.Controls.TextBlock
                $h.Text = $colDef.T; $h.FontSize = 11; $h.FontWeight = "SemiBold"
                $h.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                if ($colDef.C -gt 1) { $h.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0) }
                [System.Windows.Controls.Grid]::SetColumn($h, $colDef.C)
                $hGrid.Children.Add($h) | Out-Null
            }
            $hdr.Child = $hGrid
            $exportResultsPanel.Children.Add($hdr) | Out-Null

            # Each row costs ~12 New-Object; with several hundred apps, building
            # them all in this one dispatcher callback locks the UI for seconds.
            # Hand the list to a batched renderer that yields between chunks.
            $script:exportRows = [System.Collections.Generic.Queue[object]]::new()
            foreach ($a in $result.Sorted) { $script:exportRows.Enqueue($a) }
            $script:exportRowTracker = [System.Collections.ArrayList]::new()
            $script:exportSorted     = $result.Sorted
            $script:exportCounts     = @{ Winget = $result.WingetCount; Reg = $result.RegCount }
            Invoke-ExportRenderBatch

            # Feed the store's Install/Uninstall + "Installed" pill state from this
            # user-initiated scan (the store never runs winget on its own).
            if (Get-Command Set-StoreInstalledFromScan -EA SilentlyContinue) {
                Set-StoreInstalledFromScan $result.Sorted
            }
        } | Out-Null
})

# Render the installed list in chunks, yielding to the dispatcher between each
# so input/painting get a turn. Building all rows at once froze the window.
function Invoke-ExportRenderBatch {
    $rowTracker = $script:exportRowTracker
    $batch = 0
    while ($script:exportRows.Count -gt 0 -and $batch -lt 40) {
                $app = $script:exportRows.Dequeue()
                $batch++

                $border = New-Object System.Windows.Controls.Border
                $border.Background   = [System.Windows.Media.Brushes]::Transparent
                $border.BorderBrush  = $window.Resources["BorderBrush"]
                $border.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
                $border.CornerRadius = [System.Windows.CornerRadius]::new(0)
                $border.Padding      = [System.Windows.Thickness]::new(4, 8, 4, 8)
                $border.Margin       = [System.Windows.Thickness]::new(0)

                $rGrid = New-Object System.Windows.Controls.Grid
                # Column 0 is the uninstall checkbox (winget rows only)
                $rcChk = New-Object System.Windows.Controls.ColumnDefinition; $rcChk.Width = [System.Windows.GridLength]::Auto
                $rc0 = New-Object System.Windows.Controls.ColumnDefinition; $rc0.Width = New-Object System.Windows.GridLength(3, [System.Windows.GridUnitType]::Star)
                $rc1 = New-Object System.Windows.Controls.ColumnDefinition; $rc1.Width = New-Object System.Windows.GridLength(2, [System.Windows.GridUnitType]::Star)
                $rc2 = New-Object System.Windows.Controls.ColumnDefinition; $rc2.Width = New-Object System.Windows.GridLength(1.5, [System.Windows.GridUnitType]::Star)
                $rc3 = New-Object System.Windows.Controls.ColumnDefinition; $rc3.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
                $rGrid.ColumnDefinitions.Add($rcChk)
                $rGrid.ColumnDefinitions.Add($rc0); $rGrid.ColumnDefinitions.Add($rc1)
                $rGrid.ColumnDefinitions.Add($rc2); $rGrid.ColumnDefinitions.Add($rc3)

                # Only winget-sourced apps can be uninstalled via winget; registry
                # rows still appear (export needs them) but aren't selectable.
                $isWinget = ($app.Source -eq "Winget")
                $chk = New-Object System.Windows.Controls.CheckBox
                $chk.Style             = $window.Resources["CleanCheckBox"]
                $chk.VerticalAlignment = "Center"
                $chk.Margin            = [System.Windows.Thickness]::new(0, 0, 10, 0)
                $chk.IsEnabled         = $isWinget
                if (-not $isWinget) {
                    $chk.Opacity = 0.35
                    $chk.ToolTip = "Only winget apps can be uninstalled from here"
                }
                $chk.Add_Click({ Update-UninstallSelectionCount })
                [System.Windows.Controls.Grid]::SetColumn($chk, 0)

                $tName = New-Object System.Windows.Controls.TextBlock
                $tName.Text = $app.Name; $tName.FontSize = 11; $tName.TextTrimming = "CharacterEllipsis"
                $tName.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
                [System.Windows.Controls.Grid]::SetColumn($tName, 1)

                $pub = if ($app.PSObject.Properties["Publisher"]) { $app.Publisher } else { "" }
                $tPub = New-Object System.Windows.Controls.TextBlock
                $tPub.Text = $pub; $tPub.FontSize = 11; $tPub.TextTrimming = "CharacterEllipsis"
                $tPub.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
                $tPub.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                [System.Windows.Controls.Grid]::SetColumn($tPub, 2)

                $tVer = New-Object System.Windows.Controls.TextBlock
                $tVer.Text = $app.Version; $tVer.FontSize = 11
                $tVer.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
                $tVer.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
                [System.Windows.Controls.Grid]::SetColumn($tVer, 3)

                $srcBrush = if ($app.Source -eq "Winget") { "AccentBrush" } else { "MutedText" }
                $tSrc = New-Object System.Windows.Controls.TextBlock
                $tSrc.Text = $app.Source; $tSrc.FontSize = 11
                $tSrc.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
                $tSrc.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $srcBrush)
                [System.Windows.Controls.Grid]::SetColumn($tSrc, 4)

                $rGrid.Children.Add($chk)   | Out-Null
                $rGrid.Children.Add($tName) | Out-Null; $rGrid.Children.Add($tPub) | Out-Null
                $rGrid.Children.Add($tVer)  | Out-Null; $rGrid.Children.Add($tSrc) | Out-Null
                $border.Child = $rGrid
                $exportResultsPanel.Children.Add($border) | Out-Null

                $searchTag = "$($app.Name) $pub $($app.Version) $($app.Source)"
                $rowTracker.Add(@{ Border = $border; Tag = $searchTag }) | Out-Null

                # Register winget rows so the shared uninstall handler can act on them
                if ($isWinget) {
                    $script:uninstallItems.Add(@{
                        CheckBox = $chk; Border = $border; Name = $app.Name; Id = $app.Id
                    }) | Out-Null
                }
    }

    # More to do? Queue the next chunk and let the UI breathe first.
    if ($script:exportRows.Count -gt 0) {
        $exportStatus.Text = "Listing... ($($script:exportRowTracker.Count)/$($script:exportSorted.Count))"
        $window.Dispatcher.BeginInvoke(
            [action]{ Invoke-ExportRenderBatch },
            [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
        return
    }

    # Done: finalise once every row is in
    $exportResultsPanel.Tag = @{ Software = $script:exportSorted; Rows = $script:exportRowTracker }
    Update-UninstallSelectionCount

    $exportSummary.Text = "$($script:exportSorted.Count) programs found  ($($script:exportCounts.Winget) Winget, $($script:exportCounts.Reg) Registry-only)"
    $exportStatus.Text  = "Done"

    $btnExport.IsEnabled = $true; $btnExport.Opacity = 1
    $btnExportCopy.IsEnabled = $true; $btnExportCopy.Opacity = 1

    Set-ReadyStatus
}

# ── Helper: build export data from panel Tag ─────────────────────
function Get-ExportData {
    $tagData = $exportResultsPanel.Tag
    if (-not $tagData -or -not $tagData.Software) { return @() }
    $tagData.Software | ForEach-Object {
        $obj = [ordered]@{
            Name    = $_.Name
            Version = $_.Version
            Source  = $_.Source
        }
        if ($_.PSObject.Properties["Id"] -and $_.Id)    { $obj["Id"] = $_.Id }
        if ($_.PSObject.Properties["Publisher"])          { $obj["Publisher"] = $_.Publisher }
        if ($_.PSObject.Properties["InstallDate"])       { $obj["InstallDate"] = $_.InstallDate }
        if ($_.PSObject.Properties["InstallLocation"])   { $obj["InstallLocation"] = $_.InstallLocation }
        [PSCustomObject]$obj
    }
}

# ── Export JSON ──────────────────────────────────────────────────
# One Export button: the format comes from the save dialog's file-type picker
# (the standard Windows pattern) rather than one button per format.
$btnExport.Add_Click({
    $data = Get-ExportData
    if (-not $data -or @($data).Count -eq 0) { return }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter      = "JSON files (*.json)|*.json|CSV files (*.csv)|*.csv"
    $dlg.FilterIndex = 1
    $dlg.FileName    = "$($env:COMPUTERNAME)-installed-apps.json"
    $dlg.Title       = "Export installed apps"
    if ($dlg.ShowDialog()) {
        try {
            # FilterIndex is 1-based: 1 = JSON, 2 = CSV. Fall back to the
            # extension the user actually typed if it disagrees.
            $isCsv = ($dlg.FilterIndex -eq 2)
            if ([System.IO.Path]::GetExtension($dlg.FileName) -ieq ".csv") { $isCsv = $true }
            if ([System.IO.Path]::GetExtension($dlg.FileName) -ieq ".json") { $isCsv = $false }

            if ($isCsv) {
                $data | Export-Csv -Path $dlg.FileName -NoTypeInformation -Encoding UTF8
            } else {
                $json = $data | ConvertTo-Json -Depth 4
                [System.IO.File]::WriteAllText($dlg.FileName, $json, [System.Text.Encoding]::UTF8)
            }
            $exportStatus.Text = "Saved to $($dlg.FileName)"
        } catch {
            $exportStatus.Text = "Export failed: $_"
        }
    }
})

# ── Export CSV ───────────────────────────────────────────────────

# ── Copy to clipboard ───────────────────────────────────────────
$capturedCopyBtn = $btnExportCopy
$btnExportCopy.Add_Click({
    $tagData = $exportResultsPanel.Tag
    if (-not $tagData -or -not $tagData.Software -or @($tagData.Software).Count -eq 0) { return }
    $lines = [System.Collections.ArrayList]::new()
    $lines.Add("Name`tVersion`tSource`tPublisher") | Out-Null
    foreach ($app in $tagData.Software) {
        $pub = if ($app.PSObject.Properties["Publisher"]) { $app.Publisher } else { "" }
        $lines.Add("$($app.Name)`t$($app.Version)`t$($app.Source)`t$pub") | Out-Null
    }
    [System.Windows.Clipboard]::SetText($lines -join "`r`n")
    $capturedCopyBtn.Content = "Copied!"
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromSeconds(1.5)
    $t.Tag = $capturedCopyBtn
    $t.Add_Tick({
        $args[0].Tag.Content = "Copy to clipboard"
        $args[0].Stop()
    })
    $t.Start()
}.GetNewClosure())


# ─────────────────────────────────────────────────────────────────
# Uninstall actions for the Installed list scanned above.
# The scan registers its winget-sourced rows into $script:uninstallItems;
# registry-only rows are listed but carry a disabled checkbox.
# ─────────────────────────────────────────────────────────────────
$uninstallResultsCard   = Find "UninstallResultsCard"
$uninstallResultsPanel  = Find "UninstallResultsPanel"
$uninstallResultsStatus = Find "UninstallResultsStatus"
$uninstallResultsCount  = Find "UninstallResultsCount"

$script:uninstallItems = [System.Collections.Generic.List[hashtable]]::new()


function New-ResultRow {
    param([string]$Name, [string]$Id, [bool]$Success, [bool]$Alternate)

    $accentKey = if ($Success) { "SuccessBrush" } else { "DangerBrush" }
    $iconChar  = if ($Success)   { [char]0x2714 } else { [char]0x2716 }
    $statusTxt = if ($Success)   { "removed" } else { "failed" }

    # cy-design divided list: flush result row, hairline bottom divider.
    $border = New-Object System.Windows.Controls.Border
    $border.Background = [System.Windows.Media.Brushes]::Transparent
    $border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
    $border.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
    $border.CornerRadius = [System.Windows.CornerRadius]::new(0)
    $border.Padding      = [System.Windows.Thickness]::new(4, 10, 4, 10)
    $border.Margin       = [System.Windows.Thickness]::new(0)

    $grid = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::Auto
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::Auto
    $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = [System.Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1)
    $grid.ColumnDefinitions.Add($c2); $grid.ColumnDefinitions.Add($c3)

    $icon                   = New-Object System.Windows.Controls.TextBlock
    $icon.Text              = $iconChar
    $icon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $accentKey)
    $icon.FontSize          = 13
    $icon.Margin            = [System.Windows.Thickness]::new(0, 0, 12, 0)
    $icon.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($icon, 0)

    $nameBlock                   = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text              = $Name
    $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
    $nameBlock.FontSize          = 12
    $nameBlock.VerticalAlignment = "Center"
    $nameBlock.TextTrimming      = "CharacterEllipsis"
    [System.Windows.Controls.Grid]::SetColumn($nameBlock, 1)

    $idBlock                   = New-Object System.Windows.Controls.TextBlock
    $idBlock.Text              = $Id
    $idBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    $idBlock.FontSize          = 11
    $idBlock.Margin            = [System.Windows.Thickness]::new(12, 0, 16, 0)
    $idBlock.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($idBlock, 2)

    $statusBlock                   = New-Object System.Windows.Controls.TextBlock
    $statusBlock.Text              = $statusTxt
    $statusBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $accentKey)
    $statusBlock.FontSize          = 11
    $statusBlock.FontWeight        = [System.Windows.FontWeights]::SemiBold
    $statusBlock.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($statusBlock, 3)

    $grid.Children.Add($icon)        | Out-Null
    $grid.Children.Add($nameBlock)   | Out-Null
    $grid.Children.Add($idBlock)     | Out-Null
    $grid.Children.Add($statusBlock) | Out-Null
    $border.Child = $grid

    return $border
}

# Only winget-sourced rows are uninstallable, and only visible (unfiltered) ones
# should be affected - registry rows carry a disabled checkbox.
(Find "BtnSelectAll").Add_Click({
    foreach ($item in $script:uninstallItems) {
        if ($item.CheckBox.IsEnabled -and $item.Border.Visibility -eq "Visible") { $item.CheckBox.IsChecked = $true }
    }
    if (Get-Command Update-UninstallSelectionCount -ErrorAction SilentlyContinue) { Update-UninstallSelectionCount }
})

(Find "BtnDeselectAll").Add_Click({
    foreach ($item in $script:uninstallItems) { $item.CheckBox.IsChecked = $false }
    if (Get-Command Update-UninstallSelectionCount -ErrorAction SilentlyContinue) { Update-UninstallSelectionCount }
})

(Find "BtnUninstallSelected").Add_Click({
    $selected = @($script:uninstallItems | Where-Object { $_.CheckBox.IsChecked -eq $true })
    if ($selected.Count -eq 0) {
        Show-ThemedDialog "No apps selected. Click a row or check the box to select apps." "Nothing selected" "OK" "Information"
        return
    }

    # Settings > Apps & groups > App behavior > "Skip confirmation for single-app uninstalls"
    $needsConfirm = -not ($selected.Count -eq 1 -and $script:skipSingleUninstallConfirm)
    if ($needsConfirm) {
        $list    = ($selected | ForEach-Object { "  - " + $_.Id }) -join "`n"
        $confirm = Show-ThemedDialog ("Uninstall " + [string]$selected.Count + " app(s)?`n`n" + $list) "Confirm uninstall" "YesNo" "Warning"
        if ($confirm -ne "Yes") { return }
    }

    Set-BusyStatus "Uninstalling..."

    $uninstallResultsPanel.Children.Clear()
    $uninstallResultsCount.Text  = ""
    $uninstallResultsStatus.Text = "Working..."
    $uninstallResultsCard.Visibility = "Visible"
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

    $succeeded = 0
    $failed    = 0
    $i         = 0
    foreach ($item in $selected) {
        $uninstallResultsStatus.Text = "Removing " + $item.Name + " (" + ($i + 1) + " of " + $selected.Count + ")..."
        $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

        & winget uninstall --id $item.Id --silent --accept-source-agreements 2>&1 | Out-Null
        $success = ($LASTEXITCODE -eq 0)

        if (Get-Command Write-ScyLog -ErrorAction SilentlyContinue) {
            Write-ScyLog ("Uninstall " + $(if ($success) { "ok" } else { "FAILED" }) + ": $($item.Name) ($($item.Id))") $(if ($success) { "INFO" } else { "ERROR" })
        }
        if ($success) { $succeeded++ } else { $failed++ }

        $uninstallResultsPanel.Children.Add((New-ResultRow $item.Name $item.Id $success ($i % 2 -eq 0))) | Out-Null
        $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
        $i++
    }

    $uninstallResultsCount.Text = [string]$succeeded
    if ($failed -gt 0) {
        $uninstallResultsCount.Foreground = $window.Resources["WarningBrush"]
        $uninstallResultsStatus.Text = "$succeeded removed, $failed failed - re-scan to refresh the list"
    } else {
        $uninstallResultsCount.Foreground = $window.Resources["SuccessBrush"]
        $uninstallResultsStatus.Text = "$succeeded removed - re-scan to refresh the list"
    }

    Set-ReadyStatus
    if ($selected.Count -gt 1) {
        Show-ScyToast -Title "Scy" -Body ("Uninstall complete: " + [string]$succeeded + " removed, " + [string]$failed + " failed.")
    }
})
