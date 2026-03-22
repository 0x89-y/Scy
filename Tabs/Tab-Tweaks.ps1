# ══════════════════════════════════════════════════════════════════
#  TWEAKS TAB - Dynamic folder-based tweak loader
#
#  To add a new tweak, create a subfolder inside the Tweaks\ folder:
#
#    Tweaks\
#      My_Tweak_Name\
#        Apply.ps1        ← required - runs when applying the tweak
#        Revert.ps1       ← optional - runs when reverting the tweak
#        tweak.json       ← optional - { "group": "...", "description": "..." }
#
#  The folder name is used as the display name (underscores → spaces).
#  Tweaks are auto-grouped by common prefix (e.g. Disable_*, Show_*).
#  You can override the group via the "group" field in tweak.json.
# ══════════════════════════════════════════════════════════════════

$tweaksFolder    = Join-Path $PSScriptRoot "..\Tweaks"
$tweakCheckboxes = @{}   # folderPath -> @{ CheckBox; ApplyScript; RevertScript }

function Build-TweakRow {
    param($Dir)

    $applyScript  = Join-Path $Dir.FullName "Apply.ps1"
    $revertScript = Join-Path $Dir.FullName "Revert.ps1"
    $jsonFile     = Join-Path $Dir.FullName "tweak.json"

    if (-not (Test-Path $applyScript)) { return $null }

    $displayName = $Dir.Name -replace '_', ' '
    $tweakMeta   = if (Test-Path $jsonFile) { Get-Content $jsonFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
    $description = if ($tweakMeta -and $tweakMeta.description) { $tweakMeta.description } else { $null }

    # Outer border
    $border = New-Object System.Windows.Controls.Border
    $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty,   "Surface2Brush")
    $border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty,  "BorderBrush")
    $border.CornerRadius    = [System.Windows.CornerRadius]::new(6)
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $border.Padding         = [System.Windows.Thickness]::new(16, 12, 16, 12)
    $border.Margin          = [System.Windows.Thickness]::new(0, 0, 0, 6)

    # Grid: text column + checkbox column
    $grid = New-Object System.Windows.Controls.Grid
    $col0 = New-Object System.Windows.Controls.ColumnDefinition
    $col0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $col1 = New-Object System.Windows.Controls.ColumnDefinition
    $col1.Width = [System.Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($col0)
    $grid.ColumnDefinitions.Add($col1)

    # Left stack: name + description
    $stack = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($stack, 0)

    $nameBlock            = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text       = $displayName
    $nameBlock.FontSize   = 13
    $nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
    $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
    $stack.Children.Add($nameBlock) | Out-Null

    if ($description) {
        $descBlock              = New-Object System.Windows.Controls.TextBlock
        $descBlock.Text         = $description
        $descBlock.FontSize     = 11
        $descBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
        $descBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $descBlock.Margin       = [System.Windows.Thickness]::new(0, 3, 0, 0)
        $stack.Children.Add($descBlock) | Out-Null
    }

    # Right: checkbox
    $cb                   = New-Object System.Windows.Controls.CheckBox
    $cb.Style             = $window.Resources["TweakToggle"]
    $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.Grid]::SetColumn($cb, 1)

    # Remove button (col 2)
    $col2       = New-Object System.Windows.Controls.ColumnDefinition
    $col2.Width = [System.Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($col2)

    $removeBtn                   = New-Object System.Windows.Controls.Button
    $removeBtn.Content           = "X"
    $removeBtn.FontSize          = 11
    $removeBtn.Padding           = [System.Windows.Thickness]::new(8, 3, 8, 3)
    $removeBtn.Margin            = [System.Windows.Thickness]::new(10, 0, 0, 0)
    $removeBtn.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $removeBtn.Style             = $window.Resources["SecondaryButton"]
    $removeBtn.ToolTip           = "Remove this tweak"
    $removeBtn.Tag               = [PSCustomObject]@{ DirPath = $Dir.FullName; BorderRef = $border; DisplayName = $displayName }
    [System.Windows.Controls.Grid]::SetColumn($removeBtn, 2)

    $removeBtn.Add_Click({
        param($btn, $e)
        $tag  = $btn.Tag
        $conf = Show-ThemedDialog "Remove '$($tag.DisplayName)'? This will delete its folder from disk." "Confirm Remove" "YesNo" "Warning"
        if ($conf -ne "Yes") { return }
        try {
            Remove-Item -Path $tag.DirPath -Recurse -Force
            $tweakCheckboxes.Remove($tag.DirPath)
            Rebuild-TweaksPanel
        } catch {
            Show-ThemedDialog "Failed to remove tweak:`n$_" "Error" "OK" "Error"
        }
    })

    $grid.Children.Add($stack)     | Out-Null
    $grid.Children.Add($cb)        | Out-Null
    $grid.Children.Add($removeBtn) | Out-Null
    $border.Child = $grid

    return @{
        Border       = $border
        CheckBox     = $cb
        ApplyScript  = $applyScript
        RevertScript = $revertScript
        DisplayName  = $displayName
        Description  = $description
        FolderName   = $Dir.Name
    }
}

