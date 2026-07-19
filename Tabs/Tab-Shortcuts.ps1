  # ── Bookmarks rail (replaces the old sub-nav pills) ───────────────
  $bookmarksSectionShortcuts = Find "BookmarksSection_Shortcuts"
  $bookmarksSectionRegistry  = Find "BookmarksSection_Registry"

  $script:bookmarksSections   = @($bookmarksSectionShortcuts, $bookmarksSectionRegistry)
  $script:bookmarksNavLabels  = @("Shortcuts", "Registry")

  # Two-level rail: both sections always listed; the selected one expands to show
  # "All" + its groups, indented underneath.
  $script:shortcutGroupFilter = "All"
  $script:regGroupFilter      = "All"

  function Build-BookmarksRail {
      $panel = Find "BookmarksRail"
      if (-not $panel) { return }
      # Shortcut groups/data are defined further down this file, so an early call
      # (from the initial Set-BookmarksSubNav below) must no-op. Render-Shortcuts
      # rebuilds the rail once the data is loaded.
      if (-not (Get-Command Get-AllShortcutGroups -ErrorAction SilentlyContinue)) { return }
      $panel.Children.Clear()

      # ── Shortcuts ──
      $panel.Children.Add(
          (New-RailEntry -Label "Shortcuts" -IsSection $true `
                         -IsActive ($script:bookmarksSubNavIndex -eq 0 -and $script:shortcutGroupFilter -eq "All") `
                         -OnClick { Set-BookmarksSubNav 0; Set-ShortcutGroupFilter "All" })) | Out-Null

      if ($script:bookmarksSubNavIndex -eq 0) {
          foreach ($g in (Get-ShortcutGroupCounts).Keys) {
              $gName = $g
              $panel.Children.Add(
                  (New-RailEntry -Label $gName -Indent 1 -Count (Get-ShortcutGroupCounts)[$gName] `
                                 -IsActive ($script:shortcutGroupFilter -eq $gName) `
                                 -OnClick ({ Set-ShortcutGroupFilter $gName }).GetNewClosure())) | Out-Null
          }
      }

      # ── Registry ──
      $panel.Children.Add(
          (New-RailEntry -Label "Registry" -IsSection $true `
                         -IsActive ($script:bookmarksSubNavIndex -eq 1 -and $script:regGroupFilter -eq "All") `
                         -OnClick { Set-BookmarksSubNav 1; Set-RegGroupFilter "All" })) | Out-Null

      if ($script:bookmarksSubNavIndex -eq 1 -and (Get-Command Get-RegGroupCounts -ErrorAction SilentlyContinue)) {
          foreach ($g in (Get-RegGroupCounts).Keys) {
              $gName = $g
              $panel.Children.Add(
                  (New-RailEntry -Label $gName -Indent 1 -Count (Get-RegGroupCounts)[$gName] `
                                 -IsActive ($script:regGroupFilter -eq $gName) `
                                 -OnClick ({ Set-RegGroupFilter $gName }).GetNewClosure())) | Out-Null
          }
      }
  }

  # Shortcut counts per group (hidden shortcuts excluded)
  function Get-ShortcutGroupCounts {
      $counts = [ordered]@{}
      foreach ($g in (Get-AllShortcutGroups)) { $counts[$g] = 0 }
      foreach ($s in $script:shortcuts) {
          if ($s.IsHidden) { continue }
          $sec = $s.Section
          if (-not $counts.Contains($sec)) { $counts[$sec] = 0 }
          $counts[$sec] = $counts[$sec] + 1
      }
      return $counts
  }

  function Set-ShortcutGroupFilter {
      param([string]$Group)
      $script:shortcutGroupFilter = $Group
      Build-BookmarksRail
      if (Get-Command Apply-ShortcutFilter -ErrorAction SilentlyContinue) { Apply-ShortcutFilter }
  }

  function Set-BookmarksSubNav {
      param([int]$Index)
      if ($Index -lt 0 -or $Index -ge $script:bookmarksSections.Count) { $Index = 0 }
      $script:bookmarksSubNavIndex = $Index
      for ($i = 0; $i -lt $script:bookmarksSections.Count; $i++) {
          $script:bookmarksSections[$i].Visibility = if ($i -eq $Index) { "Visible" } else { "Collapsed" }
      }
      Build-BookmarksRail
  }

  $script:bookmarksSubNavIndex = 0
  Set-BookmarksSubNav 0

  # ── Shortcuts Tab ────────────────────────────────────────────────

  # ── Default Shortcuts Definition ───────────────────────────────
  $script:defaultShortcuts = @(
      @{ Name = "Advanced system";         Command = "sysdm.cpl";                        Arguments = @(); Section = "System";      RequiresAdmin = $false },
      @{ Name = "Environment variables";   Command = "SystemPropertiesAdvanced.exe";     Arguments = @(); Section = "System";      RequiresAdmin = $false },
      @{ Name = "Performance options";     Command = "SystemPropertiesPerformance.exe";  Arguments = @(); Section = "System";      RequiresAdmin = $false },
      @{ Name = "Device manager";          Command = "devmgmt.msc";                      Arguments = @(); Section = "System";      RequiresAdmin = $false },
      @{ Name = "System configuration";    Command = "msconfig";                         Arguments = @(); Section = "System";      RequiresAdmin = $true  },
      @{ Name = "Disk management";         Command = "diskmgmt.msc";                     Arguments = @(); Section = "Disk";        RequiresAdmin = $true  },
      @{ Name = "Disk cleanup";            Command = "cleanmgr";                         Arguments = @(); Section = "Disk";        RequiresAdmin = $false },
      @{ Name = "Optional features";       Command = "optionalfeatures";                 Arguments = @(); Section = "Disk";        RequiresAdmin = $true  },
      @{ Name = "Network connections";     Command = "ncpa.cpl";                         Arguments = @(); Section = "Network";     RequiresAdmin = $false },
      @{ Name = "Network & sharing center"; Command = "control.exe"; Arguments = @("/name", "Microsoft.NetworkAndSharingCenter"); Section = "Network"; RequiresAdmin = $false },
      @{ Name = "Hosts file";              Command = "HostsFileSpecial";                 Arguments = @(); Section = "Network";     RequiresAdmin = $true  },
      @{ Name = "Internet options";        Command = "inetcpl.cpl";                      Arguments = @(); Section = "Network";     RequiresAdmin = $false },
      @{ Name = "Flush DNS cache";         Command = "FlushDNSSpecial";                  Arguments = @(); Section = "Network";     RequiresAdmin = $false },
      @{ Name = "Credential manager";      Command = "control.exe"; Arguments = @("/name", "Microsoft.CredentialManager"); Section = "Security"; RequiresAdmin = $false },
      @{ Name = "Local security policy";   Command = "secpol.msc";                       Arguments = @(); Section = "Security";    RequiresAdmin = $true  },
      @{ Name = "Group policy editor";     Command = "gpedit.msc";                       Arguments = @(); Section = "Security";    RequiresAdmin = $true  },
      @{ Name = "Startup apps";            Command = "ms-settings:startupapps";          Arguments = @(); Section = "Startup";     RequiresAdmin = $false },
      @{ Name = "Services";               Command = "services.msc";                     Arguments = @(); Section = "Startup";     RequiresAdmin = $false },
      @{ Name = "Task scheduler";          Command = "taskschd.msc";                     Arguments = @(); Section = "Startup";     RequiresAdmin = $false },
      @{ Name = "Sound settings";          Command = "mmsys.cpl";                        Arguments = @(); Section = "Sound";       RequiresAdmin = $false },
      @{ Name = "Color calibration";       Command = "dccw.exe";                         Arguments = @(); Section = "Sound";       RequiresAdmin = $false },
      @{ Name = "DirectX diagnostic";      Command = "dxdiag";                           Arguments = @(); Section = "Diagnostics"; RequiresAdmin = $false },
      @{ Name = "Event viewer";            Command = "eventvwr.msc";                     Arguments = @(); Section = "Diagnostics"; RequiresAdmin = $false },
      @{ Name = "Resource monitor";        Command = "resmon";                           Arguments = @(); Section = "Diagnostics"; RequiresAdmin = $false },
      @{ Name = "Memory diagnostic";       Command = "mdsched";                          Arguments = @(); Section = "Diagnostics"; RequiresAdmin = $true  },
      @{ Name = "Steps Recorder";          Command = "psr.exe";                          Arguments = @(); Section = "Diagnostics"; RequiresAdmin = $false }
  )

  # ── Groups ────────────────────────────────────────────────────
  $script:defaultShortcutGroups = @("System", "Disk", "Network", "Security", "Startup", "Sound", "Diagnostics", "Custom")

  function Get-AllShortcutGroups {
      $all = [System.Collections.Generic.List[string]]::new()
      foreach ($g in $script:defaultShortcutGroups) {
          if ($g -notin $script:hiddenDefaultShortcutGroups) { $all.Add($g) }
      }
      foreach ($g in $script:customShortcutGroups)  { if ($g -notin $script:defaultShortcutGroups) { $all.Add($g) } }
      return @($all)
  }

  # Display names for default groups
  $script:sectionDisplayNames = @{
      "Disk"        = "Disk & storage"
      "Startup"     = "Startup & services"
      "Sound"       = "Sound & display"
  }

  # ── Shortcuts Management ───────────────────────────────────────
  $script:shortcuts = [System.Collections.Generic.List[hashtable]]::new()
  # Tracks dynamic section UI elements for search
  # Flat list of rendered shortcut cells: @{ Button; Section; Name; Command }
  $script:shortcutElements = @()

  # Dynamic grid columns, same rule as the Apps tiles
  $script:shortcutTileMinWidth = 220
  $__scGrid = Find "ShortcutGrid"
  if ($__scGrid) {
      $__scGrid.Add_SizeChanged({
          param($s, $e)
          if ($s.ActualWidth -le 0) { return }
          $cols = [Math]::Floor($s.ActualWidth / $script:shortcutTileMinWidth)
          if ($cols -lt 1) { $cols = 1 }
          if ($s.Columns -ne $cols) { $s.Columns = [int]$cols }
      })
  }

  function Initialize-Shortcuts {
      $script:shortcuts.Clear()

      # Load from settings if available
      $savedShortcuts = if ($script:settings.Shortcuts) { $script:settings.Shortcuts } else { @() }

      # Track loaded shortcut names
      $loadedNames = @{}

      # Load saved shortcuts (both defaults and custom)
      foreach ($saved in $savedShortcuts) {
          $isDefault = [bool]$saved.IsDefault
          # Always derive RequiresAdmin from the definition for defaults so updates take effect
          $requiresAdmin = if ($isDefault) {
              $defn = $script:defaultShortcuts | Where-Object { $_.Name -eq $saved.Name } | Select-Object -First 1
              if ($defn) { [bool]$defn.RequiresAdmin } else { [bool]$saved.RequiresAdmin }
          } else {
              [bool]$saved.RequiresAdmin
          }
          $shortcut = @{
              Name = $saved.Name
              Command = $saved.Command
              Arguments = @($saved.Arguments)
              IsDefault = $isDefault
              IsHidden = [bool]$saved.IsHidden
              Section = if ($saved.Section) { $saved.Section } else { "Custom" }
              RequiresAdmin = $requiresAdmin
          }
          $script:shortcuts.Add($shortcut)
          $loadedNames[$shortcut.Name] = $true
      }

      # Add any default shortcuts that weren't in settings
      foreach ($default in $script:defaultShortcuts) {
          if (-not $loadedNames.ContainsKey($default.Name)) {
              $shortcut = @{
                  Name = $default.Name
                  Command = $default.Command
                  Arguments = @($default.Arguments)
                  IsDefault = $true
                  IsHidden = $false
                  Section = $default.Section
                  RequiresAdmin = [bool]$default.RequiresAdmin
              }
              $script:shortcuts.Add($shortcut)
          }
      }

      Render-Shortcuts
  }

  function Refresh-ShortcutGroupBox {
      $groupBox = Find "ShortcutGroupBox"
      $prev = $groupBox.SelectedItem
      $groupBox.Items.Clear()
      $allGroups = Get-AllShortcutGroups
      foreach ($g in $allGroups) { $groupBox.Items.Add($g) | Out-Null }
      $groupBox.Items.Add("+ New group...") | Out-Null
      if ($prev -and $allGroups -contains $prev) {
          $groupBox.SelectedItem = $prev
      } else {
          $idx = $allGroups.IndexOf("Custom")
          $groupBox.SelectedIndex = if ($idx -ge 0) { $idx } else { 0 }
      }
  }

  function Render-Shortcuts {
      # One flat dynamic grid: the rail carries the groups, so no per-group
      # headers or left/right columns any more.
      $itemsPanel = Find "ShortcutGrid"
      $itemsPanel.Children.Clear()
      $script:shortcutElements = @()

      $allGroups = Get-AllShortcutGroups

      # Organize shortcuts by section
      $sections = [ordered]@{}
      foreach ($g in $allGroups) { $sections[$g] = @() }
      foreach ($shortcut in $script:shortcuts) {
          if (-not $shortcut.IsHidden) {
              $section = $shortcut.Section
              if (-not $sections.Contains($section)) { $sections[$section] = @() }
              $sections[$section] += $shortcut
          }
      }

      foreach ($sectionName in $sections.Keys) {
          foreach ($shortcut in $sections[$sectionName]) {

              $btn = New-Object System.Windows.Controls.Button
              $btn.Style = $window.FindResource("ShortcutRowButton")

              $cmdDisplay = switch ($shortcut.Command) {
                  "HostsFileSpecial" { "hosts file (admin)" }
                  "FlushDNSSpecial"  { "ipconfig /flushdns" }
                  default            { $shortcut.Command }
              }

              $rowGrid = New-Object System.Windows.Controls.Grid
              $starCol = New-Object System.Windows.Controls.ColumnDefinition
              $starCol.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
              $autoCol = New-Object System.Windows.Controls.ColumnDefinition
              $autoCol.Width = [System.Windows.GridLength]::Auto
              $rowGrid.ColumnDefinitions.Add($starCol)
              $rowGrid.ColumnDefinitions.Add($autoCol)

              $nameRow = New-Object System.Windows.Controls.StackPanel
              $nameRow.Orientation = "Horizontal"
              $nameRow.VerticalAlignment = "Center"
              [System.Windows.Controls.Grid]::SetColumn($nameRow, 0)

              $nameBlock = New-Object System.Windows.Controls.TextBlock
              $nameBlock.Text = $shortcut.Name
              $nameBlock.FontSize = 12
              $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
              $nameBlock.VerticalAlignment = "Center"
              $nameRow.Children.Add($nameBlock) | Out-Null

              if ($shortcut.RequiresAdmin) {
                  $adminBadge                = New-Object System.Windows.Controls.Border
                  $adminBadge.BorderThickness = [System.Windows.Thickness]::new(1)
                  $adminBadge.CornerRadius   = [System.Windows.CornerRadius]::new(7)
                  $adminBadge.Padding        = [System.Windows.Thickness]::new(6, 1, 6, 1)
                  $adminBadge.Margin         = [System.Windows.Thickness]::new(8, 0, 0, 0)
                  $adminBadge.VerticalAlignment = "Center"
                  $adminBadge.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "WarningBrush")
                  $adminBadgeText            = New-Object System.Windows.Controls.TextBlock
                  $adminBadgeText.Text       = "Admin"
                  $adminBadgeText.FontSize   = 10
                  $adminBadgeText.FontWeight = [System.Windows.FontWeights]::SemiBold
                  $adminBadgeText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "WarningBrush")
                  $adminBadge.Child          = $adminBadgeText
                  $nameRow.Children.Add($adminBadge) | Out-Null
              }

              $cmdBlock = New-Object System.Windows.Controls.TextBlock
              $cmdBlock.Text = $cmdDisplay
              $cmdBlock.FontSize = 11
              $cmdBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
              $cmdBlock.VerticalAlignment = "Center"
              [System.Windows.Controls.Grid]::SetColumn($cmdBlock, 1)

              $rowGrid.Children.Add($nameRow)  | Out-Null
              $rowGrid.Children.Add($cmdBlock) | Out-Null
              $btn.Content = $rowGrid

              $btn.Tag = @{
                  Name = $shortcut.Name
                  Command = $shortcut.Command
                  Arguments = $shortcut.Arguments
                  IsDefault = $shortcut.IsDefault
              }

              # Click handler
              $btn.Add_Click({
                  $data = $this.Tag
                  if ($data.Command -eq "HostsFileSpecial") {
                      try {
                          Start-Process "notepad.exe" -ArgumentList "$env:windir\System32\drivers\etc\hosts" -Verb RunAs
                          $footerStatus.Text = "Scy - Opened Hosts File"
                      } catch {
                          Show-ThemedDialog "Could not open Hosts File:`n$_" "Error" "OK" "Error"
                      }
                  } elseif ($data.Command -eq "FlushDNSSpecial") {
                      try {
                          $result = & ipconfig /flushdns 2>&1 | Out-String
                          Show-ThemedDialog $result.Trim() "DNS cache flushed" "OK" "Information"
                          $footerStatus.Text = "Scy - DNS cache flushed"
                      } catch {
                          Show-ThemedDialog "Failed to flush DNS: $_" "Error" "OK" "Error"
                      }
                  } else {
                      try {
                          if ($data.Arguments.Count -gt 0) {
                              Start-Process $data.Command -ArgumentList $data.Arguments
                          } else {
                              Start-Process $data.Command
                          }
                          $footerStatus.Text = "Scy - Opened $($data.Name)"
                      } catch {
                          Show-ThemedDialog "Could not open '$($data.Name)':`n$_" "Error" "OK" "Error"
                      }
                  }
              }.GetNewClosure())

              # Right-click context menu
              $shortcutRef = $shortcut
              $btn.Add_MouseRightButtonUp({
                  $data = $this.Tag
                  $shortcutObj = $shortcutRef

                  $menu = New-Object System.Windows.Controls.ContextMenu

                  # Hide/Show
                  if ($shortcutObj.IsHidden) {
                      $showItem = New-Object System.Windows.Controls.MenuItem
                      $showItem.Header = "Show"
                      $showItem.Add_Click({
                          $shortcutObj.IsHidden = $false
                          Save-ShortcutsToSettings
                          Render-Shortcuts
                      }.GetNewClosure())
                      $menu.Items.Add($showItem)
                  } else {
                      $hideItem = New-Object System.Windows.Controls.MenuItem
                      $hideItem.Header = "Hide"
                      $hideItem.Add_Click({
                          $shortcutObj.IsHidden = $true
                          Save-ShortcutsToSettings
                          Render-Shortcuts
                      }.GetNewClosure())
                      $menu.Items.Add($hideItem)
                  }

                  # Move to group submenu
                  $moveMenu = New-Object System.Windows.Controls.MenuItem
                  $moveMenu.Header = "Move to"
                  foreach ($secName in (Get-AllShortcutGroups)) {
                      $item = New-Object System.Windows.Controls.MenuItem
                      $item.Header = $secName
                      if ($secName -eq $shortcutObj.Section) { $item.IsEnabled = $false }
                      $targetSection = $secName
                      $item.Add_Click({
                          $shortcutObj.Section = $targetSection
                          Save-ShortcutsToSettings
                          Render-Shortcuts
                      }.GetNewClosure())
                      $moveMenu.Items.Add($item)
                  }
                  # New group option in move menu
                  $moveMenu.Items.Add((New-Object System.Windows.Controls.Separator))
                  $newGroupItem = New-Object System.Windows.Controls.MenuItem
                  $newGroupItem.Header = "New group..."
                  $newGroupItem.Add_Click({
                      Ensure-VisualBasic; $gName = [Microsoft.VisualBasic.Interaction]::InputBox("Group name:", "New Group", "")
                      if ([string]::IsNullOrWhiteSpace($gName)) { return }
                      $gName = $gName.Trim()
                      if ($gName -notin (Get-AllShortcutGroups)) {
                          $script:customShortcutGroups.Add($gName)
                          Save-Settings
                          Refresh-ShortcutGroupBox
                          if ((Get-Command Render-GroupSettings -ErrorAction SilentlyContinue)) { Render-GroupSettings }
                      }
                      $shortcutObj.Section = $gName
                      Save-ShortcutsToSettings
                      Render-Shortcuts
                  }.GetNewClosure())
                  $moveMenu.Items.Add($newGroupItem)
                  $menu.Items.Add($moveMenu)

                  # Delete (custom only)
                  if (-not $data.IsDefault) {
                      $deleteItem = New-Object System.Windows.Controls.MenuItem
                      $deleteItem.Header = "Delete"
                      $deleteItem.Add_Click({
                          $result = Show-ThemedDialog "Delete '$($data.Name)'?" "Confirm delete" "YesNo" "Question"
                          if ($result -eq "Yes") {
                              $script:shortcuts.Remove($shortcutObj)
                              Save-ShortcutsToSettings
                              Render-Shortcuts
                          }
                      }.GetNewClosure())
                      $menu.Items.Add($deleteItem)
                  }

                  $menu.PlacementTarget = $this
                  $menu.IsOpen = $true
              }.GetNewClosure())

              $itemsPanel.Children.Add($btn) | Out-Null
              # Track for rail/search filtering
              $script:shortcutElements += @{
                  Button  = $btn
                  Section = $sectionName
                  Name    = $shortcut.Name
                  Command = $shortcut.Command
              }
          }
      }

      Refresh-ShortcutGroupBox
      Apply-ShortcutFilter
      Build-BookmarksRail
  }

  # Show only the shortcuts matching the rail group + the search query.
  function Apply-ShortcutFilter {
      $box   = Find "ShortcutSearchBox"
      $query = if ($box) { $box.Text.Trim().ToLower() } else { "" }
      $group = $script:shortcutGroupFilter

      foreach ($el in $script:shortcutElements) {
          $inGroup = ($group -eq "All" -or $el.Section -eq $group)
          # NB: not $matches - that's a PowerShell automatic variable
          $isMatch = (-not $query) -or
                     $el.Name.ToLower().Contains($query) -or
                     ($el.Command -and $el.Command.ToLower().Contains($query))
          $el.Button.Visibility = if ($inGroup -and $isMatch) { "Visible" } else { "Collapsed" }
      }
  }

  function Save-ShortcutsToSettings {
      $script:settings.Shortcuts = @($script:shortcuts | ForEach-Object {
          @{
              Name = $_.Name
              Command = $_.Command
              Arguments = $_.Arguments
              IsDefault = $_.IsDefault
              IsHidden = $_.IsHidden
              Section = $_.Section
              RequiresAdmin = $_.RequiresAdmin
          }
      })
      Save-Settings
  }

  function Open-Setting {
      param([string]$Cmd, [string]$Label, [string[]]$CmdArgs = @())
      try {
          if ($CmdArgs.Count -gt 0) {
              Start-Process $Cmd -ArgumentList $CmdArgs
          } else {
              Start-Process $Cmd
          }
          $footerStatus.Text = "Scy - Opened $Label"
      } catch {
          Show-ThemedDialog "Could not open '$Label':`n$_" "Error" "OK" "Error"
      }
  }

