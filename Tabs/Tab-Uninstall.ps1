# ── Uninstall Tab ────────────────────────────────────────────────

$pkgPanel               = Find "PkgStackPanel"
$pkgCountLabel          = Find "PkgCountLabel"
$uninstallResultsCard   = Find "UninstallResultsCard"
$uninstallResultsPanel  = Find "UninstallResultsPanel"
$uninstallResultsStatus = Find "UninstallResultsStatus"
$uninstallResultsCount  = Find "UninstallResultsCount"

$script:uninstallItems = [System.Collections.Generic.List[hashtable]]::new()

# ── Helper: package row with checkbox ────────────────────────────
function New-UninstallRow {
    param([string]$Name, [string]$Id, [string]$Version, [bool]$Alternate)

    $border = New-Object System.Windows.Controls.Border
    $bgKey = if ($Alternate) { "SurfaceBrush" } else { "InputBgBrush" }
    $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $bgKey)
    $border.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $border.Padding      = [System.Windows.Thickness]::new(10, 6, 10, 6)
    $border.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 2)
    $border.Cursor       = [System.Windows.Input.Cursors]::Hand

    $grid = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::Auto
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::Auto
    $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = [System.Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1)
    $grid.ColumnDefinitions.Add($c2); $grid.ColumnDefinitions.Add($c3)

    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Margin            = [System.Windows.Thickness]::new(0, 0, 12, 0)
    $cb.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($cb, 0)

    $nameBlock = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text              = $Name
    $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
    $nameBlock.FontSize          = 12
    $nameBlock.VerticalAlignment = "Center"
    $nameBlock.TextTrimming      = "CharacterEllipsis"
    [System.Windows.Controls.Grid]::SetColumn($nameBlock, 1)

    $idBlock = New-Object System.Windows.Controls.TextBlock
    $idBlock.Text              = $Id
    $idBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    $idBlock.FontSize          = 11
    $idBlock.Margin            = [System.Windows.Thickness]::new(12, 0, 16, 0)
    $idBlock.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($idBlock, 2)

    $verBlock = New-Object System.Windows.Controls.TextBlock
    $verBlock.Text              = $Version
    $verBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "SuccessBrush")
    $verBlock.FontSize          = 11
    $verBlock.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($verBlock, 3)

    $grid.Children.Add($cb)        | Out-Null
    $grid.Children.Add($nameBlock) | Out-Null
    $grid.Children.Add($idBlock)   | Out-Null
    $grid.Children.Add($verBlock)  | Out-Null
    $border.Child = $grid

    $border.Add_MouseLeftButtonUp(({ $cb.IsChecked = -not $cb.IsChecked }.GetNewClosure()))

    return @{ Border = $border; CheckBox = $cb; Id = $Id; Name = $Name; Tag = ($Name + " " + $Id).ToLower() }
}

# ── Helper: result row ────────────────────────────────────────────
function New-ResultRow {
    param([string]$Name, [string]$Id, [bool]$Success, [bool]$Alternate)

    $accentKey = if ($Success) { "SuccessBrush" } else { "DangerBrush" }
    $iconChar  = if ($Success)   { [char]0x2714 } else { [char]0x2716 }
    $statusTxt = if ($Success)   { "removed" } else { "failed" }

    $border = New-Object System.Windows.Controls.Border
    $bgKey = if ($Alternate) { "SurfaceBrush" } else { "InputBgBrush" }
    $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $bgKey)
    $border.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $border.Padding      = [System.Windows.Thickness]::new(10, 7, 10, 7)
    $border.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 2)

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