# ── Grouping logic ────────────────────────────────────────────────

function Get-TweakGroup {
    param($Dir)

    # Explicit tweak.json group takes priority
    $jsonFile = Join-Path $Dir.FullName "tweak.json"
    if (Test-Path $jsonFile) {
        $meta = Get-Content $jsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($meta.group) { return $meta.group }
    }

    # Auto-detect from folder name prefix
    # Match multi-word prefixes like "Dark_Mode" or single-word like "Disable"
    $name = $Dir.Name
    return $null  # will be resolved after scanning all dirs
}

function Resolve-TweakGroups {
    param($Dirs)

    $explicit = @{}
    $names    = @()

    foreach ($dir in $Dirs) {
        $jsonFile = Join-Path $dir.FullName "tweak.json"
        if (Test-Path $jsonFile) {
            $meta = Get-Content $jsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($meta.group) { $explicit[$dir.FullName] = $meta.group }
        }
        $names += $dir.Name
    }

    # Find common prefixes among folder names (at least 2 tweaks share it)
    $prefixCounts = @{}
    foreach ($n in $names) {
        $parts = $n -split '_'
        # Try multi-word prefixes (longest first): "Dark_Mode", then "Dark"
        for ($len = [Math]::Min($parts.Count - 1, 3); $len -ge 1; $len--) {
            $prefix = ($parts[0..($len - 1)] -join '_')
            if (-not $prefixCounts.ContainsKey($prefix)) { $prefixCounts[$prefix] = 0 }
            $prefixCounts[$prefix]++
        }
    }

    # Only keep prefixes with 2+ members; prefer longest match per name
    $validPrefixes = $prefixCounts.Keys | Where-Object { $prefixCounts[$_] -ge 2 } | Sort-Object { $_.Length } -Descending

    $result = @{}
    foreach ($dir in $Dirs) {
        if ($explicit.ContainsKey($dir.FullName)) {
            $result[$dir.FullName] = $explicit[$dir.FullName]
            continue
        }

        $matched = $false
        foreach ($prefix in $validPrefixes) {
            if ($dir.Name.StartsWith("${prefix}_")) {
                $result[$dir.FullName] = ($prefix -replace '_', ' ')
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            $result[$dir.FullName] = "Other"
        }
    }

    return $result
}

# ── Build grouped panel ──────────────────────────────────────────

$script:tweakGroupPanels = @{}  # groupName -> StackPanel (for search filtering)

function Build-GroupHeader {
    param([string]$GroupName, [int]$Count)

    # Use a Border as the clickable header instead of a Button to avoid default hover issues
    $headerBorder = New-Object System.Windows.Controls.Border
    $headerBorder.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "Surface2Brush")
    $headerBorder.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
    $headerBorder.CornerRadius    = [System.Windows.CornerRadius]::new(6)
    $headerBorder.BorderThickness = [System.Windows.Thickness]::new(1)
    $headerBorder.Padding         = [System.Windows.Thickness]::new(14, 9, 14, 9)
    $headerBorder.Margin          = [System.Windows.Thickness]::new(0, 0, 0, 6)
    $headerBorder.Cursor          = [System.Windows.Input.Cursors]::Hand

    $headerGrid = New-Object System.Windows.Controls.Grid
    $hcol0 = New-Object System.Windows.Controls.ColumnDefinition
    $hcol0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $hcol1 = New-Object System.Windows.Controls.ColumnDefinition
    $hcol1.Width = [System.Windows.GridLength]::Auto
    $headerGrid.ColumnDefinitions.Add($hcol0)
    $headerGrid.ColumnDefinitions.Add($hcol1)

    $chevron = New-Object System.Windows.Controls.TextBlock
    $chevron.Text     = "-"
    $chevron.FontSize = 13
    $chevron.FontWeight = [System.Windows.FontWeights]::Bold
    $chevron.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    $chevron.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $chevron.Margin   = [System.Windows.Thickness]::new(0, 0, 10, 0)
    $chevron.Width    = 12

    $titleBlock = New-Object System.Windows.Controls.TextBlock
    $titleBlock.Text       = $GroupName
    $titleBlock.FontSize   = 13
    $titleBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
    $titleBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
    $titleBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $titleStack = New-Object System.Windows.Controls.StackPanel
    $titleStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $titleStack.Children.Add($chevron) | Out-Null
    $titleStack.Children.Add($titleBlock) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($titleStack, 0)

    $countBlock = New-Object System.Windows.Controls.TextBlock
    $countBlock.Text     = "$Count"
    $countBlock.FontSize = 11
    $countBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    $countBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.Grid]::SetColumn($countBlock, 1)

    $headerGrid.Children.Add($titleStack) | Out-Null
    $headerGrid.Children.Add($countBlock)  | Out-Null
    $headerBorder.Child = $headerGrid

    return @{ Border = $headerBorder; Chevron = $chevron; TitleBlock = $titleBlock; CountBlock = $countBlock }
}