# ── Populate group selector ──────────────────────────────────────
Refresh-ShortcutGroupBox

# Handle "New group..." selection in the group ComboBox
(Find "ShortcutGroupBox").Add_SelectionChanged({
    if ($this.SelectedItem -eq "+ New group...") {
        Ensure-VisualBasic; $gName = [Microsoft.VisualBasic.Interaction]::InputBox("Group name:", "New Group", "")
        if (-not [string]::IsNullOrWhiteSpace($gName)) {
            $gName = $gName.Trim()
            if ($gName -notin (Get-AllShortcutGroups)) {
                $script:customShortcutGroups.Add($gName)
                Save-Settings
                if ((Get-Command Render-GroupSettings -ErrorAction SilentlyContinue)) { Render-GroupSettings }
            }
            Refresh-ShortcutGroupBox
            (Find "ShortcutGroupBox").SelectedItem = $gName
        } else {
            $allGroups = Get-AllShortcutGroups
            $idx = $allGroups.IndexOf("Custom")
            (Find "ShortcutGroupBox").SelectedIndex = if ($idx -ge 0) { $idx } else { 0 }
        }
    }
})

# ── UI Event Handlers ─────────────────────────────────────────────
# Toggle Add Shortcut panel
(Find "BtnAddShortcut").Add_Click({
    $panel = Find "AddShortcutPanel"
    $panel.Visibility = if ($panel.Visibility -eq "Collapsed") {
        [System.Windows.Visibility]::Visible
    } else {
        [System.Windows.Visibility]::Collapsed
    }
})

