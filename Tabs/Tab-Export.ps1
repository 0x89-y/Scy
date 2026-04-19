# ── Installed Software Exporter ───────────────────────────────────
$exportResultsPanel  = Find "ExportResultsPanel"
$exportStatus        = Find "ExportStatus"
$exportSummary       = Find "ExportSummary"
$exportFilterCount   = Find "ExportFilterCount"
$exportFilterBox     = Find "ExportFilterBox"
$exportFilterPlaceholder = Find "ExportFilterPlaceholder"
$exportFilterClear   = Find "ExportFilterClear"
$btnExportScan       = Find "BtnExportScan"
$btnExportJSON       = Find "BtnExportJSON"
$btnExportCSV        = Find "BtnExportCSV"
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
$btnExportScan.Add_Click({
    Set-BusyStatus "Scanning installed software..."
    $exportResultsPanel.Children.Clear()
    $exportStatus.Text = "Scanning..."
    $exportResultsPanel.Tag = @{ Software = @(); Rows = @() }

    # Disable buttons during scan
    $btnExportJSON.IsEnabled = $false; $btnExportJSON.Opacity = 0.4
    $btnExportCSV.IsEnabled  = $false; $btnExportCSV.Opacity  = 0.4
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
            $hGrid.ColumnDefinitions.Add($hc0); $hGrid.ColumnDefinitions.Add($hc1)
            $hGrid.ColumnDefinitions.Add($hc2); $hGrid.ColumnDefinitions.Add($hc3)

            foreach ($colDef in @(
                @{ T = "Name"; C = 0 }, @{ T = "Publisher"; C = 1 },
                @{ T = "Version"; C = 2 }, @{ T = "Source"; C = 3 }
            )) {
                $h = New-Object System.Windows.Controls.TextBlock
                $h.Text = $colDef.T; $h.FontSize = 11; $h.FontWeight = "SemiBold"
                $h.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                if ($colDef.C -gt 0) { $h.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0) }
                [System.Windows.Controls.Grid]::SetColumn($h, $colDef.C)
                $hGrid.Children.Add($h) | Out-Null
            }
            $hdr.Child = $hGrid
            $exportResultsPanel.Children.Add($hdr) | Out-Null

            $alt        = $false
            $rowTracker = [System.Collections.ArrayList]::new()

            foreach ($app in $result.Sorted) {
                $border = New-Object System.Windows.Controls.Border
                $border.Background   = if ($alt) { $window.Resources["SurfaceBrush"] } else { $window.Resources["InputBgBrush"] }
                $border.CornerRadius = [System.Windows.CornerRadius]::new(4)
                $border.Padding      = [System.Windows.Thickness]::new(10, 6, 10, 6)
                $border.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 2)

                $rGrid = New-Object System.Windows.Controls.Grid
                $rc0 = New-Object System.Windows.Controls.ColumnDefinition; $rc0.Width = New-Object System.Windows.GridLength(3, [System.Windows.GridUnitType]::Star)
                $rc1 = New-Object System.Windows.Controls.ColumnDefinition; $rc1.Width = New-Object System.Windows.GridLength(2, [System.Windows.GridUnitType]::Star)
                $rc2 = New-Object System.Windows.Controls.ColumnDefinition; $rc2.Width = New-Object System.Windows.GridLength(1.5, [System.Windows.GridUnitType]::Star)
                $rc3 = New-Object System.Windows.Controls.ColumnDefinition; $rc3.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
                $rGrid.ColumnDefinitions.Add($rc0); $rGrid.ColumnDefinitions.Add($rc1)
                $rGrid.ColumnDefinitions.Add($rc2); $rGrid.ColumnDefinitions.Add($rc3)

                $tName = New-Object System.Windows.Controls.TextBlock
                $tName.Text = $app.Name; $tName.FontSize = 11; $tName.TextTrimming = "CharacterEllipsis"
                $tName.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
                [System.Windows.Controls.Grid]::SetColumn($tName, 0)

                $pub = if ($app.PSObject.Properties["Publisher"]) { $app.Publisher } else { "" }
                $tPub = New-Object System.Windows.Controls.TextBlock
                $tPub.Text = $pub; $tPub.FontSize = 11; $tPub.TextTrimming = "CharacterEllipsis"
                $tPub.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
                $tPub.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                [System.Windows.Controls.Grid]::SetColumn($tPub, 1)

                $tVer = New-Object System.Windows.Controls.TextBlock
                $tVer.Text = $app.Version; $tVer.FontSize = 11
                $tVer.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
                $tVer.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
                [System.Windows.Controls.Grid]::SetColumn($tVer, 2)

                $srcBrush = if ($app.Source -eq "Winget") { "AccentBrush" } else { "MutedText" }
                $tSrc = New-Object System.Windows.Controls.TextBlock
                $tSrc.Text = $app.Source; $tSrc.FontSize = 11
                $tSrc.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
                $tSrc.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $srcBrush)
                [System.Windows.Controls.Grid]::SetColumn($tSrc, 3)

                $rGrid.Children.Add($tName) | Out-Null; $rGrid.Children.Add($tPub) | Out-Null
                $rGrid.Children.Add($tVer)  | Out-Null; $rGrid.Children.Add($tSrc) | Out-Null
                $border.Child = $rGrid
                $exportResultsPanel.Children.Add($border) | Out-Null

                $searchTag = "$($app.Name) $pub $($app.Version) $($app.Source)"
                $rowTracker.Add(@{ Border = $border; Tag = $searchTag }) | Out-Null
                $alt = -not $alt
            }

            $exportResultsPanel.Tag = @{ Software = $result.Sorted; Rows = $rowTracker }

            $exportSummary.Text = "$($result.Sorted.Count) programs found  ($($result.WingetCount) Winget, $($result.RegCount) Registry-only)"
            $exportStatus.Text  = "Done"

            $btnExportJSON.IsEnabled = $true; $btnExportJSON.Opacity = 1
            $btnExportCSV.IsEnabled  = $true; $btnExportCSV.Opacity  = 1
            $btnExportCopy.IsEnabled = $true; $btnExportCopy.Opacity = 1

            Set-ReadyStatus
        } | Out-Null
})

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
$btnExportJSON.Add_Click({
    $data = Get-ExportData
    if (-not $data -or @($data).Count -eq 0) { return }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter   = "JSON files (*.json)|*.json"
    $dlg.FileName = "$($env:COMPUTERNAME)-installed-software.json"
    $dlg.Title    = "Export installed software as JSON"
    if ($dlg.ShowDialog()) {
        try {
            $json = $data | ConvertTo-Json -Depth 4
            [System.IO.File]::WriteAllText($dlg.FileName, $json, [System.Text.Encoding]::UTF8)
            $exportStatus.Text = "Saved to $($dlg.FileName)"
        } catch {
            $exportStatus.Text = "Export failed: $_"
        }
    }
})

# ── Export CSV ───────────────────────────────────────────────────
$btnExportCSV.Add_Click({
    $data = Get-ExportData
    if (-not $data -or @($data).Count -eq 0) { return }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter   = "CSV files (*.csv)|*.csv"
    $dlg.FileName = "$($env:COMPUTERNAME)-installed-software.csv"
    $dlg.Title    = "Export installed software as CSV"
    if ($dlg.ShowDialog()) {
        try {
            $data | Export-Csv -Path $dlg.FileName -NoTypeInformation -Encoding UTF8
            $exportStatus.Text = "Saved to $($dlg.FileName)"
        } catch {
            $exportStatus.Text = "Export failed: $_"
        }
    }
})

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
