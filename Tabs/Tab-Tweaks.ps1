# ══════════════════════════════════════════════════════════════════
#  TWEAKS TAB - Dynamic folder-based tweak loader
#
#  To add a new tweak, create a subfolder inside the Tweaks\ folder:
#
#    Tweaks\
#      My_Tweak_Name\
#        Apply.ps1        ← required - runs when applying the tweak
#        Revert.ps1       ← optional - runs when reverting the tweak
#        tweak.json       ← optional - { "group": "...", "description": "...", "requiresAdmin": false }
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

    $displayName   = $Dir.Name -replace '_', ' '
    $tweakMeta     = if (Test-Path $jsonFile) { Get-Content $jsonFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
    $description   = if ($tweakMeta -and $tweakMeta.description) { $tweakMeta.description } else { $null }
    $requiresAdmin = if ($tweakMeta -and $tweakMeta.requiresAdmin) { $true } else { $false }
    $caution       = if ($tweakMeta -and $tweakMeta.caution) { $true } else { $false }

    # cy-design divided-list row: flush, hairline bottom divider, 24px inset
    $border = New-Object System.Windows.Controls.Border
    $border.Background      = [System.Windows.Media.Brushes]::Transparent
    $border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
    $border.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
    $border.Padding         = [System.Windows.Thickness]::new(24, 10, 24, 10)
    $border.Cursor          = [System.Windows.Input.Cursors]::Hand
    $border.Add_MouseEnter({ $this.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "HoverSurfaceBrush") })
    $border.Add_MouseLeave({ $this.Background = [System.Windows.Media.Brushes]::Transparent })

    # Grid: text (star) | checkbox (auto)
    $grid = New-Object System.Windows.Controls.Grid
    $col0 = New-Object System.Windows.Controls.ColumnDefinition; $col0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = [System.Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($col0)
    $grid.ColumnDefinitions.Add($col1)

    # Left stack: name row + optional description
    $stack = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($stack, 0)

    $nameRow             = New-Object System.Windows.Controls.StackPanel
    $nameRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal

    $nameBlock            = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text       = $displayName
    $nameBlock.FontSize   = 12
    $nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
    $nameBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
    $nameRow.Children.Add($nameBlock) | Out-Null

    if ($requiresAdmin) {
        $adminBadge                   = New-Object System.Windows.Controls.Border
        $adminBadge.BorderThickness   = [System.Windows.Thickness]::new(1)
        $adminBadge.CornerRadius      = [System.Windows.CornerRadius]::new(7)
        $adminBadge.Padding           = [System.Windows.Thickness]::new(6, 1, 6, 1)
        $adminBadge.Margin            = [System.Windows.Thickness]::new(8, 0, 0, 0)
        $adminBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $adminBadge.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "WarningBrush")
        $adminBadgeText               = New-Object System.Windows.Controls.TextBlock
        $adminBadgeText.Text          = "Admin"
        $adminBadgeText.FontSize      = 10
        $adminBadgeText.FontWeight    = [System.Windows.FontWeights]::SemiBold
        $adminBadgeText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "WarningBrush")
        $adminBadge.Child             = $adminBadgeText
        $nameRow.Children.Add($adminBadge) | Out-Null
    }

    if ($caution) {
        $cautionBadge                   = New-Object System.Windows.Controls.Border
        $cautionBadge.BorderThickness   = [System.Windows.Thickness]::new(1)
        $cautionBadge.CornerRadius      = [System.Windows.CornerRadius]::new(7)
        $cautionBadge.Padding           = [System.Windows.Thickness]::new(6, 1, 6, 1)
        $cautionBadge.Margin            = [System.Windows.Thickness]::new(8, 0, 0, 0)
        $cautionBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $cautionBadge.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "DangerBrush")
        $cautionBadgeText               = New-Object System.Windows.Controls.TextBlock
        $cautionBadgeText.Text          = "Caution"
        $cautionBadgeText.FontSize      = 10
        $cautionBadgeText.FontWeight    = [System.Windows.FontWeights]::SemiBold
        $cautionBadgeText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "DangerBrush")
        $cautionBadge.Child             = $cautionBadgeText
        $nameRow.Children.Add($cautionBadge) | Out-Null
    }

    $stack.Children.Add($nameRow) | Out-Null

    if ($description) {
        $descBlock              = New-Object System.Windows.Controls.TextBlock
        $descBlock.Text         = $description
        $descBlock.FontSize     = 11
        $descBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
        $descBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $descBlock.Margin       = [System.Windows.Thickness]::new(0, 2, 0, 0)
        $stack.Children.Add($descBlock) | Out-Null
    }

    # Checkbox
    $cb                   = New-Object System.Windows.Controls.CheckBox
    $cb.Style             = $window.Resources["TweakToggle"]
    $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $cb.Margin            = [System.Windows.Thickness]::new(12, 0, 0, 0)
    [System.Windows.Controls.Grid]::SetColumn($cb, 1)

    # Right-click context menu for Remove
    $ctxMenu              = New-Object System.Windows.Controls.ContextMenu
    $miRemove             = New-Object System.Windows.Controls.MenuItem
    $miRemove.Header      = "Remove"
    $miRemove.Tag         = [PSCustomObject]@{ DirPath = $Dir.FullName; DisplayName = $displayName }
    $miRemove.Add_Click({
        param($mi, $e)
        $tag  = $mi.Tag
        $conf = Show-ThemedDialog "Remove '$($tag.DisplayName)'? This will delete its folder from disk." "Confirm remove" "YesNo" "Warning"
        if ($conf -ne "Yes") { return }
        try {
            Remove-Item -Path $tag.DirPath -Recurse -Force
            $tweakCheckboxes.Remove($tag.DirPath)
            Rebuild-TweaksPanel
        } catch {
            Show-ThemedDialog "Failed to remove tweak:`n$_" "Error" "OK" "Error"
        }
    })
    $ctxMenu.Items.Add($miRemove) | Out-Null
    $border.ContextMenu = $ctxMenu

    # Click anywhere on the row to toggle the checkbox.
    # Skip when the click originates on the checkbox itself (the checkbox handles its own click).
    $border.Tag = $cb
    $border.Add_MouseLeftButtonUp({
        param($s, $e)
        $captured = $s.Tag
        if (-not $captured) { return }
        $src = $e.OriginalSource
        while ($src) {
            if ($src -eq $captured) { return }
            try { $src = [System.Windows.Media.VisualTreeHelper]::GetParent($src) } catch { $src = $null }
        }
        $captured.IsChecked = -not $captured.IsChecked
    })

    $grid.Children.Add($stack) | Out-Null
    $grid.Children.Add($cb)    | Out-Null
    $border.Child = $grid

    return @{
        Border        = $border
        CheckBox      = $cb
        ApplyScript   = $applyScript
        RevertScript  = $revertScript
        DisplayName   = $displayName
        Description   = $description
        FolderName    = $Dir.Name
        RequiresAdmin = $requiresAdmin
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
$script:tweakGroupOrder  = @()  # group names in rail order


function Rebuild-TweaksPanel {
    $groupPanel = Find "TweaksGroupPanel"
    $groupPanel.Children.Clear()
    $tweakCheckboxes.Clear()
    $script:tweakGroupPanels = @{}
    $script:tweakGroupOrder  = @()

    if (-not (Test-Path $tweaksFolder)) { return }

    $tweakDirs = Get-ChildItem -Path $tweaksFolder -Directory -ErrorAction SilentlyContinue | Sort-Object Name
    if (-not $tweakDirs -or $tweakDirs.Count -eq 0) {
        $emptyBlock              = New-Object System.Windows.Controls.TextBlock
        $emptyBlock.Text         = 'No tweaks yet. Click "+ Add tweak" to create one.'
        $emptyBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
        $emptyBlock.FontSize     = 13
        $emptyBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $emptyBlock.Margin       = [System.Windows.Thickness]::new(0, 8, 0, 0)
        $groupPanel.Children.Add($emptyBlock) | Out-Null
        Update-TweakFooterCounts
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
    $script:tweakGroupOrder = @($sortedKeys)   # drives the rail

    foreach ($gName in $sortedKeys) {
        $rows = $groups[$gName]

        # No group header: the rail carries the categories now, so each group is
        # just a flush run of rows. "All tweaks" then reads as one continuous
        # divided list (each row draws its own bottom hairline).
        $itemsPanel = New-Object System.Windows.Controls.StackPanel

        foreach ($row in $rows) {
            $itemsPanel.Children.Add($row.Border) | Out-Null
        }

        foreach ($r in $rows) {
            $r.CheckBox.Add_Checked({   Update-TweakFooterCounts })
            $r.CheckBox.Add_Unchecked({ Update-TweakFooterCounts })
        }

        $groupPanel.Children.Add($itemsPanel) | Out-Null
        $script:tweakGroupPanels[$gName] = @{ Container = $itemsPanel; ItemsPanel = $itemsPanel; Rows = $rows }
    }
    Update-TweakFooterCounts

    # Rebuild the rail and re-apply the current selection (falls back to All tweaks)
    $keep = if ($null -ne $script:tweaksSubNavIndex) { $script:tweaksSubNavIndex } else { 0 }
    Set-TweaksSubNav $keep

    # Refresh global search index if available
    if (Get-Command Update-GlobalSearchIndex -ErrorAction SilentlyContinue) {
        Update-GlobalSearchIndex
    }
}

# ── Tweaks rail: "All tweaks" + one entry per category ────────────
# Index 0 shows every group; any other index shows just that group.
function Set-TweaksSubNav {
    param([int]$Index)

    $labels = @("All tweaks") + @($script:tweakGroupOrder)
    if ($Index -lt 0 -or $Index -ge $labels.Count) { $Index = 0 }
    $script:tweaksSubNavIndex = $Index

    $counts = @($tweakCheckboxes.Count)
    foreach ($g in $script:tweakGroupOrder) {
        $counts += @($script:tweakGroupPanels[$g].Rows).Count
    }

    foreach ($g in $script:tweakGroupOrder) {
        $container = $script:tweakGroupPanels[$g].Container
        if ($container) {
            $container.Visibility = if ($Index -eq 0 -or $labels[$Index] -eq $g) { "Visible" } else { "Collapsed" }
        }
    }

    Build-Rail -Panel (Find "TweaksRail") -Labels $labels -Counts $counts `
               -ActiveIndex $Index -OnSelect { param($i) Set-TweaksSubNav $i }
}

# ── Footer button counts ─────────────────────────────────────────
function Update-TweakFooterCounts {
    $count = 0
    foreach ($key in $tweakCheckboxes.Keys) {
        if ($tweakCheckboxes[$key].CheckBox.IsChecked) { $count++ }
    }
    # The count lives in the footer label now, so the buttons keep clean labels.
    $btnApply  = Find "BtnApplyTweaks"
    $btnRevert = Find "BtnRevertTweaks"
    $countText = Find "TweakFooterCount"
    if ($countText) {
        $countText.Text = switch ($count) {
            0       { "" }
            1       { "1 tweak selected" }
            default { "$count tweaks selected" }
        }
    }
    $btnApply.IsEnabled  = ($count -gt 0)
    $btnRevert.IsEnabled = ($count -gt 0)
}

# ── Collapse all button visibility + label ───────────────────────

# ── Initial load ──────────────────────────────────────────────────
# Deferred to first Tweaks-tab visit (Invoke-ScyTabInit in Scy.ps1) so the
# folder scan + row building doesn't slow startup.

# ── Search ────────────────────────────────────────────────────────

(Find "TweakSearchBox").Add_TextChanged({
    $query = (Find "TweakSearchBox").Text.Trim().ToLower()
    (Find "TweakSearchPlaceholder").Visibility = if ($query) { "Collapsed" } else { "Visible" }
    (Find "TweakSearchClear").Visibility = if ($query) { "Visible" } else { "Collapsed" }

    foreach ($gName in $script:tweakGroupPanels.Keys) {
        $gData   = $script:tweakGroupPanels[$gName]
        $visible = 0

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

        # While searching, span every category and hide the ones with no hits
        if ($query) {
            $gData.Container.Visibility = if ($visible -gt 0) { "Visible" } else { "Collapsed" }
        }
    }

    # Clearing the box hands control back to the rail selection
    if (-not $query) {
        Set-TweaksSubNav $(if ($null -ne $script:tweaksSubNavIndex) { $script:tweaksSubNavIndex } else { 0 })
    }
})

(Find "TweakSearchClear").Add_Click({
    (Find "TweakSearchBox").Text = ""
    (Find "TweakSearchBox").Focus()
})

# ── Collapse all / Expand all button ─────────────────────────────

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
    $needsAdmin = (Find "TweakRequiresAdminToggle").IsChecked
    $needsCaution = (Find "TweakCautionToggle").IsChecked

    if (-not $name) {
        Show-ThemedDialog "Please enter a tweak name." "Missing name" "OK" "Warning"
        return
    }
    if (-not $applyPath) {
        Show-ThemedDialog "Please select an Apply.ps1 file." "Missing file" "OK" "Warning"
        return
    }

    $folderName = $name -replace '\s+', '_'
    $destDir    = Join-Path $tweaksFolder $folderName

    if (Test-Path $destDir) {
        $confirm = Show-ThemedDialog "A tweak named '$name' already exists. Overwrite?" "Already exists" "YesNo" "Warning"
        if ($confirm -ne "Yes") { return }
    }

    try {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        Copy-Item -Path $applyPath -Destination (Join-Path $destDir "Apply.ps1") -Force

        $revertPath = (Find "TweakRevertPath").Text.Trim()
        if ($revertPath) {
            Copy-Item -Path $revertPath -Destination (Join-Path $destDir "Revert.ps1") -Force
        }
        if ($desc -or $group -or $needsAdmin -or $needsCaution) {
            $tweakJson = @{}
            if ($group) { $tweakJson.group = $group }
            if ($desc)  { $tweakJson.description = $desc }
            if ($needsAdmin) { $tweakJson.requiresAdmin = $true }
            if ($needsCaution) { $tweakJson.caution = $true }
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
        (Find "TweakApplyPlaceholder").Visibility    = "Visible"
        (Find "TweakRevertPlaceholder").Visibility   = "Visible"
        (Find "TweakGroupPlaceholder").Visibility    = "Visible"
        (Find "TweakRequiresAdminToggle").IsChecked  = $false
        (Find "TweakCautionToggle").IsChecked        = $false
        (Find "TweakCreatorPanel").Visibility        = "Collapsed"

        $footerStatus.Text = "Scy - Tweak '$name' created"
    } catch {
        Show-ThemedDialog "Failed to create tweak:`n$_" "Error" "OK" "Error"
    }
})

