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

# ── Applied state + previous values ──────────────────────────────
# A tweak.json may list the registry values that mean "applied":
#   "check": [ { "path": "HKCU:\\...", "name": "ValueName", "value": 0 } ]
# Scy only reads them (fast, works without admin) to show Applied / Partly applied.
# Before applying, the current values are saved to %APPDATA%\Scy\tweak-backups,
# and Revert puts exactly those back instead of running Revert.ps1 - unless the
# tweak sets "snapshot": false (e.g. it removes apps or switches power plans).
# "restartExplorer": true restarts Explorer after such a restore.
$script:tweakBackupDir = Join-Path $script:dataDir "tweak-backups"

# Current state of one registry value (reads only).
function Get-TweakRegValue {
    param([string]$Path, [string]$Name)
    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $key) { return @{ KeyExisted = $false; ValueExisted = $false } }
    $vn = if ($Name -eq '(Default)') { '' } else { $Name }
    if (@($key.GetValueNames()) -notcontains $vn) { return @{ KeyExisted = $true; ValueExisted = $false } }
    return @{
        KeyExisted   = $true
        ValueExisted = $true
        Value        = $key.GetValue($vn, $null, 'DoNotExpandEnvironmentNames')
        Kind         = [string]$key.GetValueKind($vn)
    }
}

# "Applied", "Partial", "NotApplied", or $null when the tweak has no check.
function Get-TweakState {
    param($Checks)
    $checks = @($Checks | Where-Object { $_ })
    if ($checks.Count -eq 0) { return $null }
    $hits = 0
    foreach ($c in $checks) {
        $v = Get-TweakRegValue -Path $c.path -Name $c.name
        if ($v.ValueExisted -and [string]$v.Value -eq [string]$c.value) { $hits++ }
    }
    if ($hits -eq $checks.Count) { return "Applied" }
    if ($hits -gt 0) { return "Partial" }
    return "NotApplied"
}

function Get-TweakBackupPath {
    param([string]$FolderName)
    Join-Path $script:tweakBackupDir ($FolderName + ".json")
}

