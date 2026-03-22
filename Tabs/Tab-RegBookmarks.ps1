# ── Registry Bookmarks Tab ──────────────────────────────────────

# ── Default Bookmarks Definition ──────────────────────────────
$script:defaultRegBookmarks = @()

$script:defaultRegBookmarkGroups = @("Custom")

# ── Groups ─────────────────────────────────────────────────────
$script:regBookmarks = [System.Collections.Generic.List[hashtable]]::new()
$script:regBookmarkSectionElements = @{}

function Get-AllRegBookmarkGroups {
    $all = [System.Collections.Generic.List[string]]::new()
    foreach ($g in $script:defaultRegBookmarkGroups) { $all.Add($g) }
    foreach ($g in $script:customRegBookmarkGroups) {
        if ($g -notin $script:defaultRegBookmarkGroups) { $all.Add($g) }
    }
    return @($all)
}

function Refresh-RegBookmarkGroupBox {
    $groupBox = Find "RegBookmarkGroupBox"
    $prev = $groupBox.SelectedItem
    $groupBox.Items.Clear()
    $allGroups = Get-AllRegBookmarkGroups
    foreach ($g in $allGroups) { $groupBox.Items.Add($g) | Out-Null }
    $groupBox.Items.Add("+ New group...") | Out-Null
    if ($prev -and $allGroups -contains $prev) {
        $groupBox.SelectedItem = $prev
    } else {
        $idx = $allGroups.IndexOf("Custom")
        $groupBox.SelectedIndex = if ($idx -ge 0) { $idx } else { 0 }
    }
}