# Cancel Add Shortcut
(Find "BtnCancelAddShortcut").Add_Click({
    (Find "AddShortcutPanel").Visibility = [System.Windows.Visibility]::Collapsed
    (Find "ShortcutNameBox").Text = ""
    (Find "ShortcutCommandBox").Text = ""
    (Find "ShortcutArgsBox").Text = ""
    (Find "ShortcutAdminCheck").IsChecked = $false
    $allGroups = Get-AllShortcutGroups
    $idx = $allGroups.IndexOf("Custom")
    (Find "ShortcutGroupBox").SelectedIndex = if ($idx -ge 0) { $idx } else { 0 }
})

# Browse for file
(Find "BtnBrowseShortcut").Add_Click({
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Executable files (*.exe)|*.exe|All files (*.*)|*.*"
    $dlg.Title = "Select executable or file"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        (Find "ShortcutCommandBox").Text = $dlg.FileName
    }
})

# Create shortcut
(Find "BtnCreateShortcut").Add_Click({
    $name = (Find "ShortcutNameBox").Text.Trim()
    $command = (Find "ShortcutCommandBox").Text.Trim()
    $argsText = (Find "ShortcutArgsBox").Text.Trim()

    if ($name -eq "" -or $command -eq "") {
        Show-ThemedDialog "Please enter both a name and command." "Missing information" "OK" "Warning"
        return
    }

    # Check for duplicate name
    if ($script:shortcuts | Where-Object { $_.Name -eq $name }) {
        Show-ThemedDialog "A shortcut with this name already exists." "Duplicate name" "OK" "Warning"
        return
    }

    # Parse arguments
    $arguments = if ($argsText -ne "") { $argsText -split ' ' } else { @() }

    # Create new custom shortcut
    $selectedGroup = (Find "ShortcutGroupBox").SelectedItem
    if (-not $selectedGroup -or $selectedGroup -eq "+ New group...") { $selectedGroup = "Custom" }
    $newShortcut = @{
        Name = $name
        Command = $command
        Arguments = $arguments
        IsDefault = $false
        IsHidden = $false
        Section = $selectedGroup
        RequiresAdmin = ((Find "ShortcutAdminCheck").IsChecked -eq $true)
    }

    $script:shortcuts.Add($newShortcut)
    Save-ShortcutsToSettings
    Render-Shortcuts

    # Clear form and hide panel
    (Find "ShortcutNameBox").Text = ""
    (Find "ShortcutCommandBox").Text = ""
    (Find "ShortcutArgsBox").Text = ""
    (Find "ShortcutAdminCheck").IsChecked = $false
    $allGroups = Get-AllShortcutGroups
    $idx = $allGroups.IndexOf("Custom")
    (Find "ShortcutGroupBox").SelectedIndex = if ($idx -ge 0) { $idx } else { 0 }
    (Find "AddShortcutPanel").Visibility = [System.Windows.Visibility]::Collapsed
})