# ── Elevated execution helper ────────────────────────────────────
function Invoke-TweakElevated {
    param([string]$ScriptPath)
    $proc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" `
        -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "Elevated script exited with code $($proc.ExitCode)"
    }
}

# ── Apply button ─────────────────────────────────────────────────
(Find "BtnApplyTweaks").Add_Click({
    $applied = 0
    $failed = @()
    foreach ($key in $tweakCheckboxes.Keys) {
        $row = $tweakCheckboxes[$key]
        if ($row.CheckBox.IsChecked) {
            try {
                if ($row.RequiresAdmin) {
                    Invoke-TweakElevated $row.ApplyScript
                } else {
                    & $row.ApplyScript -ErrorAction Stop *>&1 | ForEach-Object {
                        if ($_ -is [System.Management.Automation.ErrorRecord]) { throw $_ }
                    }
                }
                $applied++
            } catch {
                $failed += "$($row.DisplayName): $_"
            }
        }
    }
    if ($applied -eq 0 -and $failed.Count -eq 0) {
        Show-ThemedDialog "No tweaks selected." "Info" "OK" "Information"
    } elseif ($failed.Count -gt 0) {
        $msg = if ($applied -gt 0) { "Applied $applied tweak(s).`n`n" } else { "" }
        $msg += "Failed ($($failed.Count)):`n" + ($failed -join "`n")
        Show-ThemedDialog $msg "Tweak errors" "OK" "Warning"
    } else {
        Show-ThemedDialog "Applied $applied tweak(s) successfully!" "Done" "OK" "Information"
    }
})

