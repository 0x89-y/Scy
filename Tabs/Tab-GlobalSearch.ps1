# ══════════════════════════════════════════════════════════════════
#  GLOBAL SEARCH - Searches across all tabs and navigates to results
# ══════════════════════════════════════════════════════════════════

$globalSearchBox         = Find "GlobalSearchBox"
$globalSearchPlaceholder = Find "GlobalSearchPlaceholder"
$globalSearchPopup       = Find "GlobalSearchPopup"
$globalSearchResults     = Find "GlobalSearchResults"
$globalSearchEmpty       = Find "GlobalSearchEmpty"
$mainTabControl          = Find "MainTabControl"

# ── Ctrl+K shortcut to focus global search ─────────────────────
$window.Add_PreviewKeyDown({
    param($s, $e)
    if ($e.Key -eq "K" -and [System.Windows.Input.Keyboard]::Modifiers -eq "Control") {
        $globalSearchBox.Focus()
        $globalSearchBox.SelectAll()
        $e.Handled = $true
    }
    # Escape closes the popup and clears focus
    if ($e.Key -eq "Escape" -and $globalSearchPopup.IsOpen) {
        $globalSearchPopup.IsOpen = $false
        $globalSearchBox.Text = ""
        $e.Handled = $true
    }
})

# ── Build the searchable index ─────────────────────────────────
# Each entry: @{ Name; Description; Category; TabIndex; SubNavIndex; Action }
# Action is an optional scriptblock for extra navigation steps