function Rebuild-TweaksPanel {
    $groupPanel = Find "TweaksGroupPanel"
    $groupPanel.Children.Clear()
    $tweakCheckboxes.Clear()
    $script:tweakGroupPanels = @{}

    if (-not (Test-Path $tweaksFolder)) { return }

    $tweakDirs = Get-ChildItem -Path $tweaksFolder -Directory -ErrorAction SilentlyContinue | Sort-Object Name
    if (-not $tweakDirs -or $tweakDirs.Count -eq 0) {
        $emptyBlock              = New-Object System.Windows.Controls.TextBlock
        $emptyBlock.Text         = "No tweaks found. Add subfolders with Apply.ps1 to the Tweaks\ folder."
        $emptyBlock.Foreground   = $window.Resources["MutedText"]
        $emptyBlock.FontSize     = 13
        $emptyBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $emptyBlock.Margin       = [System.Windows.Thickness]::new(0, 8, 0, 0)
        $groupPanel.Children.Add($emptyBlock) | Out-Null
        return
    }

    # Resolve groups
    $groupMap = Resolve-TweakGroups $tweakDirs

    # Build rows and organize by group
    $groups = [ordered]@{}
    foreach ($dir in $tweakDirs) {
        $row = Build-TweakRow $dir
        if (-not $row) { continue }

        $gName = $groupMap[$dir.FullName]
        if (-not $groups.Contains($gName)) { $groups[$gName] = @() }
        $groups[$gName] += $row
        $tweakCheckboxes[$dir.FullName] = $row
    }

    # Sort group names: named groups first (alphabetical), "Other" last
    $sortedKeys = $groups.Keys | Where-Object { $_ -ne "Other" } | Sort-Object
    if ($groups.Contains("Other")) { $sortedKeys = @($sortedKeys) + @("Other") }

    foreach ($gName in $sortedKeys) {
        $rows = $groups[$gName]

        # Group container
        $groupContainer = New-Object System.Windows.Controls.StackPanel
        $groupContainer.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)

        # Header
        $header = Build-GroupHeader -GroupName $gName -Count $rows.Count

        $groupContainer.Children.Add($header.Border) | Out-Null

        # Items panel
        $itemsPanel = New-Object System.Windows.Controls.StackPanel
        $itemsPanel.Margin = [System.Windows.Thickness]::new(12, 0, 0, 0)

        foreach ($row in $rows) {
            $itemsPanel.Children.Add($row.Border) | Out-Null
        }

        $groupContainer.Children.Add($itemsPanel) | Out-Null

        # Toggle collapse on header click
        $header.Border.Tag = [PSCustomObject]@{ ItemsPanel = $itemsPanel; Chevron = $header.Chevron }
        $header.Border.Add_MouseLeftButtonUp({
            param($s, $e)
            $tag = $s.Tag
            if ($tag.ItemsPanel.Visibility -eq "Visible") {
                $tag.ItemsPanel.Visibility = "Collapsed"
                $tag.Chevron.Text = "+"
            } else {
                $tag.ItemsPanel.Visibility = "Visible"
                $tag.Chevron.Text = "-"
            }
        })

        $groupPanel.Children.Add($groupContainer) | Out-Null
        $script:tweakGroupPanels[$gName] = @{ Container = $groupContainer; ItemsPanel = $itemsPanel; Rows = $rows; Header = $header }
    }

    # Refresh global search index if available
    if (Get-Command Update-GlobalSearchIndex -ErrorAction SilentlyContinue) {
        Update-GlobalSearchIndex
    }
}