# ── Open Regedit at a specific key ──────────────────────────────
function Open-RegEdit {
    param([string]$KeyPath)

    # Expand short hive names to full names that regedit expects
    $fullPath = $KeyPath
    if ($fullPath -match '^HKCU\\') { $fullPath = $fullPath -replace '^HKCU\\', 'HKEY_CURRENT_USER\' }
    elseif ($fullPath -match '^HKLM\\') { $fullPath = $fullPath -replace '^HKLM\\', 'HKEY_LOCAL_MACHINE\' }
    elseif ($fullPath -match '^HKCR\\?') { $fullPath = $fullPath -replace '^HKCR\\?', 'HKEY_CLASSES_ROOT\' }
    elseif ($fullPath -match '^HKU\\')  { $fullPath = $fullPath -replace '^HKU\\', 'HKEY_USERS\' }
    elseif ($fullPath -eq 'HKCR') { $fullPath = 'HKEY_CLASSES_ROOT' }

    # Set regedit's LastKey so it opens at the right location
    try {
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit"
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
        Set-ItemProperty -Path $regPath -Name "LastKey" -Value "Computer\$fullPath" -Type String

        # Kill any running regedit so the new one picks up LastKey
        $existing = Get-Process regedit -ErrorAction SilentlyContinue
        if ($existing) {
            $existing | Stop-Process -Force
            Start-Sleep -Milliseconds 300
        }

        Start-Process regedit.exe
        $footerStatus.Text = "Scy - Opened Registry: $KeyPath"
    } catch {
        Show-ThemedDialog "Could not open Registry Editor:`n$_" "Error" "OK" "Error"
    }
}

# ── Initialize ──────────────────────────────────────────────────
function Initialize-RegBookmarks {
    $script:regBookmarks.Clear()

    $savedBookmarks = if ($script:settings.RegBookmarks) { $script:settings.RegBookmarks } else { @() }

    foreach ($saved in $savedBookmarks) {
        $bookmark = @{
            Name      = $saved.Name
            Path      = $saved.Path
            IsDefault = $false
            IsHidden  = [bool]$saved.IsHidden
            Section   = if ($saved.Section) { $saved.Section } else { "Custom" }
        }
        $script:regBookmarks.Add($bookmark)
    }

    Render-RegBookmarks
}

# ── Render ──────────────────────────────────────────────────────
function Render-RegBookmarks {
    $parentPanel = Find "RegBookmarkGroupsPanel"
    $parentPanel.Children.Clear()
    $script:regBookmarkSectionElements = @{}

    $allGroups = Get-AllRegBookmarkGroups

    # Organize bookmarks by section
    $sections = [ordered]@{}
    foreach ($g in $allGroups) { $sections[$g] = @() }
    foreach ($bookmark in $script:regBookmarks) {
        if (-not $bookmark.IsHidden) {
            $section = $bookmark.Section
            if (-not $sections.Contains($section)) { $sections[$section] = @() }
            $sections[$section] += $bookmark
        }
    }

    foreach ($sectionName in $sections.Keys) {
        $border              = New-Object System.Windows.Controls.Border
        $border.Background   = $window.Resources["Surface2Brush"]
        $border.CornerRadius = [System.Windows.CornerRadius]::new(6)
        $border.BorderBrush  = $window.Resources["BorderBrush"]
        $border.BorderThickness = [System.Windows.Thickness]::new(1)
        $border.Padding      = [System.Windows.Thickness]::new(14, 12, 14, 12)
        $border.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 8)

        $stack = New-Object System.Windows.Controls.StackPanel

        $header            = New-Object System.Windows.Controls.TextBlock
        $header.Text       = $sectionName
        $header.FontSize   = 11
        $header.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
        $header.Margin     = [System.Windows.Thickness]::new(0, 0, 0, 8)
        $stack.Children.Add($header) | Out-Null

        $itemsPanel = New-Object System.Windows.Controls.StackPanel
        $stack.Children.Add($itemsPanel) | Out-Null
        $border.Child = $stack

        if ($sections[$sectionName].Count -eq 0) {
            $border.Visibility = [System.Windows.Visibility]::Collapsed
        }

        $script:regBookmarkSectionElements[$sectionName] = @{ Border = $border; Panel = $itemsPanel }

        foreach ($bookmark in $sections[$sectionName]) {
            $row = New-Object System.Windows.Controls.Border
            $row.CornerRadius = [System.Windows.CornerRadius]::new(4)
            $row.Padding      = [System.Windows.Thickness]::new(10, 7, 10, 7)
            $row.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 4)
            $row.Cursor       = [System.Windows.Input.Cursors]::Hand
            $row.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "SurfaceBrush")

            # Hover effect
            $row.Add_MouseEnter({ $this.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "HoverSurfaceBrush") })
            $row.Add_MouseLeave({ $this.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "SurfaceBrush") })

            $grid = New-Object System.Windows.Controls.Grid
            $gc0 = New-Object System.Windows.Controls.ColumnDefinition
            $gc0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $gc1 = New-Object System.Windows.Controls.ColumnDefinition
            $gc1.Width = [System.Windows.GridLength]::Auto
            $grid.ColumnDefinitions.Add($gc0)
            $grid.ColumnDefinitions.Add($gc1)

            # Left side: name and path
            $leftStack = New-Object System.Windows.Controls.StackPanel

            $nameBlock            = New-Object System.Windows.Controls.TextBlock
            $nameBlock.Text       = $bookmark.Name
            $nameBlock.FontSize   = 13
            $nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
            $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
            $leftStack.Children.Add($nameBlock) | Out-Null

            $pathBlock            = New-Object System.Windows.Controls.TextBlock
            $pathBlock.Text       = $bookmark.Path
            $pathBlock.FontSize   = 11
            $pathBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
            $pathBlock.Margin     = [System.Windows.Thickness]::new(0, 2, 0, 0)
            $leftStack.Children.Add($pathBlock) | Out-Null

            [System.Windows.Controls.Grid]::SetColumn($leftStack, 0)
            $grid.Children.Add($leftStack) | Out-Null

            # Right side: open button
            $openBtn         = New-Object System.Windows.Controls.Button
            $openBtn.Content = "Open"
            $openBtn.Style   = $window.Resources["ActionButton"]
            $openBtn.Padding = [System.Windows.Thickness]::new(14, 5, 14, 5)
            $openBtn.FontSize = 12
            $openBtn.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $openBtn.Tag = $bookmark.Path
            $openBtn.Add_Click({
                Open-RegEdit $this.Tag
            }.GetNewClosure())

            [System.Windows.Controls.Grid]::SetColumn($openBtn, 1)
            $grid.Children.Add($openBtn) | Out-Null

            $row.Child = $grid
            $row.Tag = @{ Name = $bookmark.Name; Path = $bookmark.Path; IsDefault = $bookmark.IsDefault }

            # Click on row also opens
            $bookmarkPath = $bookmark.Path
            $row.Add_MouseLeftButtonUp({
                Open-RegEdit $bookmarkPath
            }.GetNewClosure())

            # Right-click context menu
            $bookmarkRef = $bookmark
            $row.Add_MouseRightButtonUp({
                param($sender, $e)
                $bm = $bookmarkRef

                $menu = New-Object System.Windows.Controls.ContextMenu

                # Copy path
                $copyItem = New-Object System.Windows.Controls.MenuItem
                $copyItem.Header = "Copy path"
                $copyItem.Add_Click({
                    [System.Windows.Clipboard]::SetText($bm.Path)
                    $footerStatus.Text = "Scy - Copied: $($bm.Path)"
                }.GetNewClosure())
                $menu.Items.Add($copyItem)

                # Move to group submenu
                $moveMenu = New-Object System.Windows.Controls.MenuItem
                $moveMenu.Header = "Move to"
                foreach ($secName in (Get-AllRegBookmarkGroups)) {
                    $item = New-Object System.Windows.Controls.MenuItem
                    $item.Header = $secName
                    if ($secName -eq $bm.Section) { $item.IsEnabled = $false }
                    $targetSection = $secName
                    $item.Add_Click({
                        $bm.Section = $targetSection
                        Save-RegBookmarksToSettings
                        Render-RegBookmarks
                    }.GetNewClosure())
                    $moveMenu.Items.Add($item)
                }
                $moveMenu.Items.Add((New-Object System.Windows.Controls.Separator))
                $newGroupItem = New-Object System.Windows.Controls.MenuItem
                $newGroupItem.Header = "New group..."
                $newGroupItem.Add_Click({
                    Ensure-VisualBasic; $gName = [Microsoft.VisualBasic.Interaction]::InputBox("Group name:", "New Group", "")
                    if ([string]::IsNullOrWhiteSpace($gName)) { return }
                    $gName = $gName.Trim()
                    if ($gName -notin (Get-AllRegBookmarkGroups)) {
                        $script:customRegBookmarkGroups.Add($gName)
                        Save-Settings
                        Refresh-RegBookmarkGroupBox
                    }
                    $bm.Section = $gName
                    Save-RegBookmarksToSettings
                    Render-RegBookmarks
                }.GetNewClosure())
                $moveMenu.Items.Add($newGroupItem)
                $menu.Items.Add($moveMenu)

                # Hide
                $hideItem = New-Object System.Windows.Controls.MenuItem
                $hideItem.Header = "Hide"
                $hideItem.Add_Click({
                    $bm.IsHidden = $true
                    Save-RegBookmarksToSettings
                    Render-RegBookmarks
                }.GetNewClosure())
                $menu.Items.Add($hideItem)

                # Delete
                $deleteItem = New-Object System.Windows.Controls.MenuItem
                $deleteItem.Header = "Delete"
                $deleteItem.Add_Click({
                    $result = Show-ThemedDialog "Delete bookmark '$($bm.Name)'?" "Confirm Delete" "YesNo" "Question"
                    if ($result -eq "Yes") {
                        $script:regBookmarks.Remove($bm)
                        Save-RegBookmarksToSettings
                        Render-RegBookmarks
                    }
                }.GetNewClosure())
                $menu.Items.Add($deleteItem)

                $menu.PlacementTarget = $sender
                $menu.IsOpen = $true
                $e.Handled = $true
            }.GetNewClosure())

            $itemsPanel.Children.Add($row) | Out-Null
        }

        $parentPanel.Children.Add($border) | Out-Null
    }

    Refresh-RegBookmarkGroupBox
}