# Restore defaults
(Find "BtnRestoreDefaults").Add_Click({
    $result = Show-ThemedDialog "Restore all default shortcuts?" "Confirm restore" "YesNo" "Question"
    if ($result -eq "Yes") {
        foreach ($shortcut in $script:shortcuts) {
            if ($shortcut.IsDefault) {
                $shortcut.IsHidden = $false
                $orig = $script:defaultShortcuts | Where-Object { $_.Name -eq $shortcut.Name } | Select-Object -First 1
                if ($orig) { $shortcut.Section = $orig.Section; $shortcut.RequiresAdmin = [bool]$orig.RequiresAdmin }
            }
        }
        Save-ShortcutsToSettings
        Render-Shortcuts
    }
})

# Reset shortcuts
(Find "BtnResetShortcuts").Add_Click({
    $result = Show-ThemedDialog "This will remove ALL custom shortcuts and restore all default shortcuts. Are you sure?" "Confirm reset" "YesNo" "Warning"
    if ($result -eq "Yes") {
        # Remove all custom shortcuts
        $defaults = @($script:shortcuts | Where-Object { $_.IsDefault })
        $script:shortcuts = [System.Collections.Generic.List[hashtable]]::new(
            [hashtable[]]$defaults
        )

        # Unhide all defaults and restore original sections
        foreach ($shortcut in $script:shortcuts) {
            $shortcut.IsHidden = $false
            $orig = $script:defaultShortcuts | Where-Object { $_.Name -eq $shortcut.Name } | Select-Object -First 1
            if ($orig) { $shortcut.Section = $orig.Section; $shortcut.RequiresAdmin = [bool]$orig.RequiresAdmin }
        }

        Save-ShortcutsToSettings
        Render-Shortcuts
    }
})