function Build-GlobalSearchIndex {
    $items = [System.Collections.Generic.List[hashtable]]::new()

    # -- Tab-level navigation items --
    $items.Add(@{ Name = "Packages";  Description = "Search, install, update & uninstall packages";   Category = "Tabs"; TabIndex = 0; SubNavIndex = $null })
    $items.Add(@{ Name = "Updates";   Description = "Check for package updates";                      Category = "Packages"; TabIndex = 0; SubNavIndex = 0 })
    $items.Add(@{ Name = "Search & Install"; Description = "Search winget packages and install";      Category = "Packages"; TabIndex = 0; SubNavIndex = 1 })
    $items.Add(@{ Name = "Quick Install";    Description = "Quick install from saved packages";       Category = "Packages"; TabIndex = 0; SubNavIndex = 2 })
    $items.Add(@{ Name = "Local Installers"; Description = "Scan and run local installer files";      Category = "Packages"; TabIndex = 0; SubNavIndex = 3 })
    $items.Add(@{ Name = "Uninstall";        Description = "Remove installed packages";               Category = "Packages"; TabIndex = 0; SubNavIndex = 4 })

    $items.Add(@{ Name = "Tweaks";    Description = "Apply and manage system tweaks";                 Category = "Tabs"; TabIndex = 1; SubNavIndex = $null })

    $items.Add(@{ Name = "System";    Description = "System info, cleanup, battery & firmware";       Category = "Tabs"; TabIndex = 2; SubNavIndex = $null })
    $items.Add(@{ Name = "System Info";     Description = "View hardware and OS information";         Category = "System"; TabIndex = 2; SubNavIndex = 0 })
    $items.Add(@{ Name = "Cleanup";         Description = "Clean temp files and free disk space";     Category = "System"; TabIndex = 2; SubNavIndex = 1 })
    $items.Add(@{ Name = "Battery";         Description = "Battery health and power report";          Category = "System"; TabIndex = 2; SubNavIndex = 2 })
    $items.Add(@{ Name = "Firmware";        Description = "BIOS and firmware information";            Category = "System"; TabIndex = 2; SubNavIndex = 3 })
    $items.Add(@{ Name = "SFC / DISM";      Description = "System file checker and DISM repair";      Category = "System"; TabIndex = 2; SubNavIndex = 4 })

    $items.Add(@{ Name = "Bookmarks"; Description = "Shortcuts and registry bookmarks";               Category = "Tabs"; TabIndex = 3; SubNavIndex = $null })
    $items.Add(@{ Name = "Shortcuts";       Description = "Desktop and app shortcuts";                Category = "Bookmarks"; TabIndex = 3; SubNavIndex = 0 })
    $items.Add(@{ Name = "Registry Bookmarks"; Description = "Saved registry key bookmarks";          Category = "Bookmarks"; TabIndex = 3; SubNavIndex = 1 })

    $items.Add(@{ Name = "Network";   Description = "Diagnostics, Wi-Fi, hosts, DNS & SSH";           Category = "Tabs"; TabIndex = 4; SubNavIndex = $null })
    $items.Add(@{ Name = "Network Diagnostics"; Description = "Ping, traceroute, speed test & NSLookup"; Category = "Network"; TabIndex = 4; SubNavIndex = 0 })
    $items.Add(@{ Name = "NSLookup";          Description = "DNS record lookup for domains";           Category = "Network"; TabIndex = 4; SubNavIndex = 0 })
    $items.Add(@{ Name = "Wi-Fi";           Description = "Wi-Fi profiles and passwords";             Category = "Network"; TabIndex = 4; SubNavIndex = 1 })
    $items.Add(@{ Name = "Hosts File";      Description = "Edit the system hosts file";               Category = "Network"; TabIndex = 4; SubNavIndex = 2 })
    $items.Add(@{ Name = "DNS";             Description = "Change DNS servers";                       Category = "Network"; TabIndex = 4; SubNavIndex = 3 })
    $items.Add(@{ Name = "SSH";             Description = "SSH key management";                       Category = "Network"; TabIndex = 4; SubNavIndex = 4 })

    $items.Add(@{ Name = "Active Directory"; Description = "AD users, groups, computers, OUs & domain";       Category = "Tabs"; TabIndex = 5; SubNavIndex = $null })
    $items.Add(@{ Name = "AD Users";         Description = "Look up users by SAM, UPN, or display name";    Category = "Active Directory"; TabIndex = 5; SubNavIndex = 0 })
    $items.Add(@{ Name = "AD Groups";        Description = "Look up groups and list members";                Category = "Active Directory"; TabIndex = 5; SubNavIndex = 1 })
    $items.Add(@{ Name = "AD Computers";     Description = "Look up computer accounts";                      Category = "Active Directory"; TabIndex = 5; SubNavIndex = 2 })
    $items.Add(@{ Name = "AD OUs";           Description = "Browse organizational units";                    Category = "Active Directory"; TabIndex = 5; SubNavIndex = 3 })
    $items.Add(@{ Name = "Domain Info";      Description = "Domain, forest, DCs, FSMO, whoami";             Category = "Active Directory"; TabIndex = 5; SubNavIndex = 4 })

    $items.Add(@{ Name = "Tools";     Description = "QR code, notes, export, hashing & password generator"; Category = "Tabs"; TabIndex = 6; SubNavIndex = $null })
    $items.Add(@{ Name = "QR Code";         Description = "Generate QR codes";                        Category = "Tools"; TabIndex = 6; SubNavIndex = 0 })
    $items.Add(@{ Name = "Notes";           Description = "Quick notes and scratchpad";               Category = "Tools"; TabIndex = 6; SubNavIndex = 1 })
    $items.Add(@{ Name = "Export";          Description = "Export system report";                      Category = "Tools"; TabIndex = 6; SubNavIndex = 2 })
    $items.Add(@{ Name = "File Hashing";      Description = "MD5/SHA1/SHA256 hashes, compare & verify";        Category = "Tools"; TabIndex = 6; SubNavIndex = 3 })
    $items.Add(@{ Name = "Password Generator"; Description = "Generate secure passwords with custom rules";     Category = "Tools"; TabIndex = 6; SubNavIndex = 4 })

    $items.Add(@{ Name = "Settings";  Description = "App settings, themes & backup";                  Category = "Tabs"; TabIndex = 7; SubNavIndex = $null })
    $items.Add(@{ Name = "General Settings";    Description = "General app preferences";              Category = "Settings"; TabIndex = 7; SubNavIndex = 0 })
    $items.Add(@{ Name = "Appearance";          Description = "Theme and color settings";             Category = "Settings"; TabIndex = 7; SubNavIndex = 1 })
    $items.Add(@{ Name = "Groups";              Description = "Manage quick install groups";          Category = "Settings"; TabIndex = 7; SubNavIndex = 2 })
    $items.Add(@{ Name = "Backup & Restore";    Description = "Backup and restore settings";         Category = "Settings"; TabIndex = 7; SubNavIndex = 3 })
    $items.Add(@{ Name = "Sidebar Tabs";        Description = "Show tabs as a vertical left rail (experimental)"; Category = "Settings"; TabIndex = 7; SubNavIndex = 0 })

    # -- Curated Quick Install apps (visible only) --
    if ($script:curatedApps) {
        foreach ($c in $script:curatedApps) {
            if ($c.Id -in $script:hiddenCuratedApps) { continue }
            if ($c.Category -in $script:hiddenDefaultInstallCategories) { continue }
            $items.Add(@{
                Name        = $c.Name
                Description = "Quick Install - " + $c.Category
                Category    = "Quick Install"
                TabIndex    = 0
                SubNavIndex = 2
            })
        }
    }

    # -- Tweaks from the Tweaks folder --
    $tweaksDir = Join-Path $PSScriptRoot "..\Tweaks"
    if (Test-Path $tweaksDir) {
        $tweakDirs = Get-ChildItem -Path $tweaksDir -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $tweakDirs) {
            $applyScript = Join-Path $dir.FullName "Apply.ps1"
            if (-not (Test-Path $applyScript)) { continue }
            $displayName = $dir.Name -replace '_', ' '
            $desc = $null
            $jsonFile = Join-Path $dir.FullName "tweak.json"
            if (Test-Path $jsonFile) {
                try {
                    $meta = Get-Content $jsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($meta.description) { $desc = $meta.description }
                } catch {}
            }
            $items.Add(@{
                Name        = $displayName
                Description = if ($desc) { $desc } else { "Tweak" }
                Category    = "Tweaks"
                TabIndex    = 1
                SubNavIndex = $null
            })
        }
    }

    # Filter out entries that belong to hidden tabs
    if ($script:hiddenTabs -and $script:hiddenTabs.Count -gt 0 -and $mainTabControl) {
        $filtered = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($it in $items) {
            $idx = $it.TabIndex
            if ($null -ne $idx -and $idx -ge 0 -and $idx -lt $mainTabControl.Items.Count) {
                $tabHeader = [string]$mainTabControl.Items[$idx].Header
                if ($tabHeader -ne "Settings" -and ($script:hiddenTabs -contains $tabHeader)) { continue }
            }
            $filtered.Add($it) | Out-Null
        }
        return $filtered
    }

    return $items
}