# ── Save ─────────────────────────────────────────────────────────
function Save-RegBookmarksToSettings {
    $script:settings.RegBookmarks = @($script:regBookmarks | ForEach-Object {
        @{
            Name      = $_.Name
            Path      = $_.Path
            IsDefault = $_.IsDefault
            IsHidden  = $_.IsHidden
            Section   = $_.Section
        }
    })
    Save-Settings
}

# ── Populate group selector ────────────────────────────────────
Refresh-RegBookmarkGroupBox

# Handle "New group..." selection
(Find "RegBookmarkGroupBox").Add_SelectionChanged({
    if ($this.SelectedItem -eq "+ New group...") {
        Ensure-VisualBasic; $gName = [Microsoft.VisualBasic.Interaction]::InputBox("Group name:", "New Group", "")
        if (-not [string]::IsNullOrWhiteSpace($gName)) {
            $gName = $gName.Trim()
            if ($gName -notin (Get-AllRegBookmarkGroups)) {
                $script:customRegBookmarkGroups.Add($gName)
                Save-Settings
            }
            Refresh-RegBookmarkGroupBox
            (Find "RegBookmarkGroupBox").SelectedItem = $gName
        } else {
            $allGroups = Get-AllRegBookmarkGroups
            $idx = $allGroups.IndexOf("Custom")
            (Find "RegBookmarkGroupBox").SelectedIndex = if ($idx -ge 0) { $idx } else { 0 }
        }
    }
})

# ── UI Event Handlers ──────────────────────────────────────────

# Toggle Add Bookmark panel
(Find "BtnAddRegBookmark").Add_Click({
    $panel = Find "AddRegBookmarkPanel"
    $panel.Visibility = if ($panel.Visibility -eq "Collapsed") {
        [System.Windows.Visibility]::Visible
    } else {
        [System.Windows.Visibility]::Collapsed
    }
})