# ── Initial load ──────────────────────────────────────────────────
Rebuild-TweaksPanel

# ── Search ────────────────────────────────────────────────────────

(Find "TweakSearchBox").Add_TextChanged({
    $query = (Find "TweakSearchBox").Text.Trim().ToLower()
    (Find "TweakSearchPlaceholder").Visibility = if ($query) { "Collapsed" } else { "Visible" }
    (Find "TweakSearchClear").Visibility = if ($query) { "Visible" } else { "Collapsed" }

    foreach ($gName in $script:tweakGroupPanels.Keys) {
        $gData    = $script:tweakGroupPanels[$gName]
        $visible  = 0

        foreach ($row in $gData.Rows) {
            $matchName = $row.DisplayName.ToLower().Contains($query)
            $matchDesc = $row.Description -and $row.Description.ToLower().Contains($query)

            if (-not $query -or $matchName -or $matchDesc) {
                $row.Border.Visibility = "Visible"
                $visible++
            } else {
                $row.Border.Visibility = "Collapsed"
            }
        }

        # Hide entire group if no matches; show and expand if matches
        if ($query) {
            if ($visible -gt 0) {
                $gData.Container.Visibility   = "Visible"
                $gData.ItemsPanel.Visibility  = "Visible"
                $gData.Header.Chevron.Text    = "-"
                $gData.Header.CountBlock.Text = "$visible"
            } else {
                $gData.Container.Visibility = "Collapsed"
            }
        } else {
            $gData.Container.Visibility   = "Visible"
            $gData.ItemsPanel.Visibility  = "Visible"
            $gData.Header.Chevron.Text    = "-"
            $gData.Header.CountBlock.Text = "$($gData.Rows.Count)"
        }
    }
})

(Find "TweakSearchClear").Add_Click({
    (Find "TweakSearchBox").Text = ""
    (Find "TweakSearchBox").Focus()
})

# ── Tweak creator ────────────────────────────────────────────────
(Find "BtnToggleTweakCreator").Add_Click({
    $panel = Find "TweakCreatorPanel"
    if ($panel.Visibility -eq "Visible") {
        $panel.Visibility = "Collapsed"
    } else {
        $panel.Visibility = "Visible"
    }
})

(Find "TweakNameBox").Add_TextChanged({
    (Find "TweakNamePlaceholder").Visibility = if ((Find "TweakNameBox").Text) { "Collapsed" } else { "Visible" }
})

(Find "TweakGroupBox").Add_TextChanged({
    (Find "TweakGroupPlaceholder").Visibility = if ((Find "TweakGroupBox").Text) { "Collapsed" } else { "Visible" }
})

(Find "TweakDescBox").Add_TextChanged({
    (Find "TweakDescPlaceholder").Visibility = if ((Find "TweakDescBox").Text) { "Collapsed" } else { "Visible" }
})

(Find "BtnBrowseApply").Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title  = "Select Apply.ps1"
    $dlg.Filter = "PowerShell Script (*.ps1)|*.ps1"
    if ($dlg.ShowDialog()) {
        (Find "TweakApplyPath").Text = $dlg.FileName
        (Find "TweakApplyPlaceholder").Visibility = "Collapsed"
    }
})

(Find "BtnBrowseRevert").Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title  = "Select Revert.ps1"
    $dlg.Filter = "PowerShell Script (*.ps1)|*.ps1"
    if ($dlg.ShowDialog()) {
        (Find "TweakRevertPath").Text = $dlg.FileName
        (Find "TweakRevertPlaceholder").Visibility = "Collapsed"
    }
})