# Save the pre-apply values of a tweak's checked registry values. An existing
# backup is kept: it holds the original values, from before the first apply.
# Returns $true when a new backup was written.
function Save-TweakBackup {
    param($Row)
    if (-not $Row.Snapshot -or @($Row.Checks).Count -eq 0) { return $false }
    $file = Get-TweakBackupPath $Row.FolderName
    if (Test-Path -LiteralPath $file) { return $false }
    $entries = foreach ($c in @($Row.Checks)) {
        $v = Get-TweakRegValue -Path $c.path -Name $c.name
        # For a key that doesn't exist yet, remember the nearest one that does:
        # Revert removes the (empty) keys the tweak created, up to that one.
        $existingParent = $null
        if (-not $v.KeyExisted) {
            $existingParent = Split-Path $c.path -Parent
            while ($existingParent -and -not (Test-Path -LiteralPath $existingParent)) { $existingParent = Split-Path $existingParent -Parent }
        }
        [ordered]@{ Path = $c.path; Name = $c.name; KeyExisted = $v.KeyExisted; ValueExisted = $v.ValueExisted
                    Value = $v.Value; Kind = $v.Kind; ExistingParent = $existingParent }
    }
    if (-not (Test-Path -LiteralPath $script:tweakBackupDir)) { New-Item -ItemType Directory -Path $script:tweakBackupDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($file, (ConvertTo-Json @($entries) -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
    return $true
}

function Update-TweakStates {
    foreach ($key in $tweakCheckboxes.Keys) {
        $row = $tweakCheckboxes[$key]
        if (-not $row.StatePill) { continue }
        $state = Get-TweakState $row.Checks
        $row.State = $state
        switch ($state) {
            "Applied" {
                $row.StatePillText.Text = "Applied"
                $row.StatePill.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "SuccessBrush")
                $row.StatePillText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "SuccessBrush")
                $row.StatePill.ToolTip = "This tweak's settings are currently in place"
                $row.StatePill.Visibility = "Visible"
            }
            "Partial" {
                $row.StatePillText.Text = "Partly applied"
                $row.StatePill.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "MutedText")
                $row.StatePillText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                $row.StatePill.ToolTip = "Some of this tweak's settings are in place, others aren't"
                $row.StatePill.Visibility = "Visible"
            }
            default { $row.StatePill.Visibility = "Collapsed" }
        }
    }
}

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
        $adminBadge.ToolTip           = "Needs Scy to be started with 'Run as administrator'"
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

    # State pill (Applied / Partly applied) - filled in by Update-TweakStates
    $statePill                   = New-Object System.Windows.Controls.Border
    $statePill.BorderThickness   = [System.Windows.Thickness]::new(1)
    $statePill.CornerRadius      = [System.Windows.CornerRadius]::new(7)
    $statePill.Padding           = [System.Windows.Thickness]::new(6, 1, 6, 1)
    $statePill.Margin            = [System.Windows.Thickness]::new(8, 0, 0, 0)
    $statePill.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $statePill.Visibility        = "Collapsed"
    $statePillText               = New-Object System.Windows.Controls.TextBlock
    $statePillText.FontSize      = 10
    $statePillText.FontWeight    = [System.Windows.FontWeights]::SemiBold
    $statePill.Child             = $statePillText
    $nameRow.Children.Add($statePill) | Out-Null

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
        Checks          = @(if ($tweakMeta -and $tweakMeta.check) { $tweakMeta.check })
        Snapshot        = -not ($tweakMeta -and $tweakMeta.PSObject.Properties['snapshot'] -and -not $tweakMeta.snapshot)
        RestartExplorer = [bool]($tweakMeta -and $tweakMeta.restartExplorer)
        StatePill       = $statePill
        StatePillText   = $statePillText
        State           = $null
    }
}

# ── Grouping logic ────────────────────────────────────────────────

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
    Update-TweakStates

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

# ── Apply / Revert ───────────────────────────────────────────────
# Tweak scripts run in a background job so slow ones (package removal, Explorer
# restarts) don't freeze the window. Scy never elevates or checks for admin
# itself: a tweak that needs admin (badge "Admin") simply fails with access
# denied when Scy wasn't started as administrator, and is listed separately so
# the user knows to restart Scy with "Run as administrator".
$script:tweaksBusy = $false