# Cancel Add Bookmark
(Find "BtnCancelAddRegBookmark").Add_Click({
    (Find "AddRegBookmarkPanel").Visibility = [System.Windows.Visibility]::Collapsed
    (Find "RegBookmarkNameBox").Text = ""
    (Find "RegBookmarkPathBox").Text = ""
    $allGroups = Get-AllRegBookmarkGroups
    $idx = $allGroups.IndexOf("Custom")
    (Find "RegBookmarkGroupBox").SelectedIndex = if ($idx -ge 0) { $idx } else { 0 }
})

# Create bookmark
(Find "BtnCreateRegBookmark").Add_Click({
    $name = (Find "RegBookmarkNameBox").Text.Trim()
    $path = (Find "RegBookmarkPathBox").Text.Trim()

    if ($name -eq "" -or $path -eq "") {
        Show-ThemedDialog "Please enter both a name and registry path." "Missing information" "OK" "Warning"
        return
    }

    # Validate path starts with a known hive
    if ($path -notmatch '^(HKCU|HKLM|HKCR|HKU|HKEY_CURRENT_USER|HKEY_LOCAL_MACHINE|HKEY_CLASSES_ROOT|HKEY_USERS)') {
        Show-ThemedDialog "Registry path must start with a valid hive (HKCU, HKLM, HKCR, HKU)." "Invalid path" "OK" "Warning"
        return
    }

    # Check for duplicate name
    if ($script:regBookmarks | Where-Object { $_.Name -eq $name }) {
        Show-ThemedDialog "A bookmark with this name already exists." "Duplicate name" "OK" "Warning"
        return
    }

    $selectedGroup = (Find "RegBookmarkGroupBox").SelectedItem
    if (-not $selectedGroup -or $selectedGroup -eq "+ New group...") { $selectedGroup = "Custom" }

    $newBookmark = @{
        Name      = $name
        Path      = $path
        IsDefault = $false
        IsHidden  = $false
        Section   = $selectedGroup
    }

    $script:regBookmarks.Add($newBookmark)
    Save-RegBookmarksToSettings
    Render-RegBookmarks

    # Clear form and hide panel
    (Find "RegBookmarkNameBox").Text = ""
    (Find "RegBookmarkPathBox").Text = ""
    $allGroups = Get-AllRegBookmarkGroups
    $idx = $allGroups.IndexOf("Custom")
    (Find "RegBookmarkGroupBox").SelectedIndex = if ($idx -ge 0) { $idx } else { 0 }
    (Find "AddRegBookmarkPanel").Visibility = [System.Windows.Visibility]::Collapsed
})

# Clear all bookmarks
(Find "BtnResetRegBookmarks").Add_Click({
    if ($script:regBookmarks.Count -eq 0) {
        Show-ThemedDialog "No bookmarks to clear." "Info" "OK" "Information"
        return
    }
    $result = Show-ThemedDialog "This will remove ALL bookmarks. Are you sure?" "Confirm Clear" "YesNo" "Warning"
    if ($result -eq "Yes") {
        $script:regBookmarks = [System.Collections.Generic.List[hashtable]]::new()
        Save-RegBookmarksToSettings
        Render-RegBookmarks
    }
})

# Placeholder visibility handlers
(Find "RegBookmarkNameBox").Add_TextChanged({
    (Find "RegBookmarkNamePlaceholder").Visibility = if ($this.Text -eq "") { "Visible" } else { "Collapsed" }
})
(Find "RegBookmarkPathBox").Add_TextChanged({
    (Find "RegBookmarkPathPlaceholder").Visibility = if ($this.Text -eq "") { "Visible" } else { "Collapsed" }
})

# ── Search ──────────────────────────────────────────────────────
$script:regBookmarkSearchClear = Find "RegBookmarkSearchClear"

(Find "RegBookmarkSearchBox").Add_TextChanged({
    $query = $this.Text.Trim()
    (Find "RegBookmarkSearchPlaceholder").Visibility = if ($query -eq "") { "Visible" } else { "Collapsed" }
    $script:regBookmarkSearchClear.Visibility = if ($query -ne "") { "Visible" } else { "Collapsed" }

    foreach ($secName in $script:regBookmarkSectionElements.Keys) {
        $el = $script:regBookmarkSectionElements[$secName]
        $anyVisible = $false
        foreach ($row in $el.Panel.Children) {
            $data = $row.Tag
            $visible = ($query -eq "") -or ($data.Name -like "*$query*") -or ($data.Path -like "*$query*")
            $row.Visibility = if ($visible) { "Visible" } else { "Collapsed" }
            if ($visible) { $anyVisible = $true }
        }
        $el.Border.Visibility = if ($anyVisible) { "Visible" } else { "Collapsed" }
    }
})

$script:regBookmarkSearchClear.Add_Click({
    (Find "RegBookmarkSearchBox").Text = ""
})