(Find "BtnCreateTweak").Add_Click({
    $name      = (Find "TweakNameBox").Text.Trim()
    $group     = (Find "TweakGroupBox").Text.Trim()
    $desc      = (Find "TweakDescBox").Text.Trim()
    $applyPath = (Find "TweakApplyPath").Text.Trim()

    if (-not $name) {
        Show-ThemedDialog "Please enter a tweak name." "Missing Name" "OK" "Warning"
        return
    }
    if (-not $applyPath) {
        Show-ThemedDialog "Please select an Apply.ps1 file." "Missing File" "OK" "Warning"
        return
    }

    $folderName = $name -replace '\s+', '_'
    $destDir    = Join-Path $tweaksFolder $folderName

    if (Test-Path $destDir) {
        $confirm = Show-ThemedDialog "A tweak named '$name' already exists. Overwrite?" "Already Exists" "YesNo" "Warning"
        if ($confirm -ne "Yes") { return }
    }

    try {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        Copy-Item -Path $applyPath -Destination (Join-Path $destDir "Apply.ps1") -Force

        $revertPath = (Find "TweakRevertPath").Text.Trim()
        if ($revertPath) {
            Copy-Item -Path $revertPath -Destination (Join-Path $destDir "Revert.ps1") -Force
        }
        if ($desc -or $group) {
            $tweakJson = @{}
            if ($group) { $tweakJson.group = $group }
            if ($desc)  { $tweakJson.description = $desc }
            $tweakJson | ConvertTo-Json | Set-Content -Path (Join-Path $destDir "tweak.json") -Encoding UTF8
        }

        # Reload tweaks panel
        Rebuild-TweaksPanel

        # Reset and collapse form
        (Find "TweakNameBox").Text    = ""
        (Find "TweakGroupBox").Text   = ""
        (Find "TweakDescBox").Text    = ""
        (Find "TweakApplyPath").Text  = ""
        (Find "TweakRevertPath").Text = ""
        (Find "TweakApplyPlaceholder").Visibility  = "Visible"
        (Find "TweakRevertPlaceholder").Visibility = "Visible"
        (Find "TweakGroupPlaceholder").Visibility  = "Visible"
        (Find "TweakCreatorPanel").Visibility      = "Collapsed"

        $footerStatus.Text = "Scy - Tweak '$name' created"
    } catch {
        Show-ThemedDialog "Failed to create tweak:`n$_" "Error" "OK" "Error"
    }
})

# ── Apply button ─────────────────────────────────────────────────
(Find "BtnApplyTweaks").Add_Click({
    $applied = 0
    foreach ($key in $tweakCheckboxes.Keys) {
        $row = $tweakCheckboxes[$key]
        if ($row.CheckBox.IsChecked) {
            try {
                & $row.ApplyScript
                $applied++
            } catch {
                Show-ThemedDialog "Error applying tweak: $_" "Error" "OK" "Error"
            }
        }
    }
    if ($applied -eq 0) {
        Show-ThemedDialog "No tweaks selected." "Info" "OK" "Information"
    } else {
        Show-ThemedDialog "Applied $applied tweak(s) successfully!" "Done" "OK" "Information"
    }
})

# ── Revert button ────────────────────────────────────────────────
(Find "BtnRevertTweaks").Add_Click({
    $reverted = 0
    foreach ($key in $tweakCheckboxes.Keys) {
        $row = $tweakCheckboxes[$key]
        if ($row.CheckBox.IsChecked) {
            if (Test-Path $row.RevertScript) {
                try {
                    & $row.RevertScript
                    $row.CheckBox.IsChecked = $false
                    $reverted++
                } catch {
                    Show-ThemedDialog "Error reverting tweak: $_" "Error" "OK" "Error"
                }
            } else {
                Show-ThemedDialog "'$($row.DisplayName)' has no Revert.ps1." "No Revert Available" "OK" "Warning"
            }
        }
    }
    if ($reverted -eq 0) {
        Show-ThemedDialog "No tweaks selected to revert." "Info" "OK" "Information"
    } else {
        Show-ThemedDialog "Reverted $reverted tweak(s)." "Done" "OK" "Information"
    }
})