function Invoke-SelectedTweaks {
    param([ValidateSet("Apply", "Revert")][string]$Mode)
    if ($script:tweaksBusy) { return }

    $work     = @()
    $noRevert = @()
    foreach ($key in $tweakCheckboxes.Keys) {
        $row = $tweakCheckboxes[$key]
        if (-not $row.CheckBox.IsChecked) { continue }
        $item = @{ Key = $key; Name = $row.DisplayName; Script = $null; Restore = $null
                   BackupFile = (Get-TweakBackupPath $row.FolderName); NewBackup = $false; RestartExplorer = $row.RestartExplorer }

        if ($Mode -eq "Apply") {
            if (-not (Test-Path $row.ApplyScript)) { continue }
            # Remember what was there before, so Revert can put exactly that back
            try { $item.NewBackup = [bool](Save-TweakBackup $row) } catch { Write-ScyLog "Tweak backup failed for $($row.FolderName): $($_.Exception.Message)" "ERROR" }
            $item.Script = $row.ApplyScript
        } elseif ($row.Snapshot -and (Test-Path -LiteralPath $item.BackupFile)) {
            $item.Restore = @(Get-Content -LiteralPath $item.BackupFile -Raw -Encoding UTF8 | ConvertFrom-Json)
        } elseif (Test-Path $row.RevertScript) {
            $item.Script = $row.RevertScript
        } else {
            $noRevert += $row.DisplayName
            continue
        }
        $work += $item
    }

    if ($work.Count -eq 0 -and $noRevert.Count -eq 0) {
        Show-ThemedDialog "No tweaks selected." "Info" "OK" "Information" | Out-Null
        return
    }

    $script:tweaksBusy = $true
    (Find "BtnApplyTweaks").IsEnabled  = $false
    (Find "BtnRevertTweaks").IsEnabled = $false
    $verbIng = if ($Mode -eq "Apply") { "Applying" } else { "Reverting" }
    Set-BusyStatus "$verbIng tweaks..."

    Start-ScyJob `
        -Variables @{ items = $work } `
        -Context   @{ Mode = $Mode; NoRevert = $noRevert; VerbIng = $verbIng } `
        -Work {
            param($emit)
            $restartExplorer = $false
            $results = foreach ($it in $items) {
                & $emit $it.Name
                $err = $null
                try {
                    if ($it.Restore) {
                        # Put back the values saved before the tweak was applied
                        foreach ($e in @($it.Restore)) {
                            $p  = [string]$e.Path
                            $n  = [string]$e.Name
                            $vn = if ($n -eq '(Default)') { '' } else { $n }
                            if ($e.ValueExisted) {
                                if (-not (Test-Path -LiteralPath $p)) { New-Item -Path $p -Force -ErrorAction Stop | Out-Null }
                                $val = $e.Value
                                switch ([string]$e.Kind) { 'Binary' { $val = [byte[]]@($val) } 'MultiString' { $val = [string[]]@($val) } }
                                if ($vn -eq '') { Set-ItemProperty -LiteralPath $p -Name '(default)' -Value $val -ErrorAction Stop }
                                else { New-ItemProperty -LiteralPath $p -Name $n -Value $val -PropertyType ([string]$e.Kind) -Force -ErrorAction Stop | Out-Null }
                            } else {
                                $k = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
                                if ($k -and (@($k.GetValueNames()) -contains $vn)) {
                                    if ($vn -eq '') {
                                        # Remove-ItemProperty can't delete a key's default value; use .NET
                                        $hiveName, $sub = $k.Name.Split('\', 2)
                                        $hive = switch ($hiveName) {
                                            'HKEY_CURRENT_USER'  { [Microsoft.Win32.Registry]::CurrentUser }
                                            'HKEY_LOCAL_MACHINE' { [Microsoft.Win32.Registry]::LocalMachine }
                                            'HKEY_USERS'         { [Microsoft.Win32.Registry]::Users }
                                            'HKEY_CLASSES_ROOT'  { [Microsoft.Win32.Registry]::ClassesRoot }
                                        }
                                        $w = $hive.OpenSubKey($sub, $true)
                                        try { $w.DeleteValue('', $false) } finally { $w.Close() }
                                    } else {
                                        Remove-ItemProperty -LiteralPath $p -Name $n -ErrorAction Stop
                                    }
                                }
                                # Keys the tweak created are removed again once empty, walking
                                # up to the nearest key that existed before the tweak
                                if (-not $e.KeyExisted) {
                                    $cur = $p
                                    while ($cur -and $cur -ne [string]$e.ExistingParent) {
                                        $k = Get-Item -LiteralPath $cur -ErrorAction SilentlyContinue
                                        if (-not $k -or $k.ValueCount -gt 0 -or $k.SubKeyCount -gt 0) { break }
                                        Remove-Item -LiteralPath $cur -ErrorAction Stop
                                        $cur = Split-Path $cur -Parent
                                    }
                                }
                            }
                        }
                        if ($it.RestartExplorer) { $restartExplorer = $true }
                    } else {
                        # *>&1 turns non-terminating errors into records we can fail on
                        & $it.Script *>&1 | ForEach-Object {
                            if ($_ -is [System.Management.Automation.ErrorRecord]) { throw $_ }
                        }
                    }
                } catch { $err = $_ }
                @{ Key = $it.Key; Name = $it.Name; Error = $err; BackupFile = $it.BackupFile; NewBackup = $it.NewBackup; Restored = [bool]$it.Restore }
            }
            # Restored Explorer settings only take effect after a restart (Windows relaunches it)
            if ($restartExplorer) { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue }
            return ,@($results)
        } `
        -OnLine {
            param($name, $ctx)
            $statusIndicator.Text = "$($ctx.VerbIng) $name..."
            $footerStatus.Text    = "Scy - $($ctx.VerbIng) $name..."
        } `
        -OnComplete {
            param($results, $err, $ctx)
            $script:tweaksBusy = $false
            Set-ReadyStatus
            if ($err) {
                Update-TweakFooterCounts
                Show-ThemedDialog "Running the tweaks failed:`n$($err.Exception.Message)" "Tweak errors" "OK" "Error" | Out-Null
                return
            }
            $done = 0; $failed = @(); $needAdmin = @()
            foreach ($r in @($results)) {
                if (-not $r.Error) {
                    $done++
                    if ($ctx.Mode -eq "Revert" -and $tweakCheckboxes.Contains($r.Key)) { $tweakCheckboxes[$r.Key].CheckBox.IsChecked = $false }
                    # Backup used up: the next apply records fresh "before" values
                    if ($r.Restored) { Remove-Item -LiteralPath $r.BackupFile -Force -ErrorAction SilentlyContinue }
                } else {
                    # A failed apply most likely changed nothing - don't keep a backup of it
                    if ($r.NewBackup) { Remove-Item -LiteralPath $r.BackupFile -Force -ErrorAction SilentlyContinue }
                    if (Test-ScyAccessDenied $r.Error) { $needAdmin += $r.Name }
                    else { $failed += "$($r.Name): $($r.Error)" }
                }
            }
            Update-TweakFooterCounts
            Update-TweakStates
            Show-TweakSummary -Mode $ctx.Mode -Done $done -Failed $failed -NeedAdmin $needAdmin -NoRevert $ctx.NoRevert
        } | Out-Null
}

