  # ── Shortcuts Tab ────────────────────────────────────────────────

  # ── Default Shortcuts Definition ───────────────────────────────
  $script:defaultShortcuts = @(
      @{ Name = "Advanced system";      Command = "sysdm.cpl";                        Arguments = @(); Section = "System" },
      @{ Name = "Environment variables"; Command = "SystemPropertiesAdvanced.exe";     Arguments = @(); Section = "System" },
      @{ Name = "Performance options";   Command = "SystemPropertiesPerformance.exe";  Arguments = @(); Section = "System" },
      @{ Name = "Device manager";        Command = "devmgmt.msc";                     Arguments = @(); Section = "System" },
      @{ Name = "System configuration";  Command = "msconfig";                         Arguments = @(); Section = "System" },
      @{ Name = "Disk management";       Command = "diskmgmt.msc";                     Arguments = @(); Section = "Disk" },
      @{ Name = "Disk cleanup";          Command = "cleanmgr";                         Arguments = @(); Section = "Disk" },
      @{ Name = "Optional features";    Command = "optionalfeatures";                 Arguments = @(); Section = "Disk" },
      @{ Name = "Network connections";   Command = "ncpa.cpl";                         Arguments = @(); Section = "Network" },
      @{ Name = "Network & sharing center"; Command = "control.exe"; Arguments = @("/name", "Microsoft.NetworkAndSharingCenter"); Section = "Network" },
      @{ Name = "Hosts file";           Command = "HostsFileSpecial";                  Arguments = @(); Section = "Network" },
      @{ Name = "Internet options";     Command = "inetcpl.cpl";                      Arguments = @(); Section = "Network" },
      @{ Name = "Flush DNS cache";       Command = "FlushDNSSpecial";                  Arguments = @(); Section = "Network" },
      @{ Name = "Credential manager";    Command = "control.exe"; Arguments = @("/name", "Microsoft.CredentialManager"); Section = "Security" },
      @{ Name = "Local security policy"; Command = "secpol.msc";                       Arguments = @(); Section = "Security" },
      @{ Name = "Group policy editor";   Command = "gpedit.msc";                       Arguments = @(); Section = "Security" },
      @{ Name = "Startup apps";          Command = "ms-settings:startupapps";          Arguments = @(); Section = "Startup" },
      @{ Name = "Services";              Command = "services.msc";                     Arguments = @(); Section = "Startup" },
      @{ Name = "Task scheduler";        Command = "taskschd.msc";                     Arguments = @(); Section = "Startup" },
      @{ Name = "Sound settings";        Command = "mmsys.cpl";                        Arguments = @(); Section = "Sound" },
      @{ Name = "Color calibration";     Command = "dccw.exe";                         Arguments = @(); Section = "Sound" },
      @{ Name = "DirectX diagnostic";    Command = "dxdiag";                           Arguments = @(); Section = "Diagnostics" },
      @{ Name = "Event viewer";          Command = "eventvwr.msc";                     Arguments = @(); Section = "Diagnostics" },
      @{ Name = "Resource monitor";      Command = "resmon";                           Arguments = @(); Section = "Diagnostics" },
      @{ Name = "Memory diagnostic";     Command = "mdsched";                          Arguments = @(); Section = "Diagnostics" }
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
  $script:shortcutSectionElements = @{}

  function Initialize-Shortcuts {
      $script:shortcuts.Clear()

      # Load from settings if available
      $savedShortcuts = if ($script:settings.Shortcuts) { $script:settings.Shortcuts } else { @() }

      # Track loaded shortcut names
      $loadedNames = @{}

      # Load saved shortcuts (both defaults and custom)
      foreach ($saved in $savedShortcuts) {
          $shortcut = @{
              Name = $saved.Name
              Command = $saved.Command
              Arguments = @($saved.Arguments)
              IsDefault = [bool]$saved.IsDefault
              IsHidden = [bool]$saved.IsHidden
              Section = if ($saved.Section) { $saved.Section } else { "Custom" }
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
      $parentPanel = Find "ShortcutSectionsPanel"
      $parentPanel.Children.Clear()
      $script:shortcutSectionElements = @{}

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
          $displayName = if ($script:sectionDisplayNames.ContainsKey($sectionName)) {
              $script:sectionDisplayNames[$sectionName]
          } else { $sectionName }

          $border              = New-Object System.Windows.Controls.Border
          $border.Background   = $window.Resources["Surface2Brush"]
          $border.CornerRadius = [System.Windows.CornerRadius]::new(6)
          $border.BorderBrush  = $window.Resources["BorderBrush"]
          $border.BorderThickness = [System.Windows.Thickness]::new(1)
          $border.Padding      = [System.Windows.Thickness]::new(14, 12, 14, 12)
          $border.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 8)

          $stack = New-Object System.Windows.Controls.StackPanel

          $header            = New-Object System.Windows.Controls.TextBlock
          $header.Text       = $displayName
          $header.FontSize   = 11
          $header.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
          $header.Margin     = [System.Windows.Thickness]::new(0, 0, 0, 8)
          $stack.Children.Add($header) | Out-Null

          $wrap = New-Object System.Windows.Controls.WrapPanel
          $stack.Children.Add($wrap) | Out-Null
          $border.Child = $stack

          if ($sections[$sectionName].Count -eq 0) {
              $border.Visibility = [System.Windows.Visibility]::Collapsed
          }

          # Store references for search
          $script:shortcutSectionElements[$sectionName] = @{ Border = $border; Panel = $wrap }

          foreach ($shortcut in $sections[$sectionName]) {
              $btn = New-Object System.Windows.Controls.Button
              $btn.Content = $shortcut.Name
              $btn.Style = $window.FindResource("QuickAppButton")
              $btn.Margin = "0,0,6,6"

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
                          Show-ThemedDialog $result.Trim() "DNS Cache Flushed" "OK" "Information"
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
                      $gName = [Microsoft.VisualBasic.Interaction]::InputBox("Group name:", "New Group", "")
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
                          $result = Show-ThemedDialog "Delete '$($data.Name)'?" "Confirm Delete" "YesNo" "Question"
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

              $wrap.Children.Add($btn) | Out-Null
          }

          $parentPanel.Children.Add($border) | Out-Null
      }

      Refresh-ShortcutGroupBox
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
        $gName = [Microsoft.VisualBasic.Interaction]::InputBox("Group name:", "New Group", "")
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
    }

    $script:shortcuts.Add($newShortcut)
    Save-ShortcutsToSettings
    Render-Shortcuts

    # Clear form and hide panel
    (Find "ShortcutNameBox").Text = ""
    (Find "ShortcutCommandBox").Text = ""
    (Find "ShortcutArgsBox").Text = ""
    $allGroups = Get-AllShortcutGroups
    $idx = $allGroups.IndexOf("Custom")
    (Find "ShortcutGroupBox").SelectedIndex = if ($idx -ge 0) { $idx } else { 0 }
    (Find "AddShortcutPanel").Visibility = [System.Windows.Visibility]::Collapsed
})