# ── Revert button ────────────────────────────────────────────────
(Find "BtnRevertTweaks").Add_Click({
    $reverted = 0
    $failed = @()
    foreach ($key in $tweakCheckboxes.Keys) {
        $row = $tweakCheckboxes[$key]
        if ($row.CheckBox.IsChecked) {
            if (Test-Path $row.RevertScript) {
                try {
                    if ($row.RequiresAdmin) {
                        Invoke-TweakElevated $row.RevertScript
                    } else {
                        & $row.RevertScript -ErrorAction Stop *>&1 | ForEach-Object {
                            if ($_ -is [System.Management.Automation.ErrorRecord]) { throw $_ }
                        }
                    }
                    $row.CheckBox.IsChecked = $false
                    $reverted++
                } catch {
                    $failed += "$($row.DisplayName): $_"
                }
            } else {
                Show-ThemedDialog "'$($row.DisplayName)' has no Revert.ps1." "No revert available" "OK" "Warning"
            }
        }
    }
    if ($reverted -eq 0 -and $failed.Count -eq 0) {
        Show-ThemedDialog "No tweaks selected to revert." "Info" "OK" "Information"
    } elseif ($failed.Count -gt 0) {
        $msg = if ($reverted -gt 0) { "Reverted $reverted tweak(s).`n`n" } else { "" }
        $msg += "Failed ($($failed.Count)):`n" + ($failed -join "`n")
        Show-ThemedDialog $msg "Revert errors" "OK" "Warning"
    } else {
        Show-ThemedDialog "Reverted $reverted tweak(s)." "Done" "OK" "Information"
    }
})