function Show-TweakSummary {
    param([string]$Mode, [int]$Done, [string[]]$Failed = @(), [string[]]$NeedAdmin = @(), [string[]]$NoRevert = @())
    $failed = @($Failed); $needAdmin = @($NeedAdmin); $noRevert = @($NoRevert); $done = $Done
    $verb = if ($Mode -eq "Apply") { "Applied" } else { "Reverted" }

    $parts = @()
    if ($done -gt 0)           { $parts += "$verb $done tweak(s)." }
    if ($needAdmin.Count -gt 0) {
        $parts += "Needs administrator rights ($($needAdmin.Count)):`n" + (($needAdmin | ForEach-Object { "  - $_" }) -join "`n") +
                  "`nClose Scy and start it again with 'Run as administrator', then try these again."
    }
    if ($failed.Count -gt 0)   { $parts += "Failed ($($failed.Count)):`n" + ($failed -join "`n") }
    if ($noRevert.Count -gt 0) { $parts += "No Revert.ps1, skipped ($($noRevert.Count)):`n" + (($noRevert | ForEach-Object { "  - $_" }) -join "`n") }

    $ok = ($needAdmin.Count -eq 0 -and $failed.Count -eq 0 -and $noRevert.Count -eq 0)
    $title = if ($ok) { "Done" } elseif ($needAdmin.Count -gt 0 -and $failed.Count -eq 0) { "Administrator rights required" } else { "Tweak errors" }
    Show-ThemedDialog ($parts -join "`n`n") $title "OK" $(if ($ok) { "Information" } else { "Warning" }) | Out-Null
}

(Find "BtnApplyTweaks").Add_Click({  Invoke-SelectedTweaks -Mode Apply })
(Find "BtnRevertTweaks").Add_Click({ Invoke-SelectedTweaks -Mode Revert })