# ── Scan installed ────────────────────────────────────────────────
(Find "BtnScanInstalled").Add_Click({
    $statusIndicator.Text       = "● Scanning..."
    $statusIndicator.Foreground = $window.Resources["WarningBrush"]
    $footerStatus.Text          = "Scy - Scanning installed packages..."
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

    $pkgPanel.Children.Clear()
    $script:uninstallItems.Clear()
    (Find "PkgSearchBox").Text               = ""
    (Find "PkgSearchPlaceholder").Visibility = "Visible"

    try {
        $raw   = & winget list --accept-source-agreements 2>&1
        $lines = @($raw | ForEach-Object { [string]$_ })
        $rows  = @(Get-WingetRows $lines)

        if ($rows.Count -eq 0) { throw "No packages returned by winget." }

        $alt = $false
        foreach ($row in $rows) {
            $name = if ($row.Count -gt 0) { $row[0] } else { "" }
            $id   = if ($row.Count -gt 1) { $row[1] } else { "" }
            $ver  = if ($row.Count -gt 2) { $row[2] } else { "" }
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $item = New-UninstallRow $name $id $ver $alt
            $pkgPanel.Children.Add($item.Border) | Out-Null
            $script:uninstallItems.Add($item)
            $alt = -not $alt
        }

        $pkgCountLabel.Text                    = [string]$script:uninstallItems.Count + " packages installed"
        (Find "PkgListBorder").Visibility       = "Visible"
        (Find "BtnUninstallSelected").IsEnabled = $true

    } catch {
        Show-ThemedDialog ("Scan failed:`n" + $_.Exception.Message) "Scan Error" "OK" "Error"
    }

    $statusIndicator.Text       = "● Ready"
    $statusIndicator.Foreground = $window.Resources["SuccessBrush"]
    $footerStatus.Text          = "Ready"
})

# ── Filter ────────────────────────────────────────────────────────
$script:pkgSearchClear = Find "PkgSearchClear"

(Find "PkgSearchBox").Add_TextChanged({
    $q           = (Find "PkgSearchBox").Text.ToLower()
    $placeholder = Find "PkgSearchPlaceholder"
    $placeholder.Visibility = if ($q) { "Collapsed" } else { "Visible" }
    $script:pkgSearchClear.Visibility = if ($q) { "Visible" } else { "Collapsed" }

    $visible = 0
    foreach ($item in $script:uninstallItems) {
        $show = (-not $q) -or $item.Tag.Contains($q)
        $item.Border.Visibility = if ($show) { "Visible" } else { "Collapsed" }
        if ($show) { $visible++ }
    }
    $total = $script:uninstallItems.Count
    $pkgCountLabel.Text = if ($q) { [string]$visible + " of " + [string]$total + " packages" } else { [string]$total + " packages installed" }
})

$script:pkgSearchClear.Add_Click({
    (Find "PkgSearchBox").Text = ""
})

# ── Select / Deselect All ─────────────────────────────────────────
(Find "BtnSelectAll").Add_Click({
    foreach ($item in $script:uninstallItems) { $item.CheckBox.IsChecked = $true }
})

(Find "BtnDeselectAll").Add_Click({
    foreach ($item in $script:uninstallItems) { $item.CheckBox.IsChecked = $false }
})

# ── Uninstall Selected ────────────────────────────────────────────
(Find "BtnUninstallSelected").Add_Click({
    $selected = @($script:uninstallItems | Where-Object { $_.CheckBox.IsChecked -eq $true })
    if ($selected.Count -eq 0) {
        Show-ThemedDialog "No packages selected. Click a row or check the box to select packages." "Nothing Selected" "OK" "Information"
        return
    }

    $list    = ($selected | ForEach-Object { "  - " + $_.Id }) -join "`n"
    $confirm = Show-ThemedDialog ("Uninstall " + [string]$selected.Count + " package(s)?`n`n" + $list) "Confirm Uninstall" "YesNo" "Warning"
    if ($confirm -ne "Yes") { return }

    $statusIndicator.Text       = "● Uninstalling..."
    $statusIndicator.Foreground = $window.Resources["WarningBrush"]

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

    $statusIndicator.Text       = "● Ready"
    $statusIndicator.Foreground = $window.Resources["SuccessBrush"]
})