# Restore defaults
(Find "BtnRestoreDefaults").Add_Click({
    $result = Show-ThemedDialog "Restore all default shortcuts?" "Confirm Restore" "YesNo" "Question"
    if ($result -eq "Yes") {
        foreach ($shortcut in $script:shortcuts) {
            if ($shortcut.IsDefault) {
                $shortcut.IsHidden = $false
                $orig = $script:defaultShortcuts | Where-Object { $_.Name -eq $shortcut.Name }
                if ($orig) { $shortcut.Section = $orig.Section }
            }
        }
        Save-ShortcutsToSettings
        Render-Shortcuts
    }
})

# Reset shortcuts
(Find "BtnResetShortcuts").Add_Click({
    $result = Show-ThemedDialog "This will remove ALL custom shortcuts and restore all default shortcuts. Are you sure?" "Confirm Reset" "YesNo" "Warning"
    if ($result -eq "Yes") {
        # Remove all custom shortcuts
        $defaults = @($script:shortcuts | Where-Object { $_.IsDefault })
        $script:shortcuts = [System.Collections.Generic.List[hashtable]]::new(
            [hashtable[]]$defaults
        )

        # Unhide all defaults and restore original sections
        foreach ($shortcut in $script:shortcuts) {
            $shortcut.IsHidden = $false
            $orig = $script:defaultShortcuts | Where-Object { $_.Name -eq $shortcut.Name }
            if ($orig) { $shortcut.Section = $orig.Section }
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

    foreach ($secName in $script:shortcutSectionElements.Keys) {
        $el = $script:shortcutSectionElements[$secName]
        $anyVisible = $false
        foreach ($btn in $el.Panel.Children) {
            $visible = ($query -eq "") -or ($btn.Content -like "*$query*")
            $btn.Visibility = if ($visible) { "Visible" } else { "Collapsed" }
            if ($visible) { $anyVisible = $true }
        }
        $el.Border.Visibility = if ($anyVisible) { "Visible" } else { "Collapsed" }
    }
})

$script:shortcutSearchClear.Add_Click({
    (Find "ShortcutSearchBox").Text = ""
})