$script:globalSearchIndex = Build-GlobalSearchIndex

# ── Rebuild index (called after tweaks are added/removed) ──────
function Update-GlobalSearchIndex {
    $script:globalSearchIndex = Build-GlobalSearchIndex
}

# ── Navigate to a search result ────────────────────────────────
function Navigate-ToResult {
    param([hashtable]$Item)

    $mainTabControl.SelectedIndex = $Item.TabIndex

    # Give the UI a moment to switch tabs, then set sub-nav
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

    if ($null -ne $Item.SubNavIndex) {
        switch ($Item.TabIndex) {
            0 { Set-PkgSubNav       $Item.SubNavIndex }
            2 { Set-SystemSubNav    $Item.SubNavIndex }
            3 { Set-BookmarksSubNav $Item.SubNavIndex }
            4 { Set-NetSubNav       $Item.SubNavIndex }
            5 { Set-AdSubNav        $Item.SubNavIndex }
            6 { Set-ToolsSubNav     $Item.SubNavIndex }
            7 { Set-SettingsSubNav  $Item.SubNavIndex }
        }
    }

    # If it's a tweak, type the name into the tweak search box
    if ($Item.Category -eq "Tweaks" -and $Item.TabIndex -eq 1) {
        $tweakSearch = Find "TweakSearchBox"
        if ($tweakSearch) {
            $tweakSearch.Text = $Item.Name
        }
    }
}