# Placeholder visibility handlers
(Find "ShortcutNameBox").Add_TextChanged({
    (Find "ShortcutNamePlaceholder").Visibility = if ($this.Text -eq "") { "Visible" } else { "Collapsed" }
})
(Find "ShortcutCommandBox").Add_TextChanged({
    (Find "ShortcutCommandPlaceholder").Visibility = if ($this.Text -eq "") { "Visible" } else { "Collapsed" }
})
(Find "ShortcutArgsBox").Add_TextChanged({
    (Find "ShortcutArgsPlaceholder").Visibility = if ($this.Text -eq "") { "Visible" } else { "Collapsed" }
})

# ── Search ───────────────────────────────────────────────────────
$script:shortcutSearchClear = Find "ShortcutSearchClear"

(Find "ShortcutSearchBox").Add_TextChanged({
    $query = $this.Text.Trim()
    (Find "ShortcutSearchPlaceholder").Visibility = if ($query -eq "") { "Visible" } else { "Collapsed" }
    $script:shortcutSearchClear.Visibility = if ($query -ne "") { "Visible" } else { "Collapsed" }
    # Group + query filtering both live in Apply-ShortcutFilter
    Apply-ShortcutFilter
})

$script:shortcutSearchClear.Add_Click({
    (Find "ShortcutSearchBox").Text = ""
})