# ── Build a result row UI element ──────────────────────────────
function New-SearchResultRow {
    param([hashtable]$Item)

    $row = New-Object System.Windows.Controls.Border
    $row.Padding         = [System.Windows.Thickness]::new(10, 7, 10, 7)
    $row.Margin          = [System.Windows.Thickness]::new(0, 1, 0, 1)
    $row.CornerRadius    = [System.Windows.CornerRadius]::new(4)
    $row.Cursor          = [System.Windows.Input.Cursors]::Hand
    $row.Background      = [System.Windows.Media.Brushes]::Transparent

    $grid = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition
    $c0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    $c1.Width = [System.Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($c0)
    $grid.ColumnDefinitions.Add($c1)

    $stack = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($stack, 0)

    $nameBlock            = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text       = $Item.Name
    $nameBlock.FontSize   = 12
    $nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
    $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
    $stack.Children.Add($nameBlock) | Out-Null

    if ($Item.Description) {
        $descBlock              = New-Object System.Windows.Controls.TextBlock
        $descBlock.Text         = $Item.Description
        $descBlock.FontSize     = 10
        $descBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
        $descBlock.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $stack.Children.Add($descBlock) | Out-Null
    }

    $badge              = New-Object System.Windows.Controls.TextBlock
    $badge.Text         = $Item.Category
    $badge.FontSize     = 10
    $badge.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    $badge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.Grid]::SetColumn($badge, 1)

    $grid.Children.Add($stack) | Out-Null
    $grid.Children.Add($badge) | Out-Null
    $row.Child = $grid

    # Hover effect
    $row.Add_MouseEnter({
        param($s, $e)
        $s.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "HoverSurfaceBrush")
    })
    $row.Add_MouseLeave({
        param($s, $e)
        $s.Background = [System.Windows.Media.Brushes]::Transparent
    })

    # Click → navigate
    $row.Tag = $Item
    $row.Add_MouseLeftButtonUp({
        param($s, $e)
        $globalSearchPopup.IsOpen = $false
        $globalSearchBox.Text = ""
        Navigate-ToResult $s.Tag
    })

    return $row
}

# ── Search handler ─────────────────────────────────────────────
$globalSearchBox.Add_TextChanged({
    $query = $globalSearchBox.Text.Trim().ToLower()
    $globalSearchPlaceholder.Visibility = if ($query) { "Collapsed" } else { "Visible" }

    if (-not $query -or $query.Length -lt 1) {
        $globalSearchPopup.IsOpen = $false
        return
    }

    $globalSearchResults.Children.Clear()

    $keywords = $query -split '\s+'
    $matched  = @()

    foreach ($item in $script:globalSearchIndex) {
        $nameL = $item.Name.ToLower()
        $descL = if ($item.Description) { $item.Description.ToLower() } else { "" }
        $catL  = $item.Category.ToLower()

        $allMatch = $true
        foreach ($kw in $keywords) {
            if (-not ($nameL.Contains($kw) -or $descL.Contains($kw) -or $catL.Contains($kw))) {
                $allMatch = $false
                break
            }
        }

        if ($allMatch) { $matched += $item }
    }

    # Sort: exact name prefix first, then by category, then by name
    $matched = $matched | Sort-Object @{Expression={
        if ($_.Name.ToLower().StartsWith($query)) { 0 } else { 1 }
    }}, Category, Name

    # Limit to 15 results
    $matched = $matched | Select-Object -First 15

    if ($matched.Count -eq 0) {
        $globalSearchEmpty.Visibility = "Visible"
    } else {
        $globalSearchEmpty.Visibility = "Collapsed"
        $lastCategory = ""
        foreach ($item in $matched) {
            if ($item.Category -ne $lastCategory) {
                $lastCategory = $item.Category
                $catHeader              = New-Object System.Windows.Controls.TextBlock
                $catHeader.Text         = $item.Category.ToUpper()
                $catHeader.FontSize     = 9
                $catHeader.FontWeight   = [System.Windows.FontWeights]::Bold
                $catHeader.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                $catHeader.Margin       = [System.Windows.Thickness]::new(10, 8, 0, 2)
                $globalSearchResults.Children.Add($catHeader) | Out-Null
            }
            $row = New-SearchResultRow $item
            $globalSearchResults.Children.Add($row) | Out-Null
        }
    }

    $globalSearchPopup.IsOpen = $true
})

# Close popup when search box loses focus
$globalSearchBox.Add_LostFocus({
    # Small delay to allow click events on results to fire
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $timer.Tag = $globalSearchPopup
    $timer.Add_Tick({
        param($s, $e)
        $s.Stop()
        if (-not $globalSearchBox.IsFocused) {
            $globalSearchPopup.IsOpen = $false
        }
    })
    $timer.Start()
})
