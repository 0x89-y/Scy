# ── Settings Tab ─────────────────────────────────────────────────

# ── Settings sub-navigation ──────────────────────────────────────
$script:settingsNavLabels = @("General", "Appearance", "Apps & Groups", "About")

$settingsSectionAppearance = Find "SettingsSection_Appearance"
$settingsSectionGeneral    = Find "SettingsSection_General"
$settingsSectionGroups     = Find "SettingsSection_Groups"
$settingsSectionAbout      = Find "SettingsSection_About"

$script:settingsSections    = @($settingsSectionGeneral, $settingsSectionAppearance, $settingsSectionGroups, $settingsSectionAbout)

function Set-SettingsSubNav {
    param([int]$Index)
    if ($Index -lt 0 -or $Index -ge $script:settingsSections.Count) { $Index = 0 }
    $script:settingsSubNavIndex = $Index
    for ($i = 0; $i -lt $script:settingsSections.Count; $i++) {
        $script:settingsSections[$i].Visibility = if ($i -eq $Index) { "Visible" } else { "Collapsed" }
    }
    Build-Rail -Panel (Find "SettingsRail") -Labels $script:settingsNavLabels `
               -ActiveIndex $Index -OnSelect { param($i) Set-SettingsSubNav $i }
}

Set-SettingsSubNav 0

# ── Collapsible settings cards ──────────────────────────────────
foreach ($section in @("Updates", "Changelog", "General", "VisibleTabs", "Backup", "Credits", "Catalog", "Groups", "LocalInstallers", "AppUpdates", "AppBehavior", "IconCache")) {
    $header  = Find "SettingsHeader_$section"
    $header.Tag = $section
    $header.Add_MouseLeftButtonUp({
        $name    = $this.Tag
        $body    = Find "SettingsBody_$name"
        $chevron = Find "SettingsChevron_$name"
        if ($body.Visibility -eq "Visible") {
            $body.Visibility = "Collapsed"
            $chevron.Text = [char]0x25B6
        } else {
            $body.Visibility = "Visible"
            $chevron.Text = [char]0x25BC
        }
    })
}

$script:settingsFile = Join-Path $PSScriptRoot "..\settings.json"
$script:settings = @{}
$script:customShortcutGroups    = [System.Collections.Generic.List[string]]::new()
$script:customInstallCategories = [System.Collections.Generic.List[string]]::new()
$script:hiddenDefaultShortcutGroups    = [System.Collections.Generic.List[string]]::new()
$script:hiddenDefaultInstallCategories = [System.Collections.Generic.List[string]]::new()
$script:hiddenCuratedApps              = [System.Collections.Generic.List[string]]::new()
$script:customRegBookmarkGroups        = [System.Collections.Generic.List[string]]::new()
$script:hiddenTabs                     = [System.Collections.Generic.List[string]]::new()

# ── Theme model (cy-design) ───────────────────────────────────────
# Base palettes (Light/Dark zinc) come from Themes.ps1, shared with the splash.
# The accent is chosen separately; state lives in these three script vars,
# initialized from settings further down and applied by Apply-Theme.
#   $script:themeMode   = "System" | "Light" | "Dark"
#   $script:accentName  = <preset> | "windows" | "custom"
#   $script:customAccent = "#rrggbb"  (used when accentName -eq "custom")

function script:New-Brush($hex) {
    $color = [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString($hex)
    ([System.Windows.Media.SolidColorBrush]::new($color)).psobject.BaseObject
}

function script:LightenHex($hex, $amount) {
    $r = [Math]::Min(255, [Convert]::ToInt32($hex.Substring(1,2), 16) + $amount)
    $g = [Math]::Min(255, [Convert]::ToInt32($hex.Substring(3,2), 16) + $amount)
    $b = [Math]::Min(255, [Convert]::ToInt32($hex.Substring(5,2), 16) + $amount)
    "#{0:X2}{1:X2}{2:X2}" -f $r, $g, $b
}

function script:LerpHex($hex1, $hex2, $t) {
    $r1 = [Convert]::ToInt32($hex1.Substring(1,2), 16); $r2 = [Convert]::ToInt32($hex2.Substring(1,2), 16)
    $g1 = [Convert]::ToInt32($hex1.Substring(3,2), 16); $g2 = [Convert]::ToInt32($hex2.Substring(3,2), 16)
    $b1 = [Convert]::ToInt32($hex1.Substring(5,2), 16); $b2 = [Convert]::ToInt32($hex2.Substring(5,2), 16)
    "#{0:X2}{1:X2}{2:X2}" -f [int]($r1+($r2-$r1)*$t), [int]($g1+($g2-$g1)*$t), [int]($b1+($b2-$b1)*$t)
}

function script:Get-WindowsAccentHex {
    try {
        $dw = Get-ItemPropertyValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Accent" "AccentColorMenu"
        $r = $dw -band 0xFF
        $g = ($dw -shr 8) -band 0xFF
        $b = ($dw -shr 16) -band 0xFF
        return "#{0:X2}{1:X2}{2:X2}" -f $r, $g, $b
    } catch { return $null }
}

# Resolve the currently-selected accent to a concrete hex for the given mode.
function script:Get-AccentHex {
    param([string]$Mode)   # "Light" | "Dark"
    switch ($script:accentName) {
        "windows" {
            $wa = Get-WindowsAccentHex
            if ($wa) { $wa } else { $script:AccentPresets["purple"][$Mode] }
        }
        "custom" {
            if ($script:customAccent) { $script:customAccent } else { $script:AccentPresets["purple"][$Mode] }
        }
        default {
            $p = $script:AccentPresets[$script:accentName]
            if ($p) { $p[$Mode] } else { $script:AccentPresets["purple"][$Mode] }
        }
    }
}

function script:Apply-Theme {
    # cy-design: pick the Light/Dark zinc base from the mode, then overlay the
    # separately-chosen accent (preset / Windows / custom) and derive its
    # hover + 16% container wash.
    $mode = Resolve-ThemeMode $script:themeMode      # "Light" | "Dark"
    $base = $script:BuiltinThemes[$mode]
    if (-not $base) { return }
    $t = @{}
    foreach ($k in $base.Keys) { $t[$k] = $base[$k] }

    $accent = Get-AccentHex $mode
    $t.Accent          = $accent
    $t.AccentHover     = if ($mode -eq "Light") { LerpHex $accent "#000000" 0.15 } else { LerpHex $accent "#ffffff" 0.20 }
    $t.AccentContainer = LerpHex $t.Surface $accent 0.16

    # Replace each resource entry with a new SolidColorBrush (.psobject.BaseObject ensures
    # the actual CLR object is stored, not a PowerShell PSObject wrapper)
    $window.Resources["WindowBgBrush"]        = New-Brush $t.WindowBg
    $window.Resources["AppBgBrush"]           = New-Brush $t.AppBg
    $window.Resources["GridDotBrush"]         = New-Brush $t.GridDot
    $window.Resources["AccentBrush"]          = New-Brush $t.Accent
    $window.Resources["AccentHoverBrush"]     = New-Brush $t.AccentHover
    $window.Resources["AccentContainerBrush"] = New-Brush $t.AccentContainer
    $window.Resources["AccentContrastBrush"]  = New-Brush $t.AccentContrast
    $window.Resources["SurfaceBrush"]         = New-Brush $t.Surface
    $window.Resources["Surface2Brush"]        = New-Brush $t.Surface2
    $window.Resources["BorderBrush"]          = New-Brush $t.Border
    $window.Resources["BorderStrongBrush"]    = New-Brush $t.BorderStrong
    $window.Resources["MutedText"]            = New-Brush $t.MutedText
    $window.Resources["FgBrush"]              = New-Brush $t.FgBrush
    $window.Resources["SubTextBrush"]         = New-Brush $t.SubText
    $window.Resources["WinCtrlFgBrush"]       = New-Brush $t.WinCtrlFg
    $window.Resources["ScrollThumbBrush"]     = New-Brush $t.ScrollThumb
    $window.Resources["InputBgBrush"]         = New-Brush $t.InputBg
    $window.Resources["HoverSurfaceBrush"]    = New-Brush $t.HoverSurface
    $window.Resources["SuccessBrush"]         = New-Brush $t.Success
    $window.Resources["WarningBrush"]         = New-Brush $t.Warning
    $window.Resources["DangerBrush"]          = New-Brush $t.Danger

    # Window Background/Foreground set directly (root Window element can't use resource refs)
    $window.Background = New-Brush $t.WindowBg
    $window.Foreground = New-Brush $t.FgBrush

    Update-ThemePickerUI
    Save-Settings

    # No sub-nav re-apply needed: every tab's nav is now a rail whose entries
    # bind their brushes via SetResourceReference, so they retint themselves.
    # Re-running the Set-*SubNav functions here would only risk resetting the
    # user's current rail selection (e.g. Network's flat rail maps section 0 to
    # its first tool, which would bounce them off "Speed test").
}

# Highlight the active mode button + paint/ring the accent swatches.
function script:Update-ThemePickerUI {
    foreach ($m in @("System","Light","Dark")) {
        $btn = Find "Mode$m"
        if ($btn) {
            if ($m -eq $script:themeMode) {
                $btn.BorderBrush = $window.Resources["AccentBrush"]
                $btn.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "FgBrush")
            } else {
                $btn.BorderBrush = $window.Resources["BorderStrongBrush"]
                $btn.Background = [System.Windows.Media.Brushes]::Transparent
                $btn.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "MutedText")
            }
        }
    }

    $mode = Resolve-ThemeMode $script:themeMode
    $ringOn  = $window.Resources["FgBrush"]
    $ringOff = $window.Resources["BorderBrush"]
    foreach ($name in @($script:AccentPresets.Keys)) {
        $sw = Find "AccentSwatch_$name"
        if ($sw) {
            $sw.Background  = New-Brush $script:AccentPresets[$name][$mode]
            $sw.BorderBrush = if ($script:accentName -eq $name) { $ringOn } else { $ringOff }
        }
    }
    $swWin = Find "AccentSwatch_windows"
    if ($swWin) {
        $wa = Get-WindowsAccentHex
        if ($wa) { $swWin.Background = New-Brush $wa }
        $swWin.BorderBrush = if ($script:accentName -eq "windows") { $ringOn } else { $ringOff }
    }
    $swCus = Find "AccentSwatch_custom"
    if ($swCus) {
        if ($script:customAccent) { $swCus.Background = New-Brush $script:customAccent }
        $swCus.BorderBrush = if ($script:accentName -eq "custom") { $ringOn } else { $ringOff }
    }
}

# Change the theme mode (System/Light/Dark) and re-apply.
function script:Set-ThemeMode {
    param([string]$Mode)
    $script:themeMode = $Mode
    Apply-Theme
}

# Change the accent (preset name / "windows" / "custom") and re-apply.
function script:Set-Accent {
    param([string]$Name)
    $script:accentName = $Name
    Apply-Theme
}

# ── Load / Save settings ──────────────────────────────────────────
function Save-Settings {
    try {
        @{
            LocalInstallFolder = $script:localInstallFolder
            ThemeMode          = $script:themeMode
            Accent             = $script:accentName
            CustomAccent       = $script:customAccent
            AutoCheckUpdates   = $script:autoCheckUpdates
            AutoCheckSelfUpdate = $script:autoCheckSelfUpdate
            UseDevBranch       = $script:useDevBranch
            RememberWindowPosition = $script:rememberWindowPosition
            DisableAutoIconFetch    = $script:disableAutoIconFetch
            SkipSplash                  = $script:skipSplash
            EnableNotifications         = $script:enableNotifications
            SkipSingleUninstallConfirm  = $script:skipSingleUninstallConfirm
            DefaultAppsSubTab           = $script:defaultAppsSubTab
            DefaultTab                  = $script:defaultTab
            CollapsedTweakGroups        = @($script:collapsedTweakGroups)
            EnableLogging               = $script:enableLogging
            SpeedTestServer    = $script:speedTestServer
            WindowGeometry     = $script:windowGeometry
            QuickInstalls      = @($script:quickInstalls | ForEach-Object { @{Name=$_.Name; Id=$_.Id; Category=$_.Category} })
            QuickBundles       = @($script:quickBundles  | ForEach-Object { @{Name=$_.Name; Description=$_.Description; Apps=@($_.Apps | ForEach-Object { @{Name=$_.Name; Id=$_.Id} })} })
            Shortcuts              = $script:settings.Shortcuts
            CustomShortcutGroups   = @($script:customShortcutGroups)
            CustomInstallCategories = @($script:customInstallCategories)
            HiddenDefaultShortcutGroups    = @($script:hiddenDefaultShortcutGroups)
            HiddenDefaultInstallCategories = @($script:hiddenDefaultInstallCategories)
            HiddenCuratedApps              = @($script:hiddenCuratedApps)
            HiddenTabs                     = @($script:hiddenTabs)
            RememberCleanTargets           = $script:rememberCleanTargets
            AutoScanLocalInstallers        = $script:autoScanLocalInstallers
            RememberLocalInstallers        = $script:rememberLocalInstallers
            CachedLocalInstallers          = @($script:cachedLocalInstallers)
            LocalInstallerExtensions       = @($script:localInstallerExtensions)
            CleanTargetSelection           = $script:cleanTargetSelection
            RegBookmarks                   = $script:settings.RegBookmarks
            CustomRegBookmarkGroups        = @($script:customRegBookmarkGroups)
            NotesPreviewMode               = $script:notesPreviewMode
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $script:settingsFile -Encoding UTF8
    } catch {}
}

function Set-LocalInstallFolder {
    param([string]$Path)
    $script:localInstallFolder = $Path
    Save-Settings
    (Find "SettingsLocalFolder").Text = $Path
    Update-LocalInstallers
}

# ── Load saved settings ───────────────────────────────────────────
$script:themeMode          = "System"
$script:accentName         = "purple"
$script:customAccent       = "#7c3aed"
$script:autoCheckUpdates   = $false
$script:autoCheckSelfUpdate = $false
$script:useDevBranch        = $false
$script:rememberWindowPosition = $false
$script:disableAutoIconFetch    = $true   # default ON - user opts in via Settings > Groups > Icon cache
$script:skipSplash                  = $false
$script:enableNotifications         = $true
$script:skipSingleUninstallConfirm  = $false
$script:defaultAppsSubTab           = "Store"
$script:defaultTab                  = "Apps"
$script:collapsedTweakGroups        = [System.Collections.Generic.List[string]]::new()
# $script:enableLogging is initialized early in Scy.ps1; restored from saved settings below.
$script:rememberCleanTargets   = $false
$script:autoScanLocalInstallers    = $false
$script:rememberLocalInstallers    = $false
$script:cachedLocalInstallers      = @()
$script:localInstallerExtensions   = [System.Collections.Generic.List[string]]::new()
$script:localInstallerExtensions.Add('.exe')
$script:localInstallerExtensions.Add('.msi')
$script:cleanTargetSelection   = @{}
$script:windowGeometry     = $null
$script:speedTestServer    = "Hetzner FSN1 (DE)"

if (Test-Path $script:settingsFile) {
    try {
        $saved = Get-Content $script:settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($saved.LocalInstallFolder) { $script:localInstallFolder = $saved.LocalInstallFolder }
        # Theme: new schema (ThemeMode + Accent + CustomAccent) with back-compat
        # migration from the old named-theme model.
        if ($saved.ThemeMode)   { $script:themeMode  = [string]$saved.ThemeMode }
        elseif ($saved.Theme)   { $script:themeMode  = if ([string]$saved.Theme -in @("Blossom","Frost")) { "Light" } else { "Dark" } }
        if ($saved.Accent)      { $script:accentName = [string]$saved.Accent }
        elseif ($null -ne $saved.UseWindowsAccent -and [bool]$saved.UseWindowsAccent) { $script:accentName = "windows" }
        if ($saved.CustomAccent -and [string]$saved.CustomAccent -match '^#[0-9a-fA-F]{6}$') { $script:customAccent = [string]$saved.CustomAccent }
        elseif ($saved.CustomTheme -and $saved.CustomTheme.Accent -match '^#[0-9a-fA-F]{6}$') { $script:customAccent = [string]$saved.CustomTheme.Accent }
        if ($null -ne $saved.AutoCheckUpdates)   { $script:autoCheckUpdates   = [bool]$saved.AutoCheckUpdates }
        if ($null -ne $saved.AutoCheckSelfUpdate)  { $script:autoCheckSelfUpdate = [bool]$saved.AutoCheckSelfUpdate }
        if ($null -ne $saved.UseDevBranch)         { $script:useDevBranch        = [bool]$saved.UseDevBranch }
        if ($null -ne $saved.RememberWindowPosition) { $script:rememberWindowPosition = [bool]$saved.RememberWindowPosition }
        if ($null -ne $saved.DisableAutoIconFetch)    { $script:disableAutoIconFetch    = [bool]$saved.DisableAutoIconFetch }
        if ($null -ne $saved.SkipSplash)                  { $script:skipSplash                  = [bool]$saved.SkipSplash }
        if ($null -ne $saved.EnableNotifications)         { $script:enableNotifications         = [bool]$saved.EnableNotifications }
        if ($null -ne $saved.SkipSingleUninstallConfirm)  { $script:skipSingleUninstallConfirm  = [bool]$saved.SkipSingleUninstallConfirm }
        if ($null -ne $saved.EnableLogging)               { $script:enableLogging              = [bool]$saved.EnableLogging }
        if ($saved.DefaultAppsSubTab)                     { $script:defaultAppsSubTab           = [string]$saved.DefaultAppsSubTab }
        if ($saved.DefaultTab)                            { $script:defaultTab                  = [string]$saved.DefaultTab }
        if ($null -ne $saved.CollapsedTweakGroups) {
            $script:collapsedTweakGroups.Clear()
            foreach ($g in $saved.CollapsedTweakGroups) { $script:collapsedTweakGroups.Add([string]$g) | Out-Null }
        }
        if ($saved.SpeedTestServer)              { $script:speedTestServer    = [string]$saved.SpeedTestServer }
        if ($saved.WindowGeometry) {
            $wg = $saved.WindowGeometry
            $script:windowGeometry = @{
                Left   = [double]$wg.Left
                Top    = [double]$wg.Top
                Width  = [double]$wg.Width
                Height = [double]$wg.Height
                State  = [string]$wg.State
            }
        }
        if ($null -ne $saved.QuickInstalls) {
            $script:quickInstalls.Clear()
            foreach ($qi in $saved.QuickInstalls) {
                $cat = if ($qi.Category) { [string]$qi.Category } else { "" }
                $script:quickInstalls.Add(@{Name=$qi.Name; Id=$qi.Id; Category=$cat})
            }
        }
        if ($null -ne $saved.QuickBundles) {
            $script:quickBundles.Clear()
            foreach ($b in $saved.QuickBundles) {
                $apps = [System.Collections.Generic.List[hashtable]]::new()
                if ($b.Apps) {
                    foreach ($a in $b.Apps) {
                        $apps.Add(@{Name=[string]$a.Name; Id=[string]$a.Id})
                    }
                }
                $desc = if ($b.Description) { [string]$b.Description } else { "" }
                $script:quickBundles.Add(@{Name=[string]$b.Name; Description=$desc; Apps=$apps})
            }
        }
        if ($null -ne $saved.Shortcuts) {
            $script:settings.Shortcuts = $saved.Shortcuts
        }
        if ($null -ne $saved.CustomShortcutGroups) {
            $script:customShortcutGroups.Clear()
            foreach ($g in $saved.CustomShortcutGroups) { $script:customShortcutGroups.Add([string]$g) }
        }
        if ($null -ne $saved.CustomInstallCategories) {
            $script:customInstallCategories.Clear()
            foreach ($g in $saved.CustomInstallCategories) { $script:customInstallCategories.Add([string]$g) }
        }
        if ($null -ne $saved.HiddenDefaultShortcutGroups) {
            $script:hiddenDefaultShortcutGroups.Clear()
            foreach ($g in $saved.HiddenDefaultShortcutGroups) { $script:hiddenDefaultShortcutGroups.Add([string]$g) }
        }
        if ($null -ne $saved.HiddenDefaultInstallCategories) {
            $script:hiddenDefaultInstallCategories.Clear()
            foreach ($g in $saved.HiddenDefaultInstallCategories) { $script:hiddenDefaultInstallCategories.Add([string]$g) }
        }
        if ($null -ne $saved.HiddenCuratedApps) {
            $script:hiddenCuratedApps.Clear()
            foreach ($h in $saved.HiddenCuratedApps) { $script:hiddenCuratedApps.Add([string]$h) }
        }
        if ($null -ne $saved.HiddenTabs) {
            $script:hiddenTabs.Clear()
            foreach ($h in $saved.HiddenTabs) { $script:hiddenTabs.Add([string]$h) }
        }
        if ($null -ne $saved.RememberCleanTargets) { $script:rememberCleanTargets = [bool]$saved.RememberCleanTargets }
        if ($null -ne $saved.AutoScanLocalInstallers) { $script:autoScanLocalInstallers = [bool]$saved.AutoScanLocalInstallers }
        if ($null -ne $saved.RememberLocalInstallers) { $script:rememberLocalInstallers = [bool]$saved.RememberLocalInstallers }
        if ($null -ne $saved.LocalInstallerExtensions) {
            $script:localInstallerExtensions.Clear()
            foreach ($ext in $saved.LocalInstallerExtensions) { $script:localInstallerExtensions.Add([string]$ext) }
        }
        if ($null -ne $saved.CachedLocalInstallers) {
            $script:cachedLocalInstallers = @($saved.CachedLocalInstallers | ForEach-Object { @{Name=[string]$_.Name; FullName=[string]$_.FullName} })
        }
        if ($null -ne $saved.CleanTargetSelection) {
            $script:cleanTargetSelection = @{}
            foreach ($prop in $saved.CleanTargetSelection.PSObject.Properties) {
                $script:cleanTargetSelection[$prop.Name] = [bool]$prop.Value
            }
        }
        if ($null -ne $saved.RegBookmarks) {
            $script:settings.RegBookmarks = $saved.RegBookmarks
        }
        if ($null -ne $saved.CustomRegBookmarkGroups) {
            $script:customRegBookmarkGroups.Clear()
            foreach ($g in $saved.CustomRegBookmarkGroups) { $script:customRegBookmarkGroups.Add([string]$g) }
        }
        if ($null -ne $saved.NotesPreviewMode) { $script:notesPreviewMode = [bool]$saved.NotesPreviewMode }
    } catch {}
}

# ── Top nav strip layout ──────────────────────────────────────────
function Apply-NavLayout {
    $tc     = Find "MainTabControl"
    $search = Find "GlobalSearchContainer"
    if (-not $tc) { return }

    $tc.TabStripPlacement = [System.Windows.Controls.Dock]::Top
    # cy-design: pane fills the window edge-to-edge (no floating margin)
    $tc.Margin    = [System.Windows.Thickness]::new(0)
    $tc.Padding   = [System.Windows.Thickness]::new(0)
    $headerMargin = [System.Windows.Thickness]::new(16, 4, 0, 8)
    if ($search) {
        # Top 6 centres the 32px search inside the ~37px tab strip band
        # (headerMargin top 4). At 14 it hung below the tabs onto the pane.
        $search.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
        $search.Width  = 260
        $search.Margin = [System.Windows.Thickness]::new(0, 6, 20, 0)
    }

    # Reach into the default TabControl template and set the inner TabPanel's margin directly.
    # The previous Resources/Style approach didn't apply because PowerShell's PSObject wrapping
    # of Setter values prevents WPF from casting them to Thickness at apply time.
    $tc.ApplyTemplate() | Out-Null
    $headerPanel = $tc.Template.FindName('HeaderPanel', $tc)
    if ($headerPanel) {
        $headerPanel.Margin              = $headerMargin
        $headerPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    }
}

# ── Tab visibility ────────────────────────────────────────────────
function Apply-TabVisibility {
    $tc = Find "MainTabControl"
    if (-not $tc) { return }
    $firstVisible = $null
    foreach ($item in $tc.Items) {
        $header = [string]$item.Header
        # Settings has no strip header - it opens from the title-bar cog - so it
        # stays collapsed in the strip yet remains programmatically selectable.
        if ($header -eq "Settings") { $item.Visibility = "Collapsed"; continue }
        $hidden = ($script:hiddenTabs -contains $header)
        $item.Visibility = if ($hidden) { "Collapsed" } else { "Visible" }
        if (-not $hidden -and $null -eq $firstVisible) { $firstVisible = $item }
    }
    # Kick selection off a hidden tab, but never off Settings (cog-opened).
    if ($tc.SelectedItem -and $tc.SelectedItem.Visibility -eq "Collapsed" `
        -and [string]$tc.SelectedItem.Header -ne "Settings" -and $firstVisible) {
        $tc.SelectedItem = $firstVisible
    }
}

function Apply-TabContextMenus {
    $tc = Find "MainTabControl"
    if (-not $tc) { return }
    foreach ($item in $tc.Items) {
        $header = [string]$item.Header
        if ($header -eq "Settings") { continue }
        if ($item.ContextMenu) { continue }

        $menu = New-Object System.Windows.Controls.ContextMenu
        $hide = New-Object System.Windows.Controls.MenuItem
        $hide.Header = "Hide tab"
        $hide.Tag    = $header
        $hide.Add_Click({
            param($s, $e)
            $h = [string]$s.Tag
            if (-not ($script:hiddenTabs -contains $h)) { $script:hiddenTabs.Add($h) | Out-Null }
            Save-Settings
            Apply-TabVisibility
            Build-TabVisibilityList
            if (Get-Command Update-GlobalSearchIndex -ErrorAction SilentlyContinue) { Update-GlobalSearchIndex }
        })
        $menu.Items.Add($hide) | Out-Null
        # A TabItem's body is hosted by the TabControl's content presenter, not a
        # visual child of the TabItem, and ContextMenu doesn't inherit to it - so
        # this menu only ever opens from the tab header in the strip. No guard needed.
        $item.ContextMenu = $menu
    }
}

function Build-TabVisibilityList {
    $list = Find "TabVisibilityList"
    $tc   = Find "MainTabControl"
    if (-not $list -or -not $tc) { return }
    $list.Children.Clear()

    foreach ($item in $tc.Items) {
        $header = [string]$item.Header
        if ($header -eq "Settings") { continue }

        # cy-design divided-list row: flush, hairline bottom divider, toggle switch
        $row = New-Object System.Windows.Controls.Border
        $row.Background      = [System.Windows.Media.Brushes]::Transparent
        $row.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
        $row.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
        $row.Padding         = [System.Windows.Thickness]::new(0, 9, 0, 9)
        $row.Cursor          = [System.Windows.Input.Cursors]::Hand
        $row.Add_MouseEnter({ $this.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "HoverSurfaceBrush") })
        $row.Add_MouseLeave({ $this.Background = [System.Windows.Media.Brushes]::Transparent })

        $grid = New-Object System.Windows.Controls.Grid
        $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::Auto
        $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1)

        $label                   = New-Object System.Windows.Controls.TextBlock
        $label.Text              = $header
        $label.FontSize          = 12
        $label.FontWeight        = [System.Windows.FontWeights]::SemiBold
        $label.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $label.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
        [System.Windows.Controls.Grid]::SetColumn($label, 0)

        $cb                   = New-Object System.Windows.Controls.CheckBox
        $cb.Style             = $window.Resources["TweakToggle"]
        $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $cb.Margin            = [System.Windows.Thickness]::new(12, 0, 0, 0)
        $cb.Tag               = $header
        $cb.IsChecked         = -not ($script:hiddenTabs -contains $header)
        [System.Windows.Controls.Grid]::SetColumn($cb, 1)

        # IsChecked set above BEFORE wiring handlers so the initial state doesn't fire them
        $onToggle = {
            param($s, $e)
            $h = [string]$s.Tag
            if ($s.IsChecked) {
                $script:hiddenTabs.Remove($h) | Out-Null
            } elseif (-not ($script:hiddenTabs -contains $h)) {
                $script:hiddenTabs.Add($h) | Out-Null
            }
            Save-Settings
            Apply-TabVisibility
            if (Get-Command Update-GlobalSearchIndex -ErrorAction SilentlyContinue) { Update-GlobalSearchIndex }
        }
        $cb.Add_Checked($onToggle)
        $cb.Add_Unchecked($onToggle)

        # Click anywhere on the row toggles the switch (unless the click hit the switch itself)
        $row.Tag = $cb
        $row.Add_MouseLeftButtonUp({
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

        $grid.Children.Add($label) | Out-Null
        $grid.Children.Add($cb)    | Out-Null
        $row.Child = $grid
        $list.Children.Add($row) | Out-Null
    }
}

(Find "SettingsLocalFolder").Text = $script:localInstallFolder
(Find "ToggleAutoCheckUpdates").IsChecked = $script:autoCheckUpdates
(Find "ToggleAutoCheckSelfUpdate").IsChecked = $script:autoCheckSelfUpdate
(Find "ToggleUseDevBranch").IsChecked = $script:useDevBranch
(Find "ToggleRememberPosition").IsChecked = $script:rememberWindowPosition
(Find "ToggleRememberCleanTargets").IsChecked = $script:rememberCleanTargets
(Find "ToggleScanLocalInstallers").IsChecked = $script:autoScanLocalInstallers
(Find "ToggleRememberLocalInstallers").IsChecked = $script:rememberLocalInstallers
# Build-TabVisibilityList deferred to first Settings-tab visit (Invoke-ScyTabInit
# in Scy.ps1). Apply-TabVisibility/ContextMenus/NavLayout stay eager - they
# affect the whole window, not just the Settings tab.
Apply-TabVisibility
Apply-TabContextMenus
Apply-NavLayout
$window.Dispatcher.BeginInvoke([action]{ Update-QuickInstalls }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null

# Apply the saved/default theme on startup
Apply-Theme

# Follow the Windows light/dark setting live when mode is "System": re-apply the
# theme whenever the window regains focus and the resolved OS mode has changed.
$script:lastResolvedMode = Resolve-ThemeMode $script:themeMode
$window.Add_Activated({
    if ($script:themeMode -eq "System") {
        $now = Resolve-ThemeMode "System"
        if ($now -ne $script:lastResolvedMode) {
            $script:lastResolvedMode = $now
            Apply-Theme
        }
    }
})

# Initialize shortcuts after settings are loaded
$window.Dispatcher.BeginInvoke([action]{ Initialize-Shortcuts }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
$window.Dispatcher.BeginInvoke([action]{ Initialize-RegBookmarks }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null

# Trigger update check on launch if enabled (deferred until window is rendered)
if ($script:autoCheckUpdates) {
    $window.Dispatcher.BeginInvoke([action]{
        (Find "BtnCheckUpdates").RaiseEvent(
            [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
        )
    }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
}

# Trigger Scy self-update check on launch if enabled
if ($script:autoCheckSelfUpdate) {
    $window.Dispatcher.BeginInvoke([action]{
        try {
            $branch = if ($script:useDevBranch) { "dev" } else { "main" }
            $remoteJson = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/0x89-y/Scy/$branch/version.json" `
                                            -Headers @{ "User-Agent" = "Scy-Updater" } `
                                            -TimeoutSec 5
            $script:latestVersion = $remoteJson.version

            $selfUpdateStatusText   = Find "SelfUpdateStatusText"
            $btnInstallSelfUpdate   = Find "BtnInstallSelfUpdate"
            $updateBanner           = Find "UpdateBanner"

            if ([version]$script:latestVersion -gt [version]$script:localVersion.version) {
                $selfUpdateStatusText.Text       = "Update available  (v$($script:latestVersion))"
                $selfUpdateStatusText.Foreground = $window.Resources["WarningBrush"]
                $btnInstallSelfUpdate.Visibility = "Visible"
                $updateBanner.Text       = "Update available (v$($script:latestVersion))"
                $updateBanner.Visibility = "Visible"
            } else {
                $selfUpdateStatusText.Text       = "Up to date"
                $selfUpdateStatusText.Foreground = $window.Resources["SuccessBrush"]
            }
        } catch {
            # Silently ignore - network may be unavailable
        }
    }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
}

# ── Theme mode + accent handlers ──────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing       -ErrorAction SilentlyContinue

(Find "ModeSystem").Add_Click({ Set-ThemeMode "System" })
(Find "ModeLight").Add_Click( { Set-ThemeMode "Light"  })
(Find "ModeDark").Add_Click(  { Set-ThemeMode "Dark"   })

foreach ($presetName in @($script:AccentPresets.Keys)) {
    $captured = $presetName
    $sw = Find "AccentSwatch_$captured"
    if ($sw) { $sw.Add_MouseLeftButtonUp(({ Set-Accent $captured }).GetNewClosure()) }
}
(Find "AccentSwatch_windows").Add_MouseLeftButtonUp({ Set-Accent "windows" })
(Find "AccentSwatch_custom").Add_MouseLeftButtonUp({
    $hex = if ($script:customAccent) { $script:customAccent } else { "#7c3aed" }
    $r = [Convert]::ToInt32($hex.Substring(1,2), 16)
    $g = [Convert]::ToInt32($hex.Substring(3,2), 16)
    $b = [Convert]::ToInt32($hex.Substring(5,2), 16)
    $dlg          = New-Object System.Windows.Forms.ColorDialog
    $dlg.FullOpen = $true
    $dlg.Color    = [System.Drawing.Color]::FromArgb($r, $g, $b)
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $c = $dlg.Color
        $script:customAccent = "#{0:X2}{1:X2}{2:X2}" -f $c.R, $c.G, $c.B
        Set-Accent "custom"
    }
})

# ── Settings tab - change folder ─────────────────────────────────
(Find "BtnSettingsChangeFolder").Add_Click({
    Add-Type -AssemblyName System.Windows.Forms
    $dlg             = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select folder to scan for installers"
    $dlg.SelectedPath = $script:localInstallFolder
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Set-LocalInstallFolder $dlg.SelectedPath
    }
})

# ── Auto-check for updates toggle ────────────────────────────────
(Find "ToggleAutoCheckUpdates").Add_Checked({   $script:autoCheckUpdates = $true;  Save-Settings })
(Find "ToggleAutoCheckUpdates").Add_Unchecked({ $script:autoCheckUpdates = $false; Save-Settings })

# ── Auto-check for Scy self-updates toggle ───────────────────────
(Find "ToggleAutoCheckSelfUpdate").Add_Checked({   $script:autoCheckSelfUpdate = $true;  Save-Settings })
(Find "ToggleAutoCheckSelfUpdate").Add_Unchecked({ $script:autoCheckSelfUpdate = $false; Save-Settings })

# ── Use dev branch for updates toggle ────────────────────────────
(Find "ToggleUseDevBranch").Add_Checked({
    $script:useDevBranch = $true
    Save-Settings
    if ($selfUpdateStatusText) {
        $selfUpdateStatusText.Text       = "Switched to dev branch - check again"
        $selfUpdateStatusText.Foreground = $window.Resources["MutedText"]
        if ($btnInstallSelfUpdate) { $btnInstallSelfUpdate.Visibility = "Collapsed" }
    }
})
(Find "ToggleUseDevBranch").Add_Unchecked({
    $script:useDevBranch = $false
    Save-Settings
    if ($selfUpdateStatusText) {
        $selfUpdateStatusText.Text       = "Switched to main branch - check again"
        $selfUpdateStatusText.Foreground = $window.Resources["MutedText"]
        if ($btnInstallSelfUpdate) { $btnInstallSelfUpdate.Visibility = "Collapsed" }
    }
})

# ── Remember window position toggle ──────────────────────────────
(Find "ToggleRememberPosition").Add_Checked({   $script:rememberWindowPosition = $true;  Save-Settings })
(Find "ToggleRememberPosition").Add_Unchecked({ $script:rememberWindowPosition = $false; Save-Settings })

# ── Auto-fetch icons toggle (positive label maps to NOT $disableAutoIconFetch) ──
(Find "ToggleDisableAutoIconFetch").IsChecked = (-not $script:disableAutoIconFetch)
(Find "ToggleDisableAutoIconFetch").Add_Checked({   $script:disableAutoIconFetch = $false; Save-Settings })
(Find "ToggleDisableAutoIconFetch").Add_Unchecked({ $script:disableAutoIconFetch = $true;  Save-Settings })

# ── Skip splash toggle ───────────────────────────────────────────
(Find "ToggleSkipSplash").IsChecked = $script:skipSplash
(Find "ToggleSkipSplash").Add_Checked({   $script:skipSplash = $true;  Save-Settings })
(Find "ToggleSkipSplash").Add_Unchecked({ $script:skipSplash = $false; Save-Settings })

# ── Enable notifications toggle ──────────────────────────────────
(Find "ToggleEnableNotifications").IsChecked = $script:enableNotifications
(Find "ToggleEnableNotifications").Add_Checked({   $script:enableNotifications = $true;  Save-Settings })
(Find "ToggleEnableNotifications").Add_Unchecked({ $script:enableNotifications = $false; Save-Settings })

# ── Debug log toggle + open log ──────────────────────────────────
(Find "ToggleEnableLogging").IsChecked = $script:enableLogging
(Find "ToggleEnableLogging").Add_Checked({
    $script:enableLogging = $true
    Save-Settings
    if (Get-Command Write-ScyLog -ErrorAction SilentlyContinue) { Write-ScyLog "Logging enabled" }
})
(Find "ToggleEnableLogging").Add_Unchecked({
    if (Get-Command Write-ScyLog -ErrorAction SilentlyContinue) { Write-ScyLog "Logging disabled" }
    $script:enableLogging = $false
    Save-Settings
})
(Find "BtnOpenLog").Add_Click({
    $logPath = Join-Path $env:LOCALAPPDATA "Scy\scy.log"
    if (Test-Path $logPath) {
        Start-Process notepad.exe -ArgumentList $logPath
    } else {
        Show-ThemedDialog "No log file yet. Enable 'Write a debug log', then reproduce the issue." "Debug log" "OK" "Information"
    }
})

# ── Skip single-uninstall confirm toggle ─────────────────────────
(Find "ToggleSkipSingleUninstallConfirm").IsChecked = $script:skipSingleUninstallConfirm
(Find "ToggleSkipSingleUninstallConfirm").Add_Checked({   $script:skipSingleUninstallConfirm = $true;  Save-Settings })
(Find "ToggleSkipSingleUninstallConfirm").Add_Unchecked({ $script:skipSingleUninstallConfirm = $false; Save-Settings })

# ── Default Apps sub-tab ─────────────────────────────────────────
$defaultAppsSubTabBox = Find "DefaultAppsSubTabBox"
switch ($script:defaultAppsSubTab) {
    "Installed" { $defaultAppsSubTabBox.SelectedIndex = 1 }
    "Updates"   { $defaultAppsSubTabBox.SelectedIndex = 2 }
    default     { $defaultAppsSubTabBox.SelectedIndex = 0 }
}
$defaultAppsSubTabBox.Add_SelectionChanged({
    param($s, $e)
    $sel = if ($s.SelectedItem) { [string]$s.SelectedItem.Content } else { "Store" }
    $script:defaultAppsSubTab = $sel
    Save-Settings
})

# ── Default top-level tab on launch ──────────────────────────────
$defaultTabBox = Find "DefaultTabBox"
$tabOrder = @("Apps", "Tweaks", "System", "Bookmarks", "Network", "Active Directory", "Tools", "Settings")
$idx = $tabOrder.IndexOf($script:defaultTab)
if ($idx -lt 0) { $idx = 0 }
$defaultTabBox.SelectedIndex = $idx
$defaultTabBox.Add_SelectionChanged({
    param($s, $e)
    $sel = if ($s.SelectedItem) { [string]$s.SelectedItem.Content } else { "Apps" }
    $script:defaultTab = $sel
    Save-Settings
})

(Find "ToggleRememberCleanTargets").Add_Checked({   $script:rememberCleanTargets = $true;  Save-Settings })
(Find "ToggleRememberCleanTargets").Add_Unchecked({ $script:rememberCleanTargets = $false; Save-Settings })

(Find "ToggleScanLocalInstallers").Add_Checked({   $script:autoScanLocalInstallers = $true;  Save-Settings })
(Find "ToggleScanLocalInstallers").Add_Unchecked({ $script:autoScanLocalInstallers = $false; Save-Settings })

(Find "ToggleRememberLocalInstallers").Add_Checked({
    $script:rememberLocalInstallers = $true
    Save-Settings
})
(Find "ToggleRememberLocalInstallers").Add_Unchecked({
    $script:rememberLocalInstallers = $false
    $script:cachedLocalInstallers   = @()
    Save-Settings
})

# ── Local installer file extensions ──────────────────────────
$localExtPanel = Find "LocalExtensionsPanel"
$localExtBox   = Find "LocalExtBox"
$localExtPlaceholder = Find "LocalExtPlaceholder"

function Render-LocalExtensions {
    $localExtPanel.Children.Clear()
    foreach ($ext in $script:localInstallerExtensions) {
        $chip = New-Object System.Windows.Controls.Button
        $chip.Content     = "$ext  x"
        $chip.Style       = $window.Resources["QuickAppButton"]
        $chip.Tag         = $ext
        $chip.ToolTip     = "Click to remove $ext"
        $chip.Add_Click({
            $extToRemove = $this.Tag
            $script:localInstallerExtensions.Remove($extToRemove)
            Save-Settings
            Render-LocalExtensions
        })
        $localExtPanel.Children.Add($chip) | Out-Null
    }
}

# Deferred to first Settings-tab visit (Invoke-ScyTabInit in Scy.ps1).
# Render-LocalExtensions

$localExtBox.Add_TextChanged({
    $localExtPlaceholder.Visibility = if ($localExtBox.Text) { "Collapsed" } else { "Visible" }
})

$localExtBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return) {
        (Find "BtnAddLocalExt").RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    }
})

(Find "BtnAddLocalExt").Add_Click({
    $raw = $localExtBox.Text.Trim().ToLower()
    if (-not $raw) { return }
    if (-not $raw.StartsWith('.')) { $raw = ".$raw" }
    if ($script:localInstallerExtensions -contains $raw) {
        $localExtBox.Text = ""
        return
    }
    $script:localInstallerExtensions.Add($raw)
    $localExtBox.Text = ""
    Save-Settings
    Render-LocalExtensions
})

# ── Scy self-update ──────────────────────────────────────────────
$script:versionFile = Join-Path $PSScriptRoot "..\version.json"
$script:localVersion = @{ version = "unknown" }
if (Test-Path $script:versionFile) {
    try {
        $script:localVersion = Get-Content $script:versionFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {}
}

$selfUpdateVersionLabel = Find "SelfUpdateVersionLabel"
$selfUpdateStatusText   = Find "SelfUpdateStatusText"
$btnCheckSelfUpdate     = Find "BtnCheckSelfUpdate"
$btnInstallSelfUpdate   = Find "BtnInstallSelfUpdate"

$selfUpdateVersionLabel.Text = "Version: $($script:localVersion.version)"
$script:latestVersion = $null

$btnCheckSelfUpdate.Add_Click({
    $selfUpdateStatusText.Text       = "Checking..."
    $selfUpdateStatusText.Foreground = $window.Resources["WarningBrush"]
    $btnInstallSelfUpdate.Visibility = "Collapsed"
    $btnCheckSelfUpdate.IsEnabled    = $false
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

    try {
        $branch = if ($script:useDevBranch) { "dev" } else { "main" }
        $remoteJson = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/0x89-y/Scy/$branch/version.json" `
                                        -Headers @{ "User-Agent" = "Scy-Updater" } `
                                        -TimeoutSec 15
        $script:latestVersion = $remoteJson.version

        if ([version]$script:latestVersion -le [version]$script:localVersion.version) {
            $selfUpdateStatusText.Text       = "Up to date"
            $selfUpdateStatusText.Foreground = $window.Resources["SuccessBrush"]
        } else {
            $selfUpdateStatusText.Text       = "Update available  (v$($script:latestVersion))"
            $selfUpdateStatusText.Foreground = $window.Resources["WarningBrush"]
            $btnInstallSelfUpdate.Visibility = "Visible"
        }
    } catch {
        $selfUpdateStatusText.Text       = "Could not check for updates"
        $selfUpdateStatusText.Foreground = $window.Resources["DangerBrush"]
    }

    $btnCheckSelfUpdate.IsEnabled = $true
})

$btnInstallSelfUpdate.Add_Click({
    $confirm = Show-ThemedDialog "Download and install the latest version of Scy?`nYour settings will be preserved." "Update Scy" "YesNo" "Question"
    if ($confirm -ne "Yes") { return }

    if (Get-Command Write-ScyLog -ErrorAction SilentlyContinue) { Write-ScyLog "Self-update started (target v$($script:latestVersion))" }
    $btnInstallSelfUpdate.IsEnabled = $false
    $btnCheckSelfUpdate.IsEnabled   = $false
    $selfUpdateStatusText.Text       = "Downloading update..."
    $selfUpdateStatusText.Foreground = $window.Resources["WarningBrush"]
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

    try {
        $branch  = if ($script:useDevBranch) { "dev" } else { "main" }
        $zipUrl  = "https://github.com/0x89-y/Scy/archive/refs/heads/$branch.zip"
        $zipPath = Join-Path $env:TEMP "Scy-update.zip"
        $extPath = Join-Path $env:TEMP "Scy-update"

        # Clean up any previous update artifacts
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
        if (Test-Path $extPath) { Remove-Item $extPath -Recurse -Force }

        # Download
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 60

        $selfUpdateStatusText.Text = "Installing update..."
        $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

        # Extract
        Expand-Archive -Path $zipPath -DestinationPath $extPath -Force

        # The ZIP extracts to a Scy-<branch>/ subfolder
        $sourceDir = Join-Path $extPath "Scy-$branch"
        $targetDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

        # Copy files, preserving settings.json
        Get-ChildItem -Path $sourceDir -Recurse -File | ForEach-Object {
            $relativePath = $_.FullName.Substring($sourceDir.Length + 1)
            # Skip settings.json and notes.txt to preserve user data
            if ($relativePath -eq "settings.json") { return }
            if ($relativePath -eq "notes.txt") { return }
            $destFile = Join-Path $targetDir $relativePath
            $destDir  = Split-Path $destFile -Parent
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Copy-Item $_.FullName -Destination $destFile -Force
        }

        # Remove unnecessary files (LICENSE, README, install script)
        Get-ChildItem -Path $targetDir -File | Where-Object { $_.Name -match '^(LICENSE|README|install\.ps1)' } | ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }

        # Clean up temp files
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item $extPath -Recurse -Force -ErrorAction SilentlyContinue

        # Re-read the new version.json
        if (Test-Path $script:versionFile) {
            try {
                $script:localVersion = Get-Content $script:versionFile -Raw -Encoding UTF8 | ConvertFrom-Json
                $selfUpdateVersionLabel.Text = "Version: $($script:localVersion.version)"
            } catch {}
        }

        $selfUpdateStatusText.Text       = "Updated successfully"
        $selfUpdateStatusText.Foreground = $window.Resources["SuccessBrush"]
        $btnInstallSelfUpdate.Visibility = "Collapsed"
        if (Get-Command Write-ScyLog -ErrorAction SilentlyContinue) { Write-ScyLog "Self-update completed (now v$($script:localVersion.version))" }

        Show-ThemedDialog "Scy has been updated to the latest version.`nPlease restart Scy to apply changes." "Update complete" "OK" "Information"
    } catch {
        $selfUpdateStatusText.Text       = "Update failed: $_"
        $selfUpdateStatusText.Foreground = $window.Resources["DangerBrush"]
        if (Get-Command Write-ScyLog -ErrorAction SilentlyContinue) { Write-ScyLog "Self-update FAILED: $($_.Exception.Message)" "ERROR" }
    }

    $btnInstallSelfUpdate.IsEnabled = $true
    $btnCheckSelfUpdate.IsEnabled   = $true
})

# ── Changelog ────────────────────────────────────────────────────
# Reads changelog.json from the app root and renders one card per version.
# Deferred to first Settings-tab visit (Invoke-ScyTabInit in Scy.ps1).
$script:changelogFile = Join-Path $PSScriptRoot "..\changelog.json"
function Render-Changelog {
    $panel = Find "ChangelogPanel"
    if (-not $panel) { return }
    $panel.Children.Clear()

    $entries = $null
    if (Test-Path $script:changelogFile) {
        try { $entries = Get-Content $script:changelogFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    }

    if (-not $entries -or @($entries).Count -eq 0) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text       = "No changelog available."
        $empty.FontSize   = 12
        $empty.TextWrapping = "Wrap"
        $empty.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
        $panel.Children.Add($empty) | Out-Null
        return
    }

    foreach ($entry in @($entries)) {
        $card = New-Object System.Windows.Controls.Border
        # cy-design divided list: one flush entry per release, hairline between.
        $card.Background = [System.Windows.Media.Brushes]::Transparent
        $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
        $card.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
        $card.CornerRadius    = [System.Windows.CornerRadius]::new(0)
        $card.Padding         = [System.Windows.Thickness]::new(2, 12, 2, 12)
        $card.Margin          = [System.Windows.Thickness]::new(0)

        $stack = New-Object System.Windows.Controls.StackPanel

        # Header: version (accent) + date (muted)
        $headerRow             = New-Object System.Windows.Controls.DockPanel
        $verBlock              = New-Object System.Windows.Controls.TextBlock
        $verBlock.Text         = "v" + [string]$entry.version
        $verBlock.FontSize     = 13
        $verBlock.FontWeight   = [System.Windows.FontWeights]::SemiBold
        $verBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "AccentBrush")
        $headerRow.Children.Add($verBlock) | Out-Null

        if ($entry.date) {
            $dateBlock              = New-Object System.Windows.Controls.TextBlock
            $dateBlock.Text         = [string]$entry.date
            $dateBlock.FontSize     = 11
            $dateBlock.HorizontalAlignment = "Right"
            $dateBlock.VerticalAlignment   = "Center"
            $dateBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
            [System.Windows.Controls.DockPanel]::SetDock($dateBlock, [System.Windows.Controls.Dock]::Right)
            $headerRow.Children.Add($dateBlock) | Out-Null
        }
        $stack.Children.Add($headerRow) | Out-Null

        # Change bullets
        foreach ($change in @($entry.changes)) {
            $row             = New-Object System.Windows.Controls.DockPanel
            $row.Margin      = [System.Windows.Thickness]::new(0, 6, 0, 0)
            $bullet          = New-Object System.Windows.Controls.TextBlock
            $bullet.Text     = [char]0x2022   # bullet dot
            $bullet.FontSize = 12
            $bullet.Margin   = [System.Windows.Thickness]::new(0, 0, 8, 0)
            $bullet.VerticalAlignment = "Top"
            $bullet.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
            [System.Windows.Controls.DockPanel]::SetDock($bullet, [System.Windows.Controls.Dock]::Left)
            $row.Children.Add($bullet) | Out-Null

            $txt             = New-Object System.Windows.Controls.TextBlock
            $txt.Text        = [string]$change
            $txt.FontSize    = 12
            $txt.TextWrapping = "Wrap"
            $txt.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
            $row.Children.Add($txt) | Out-Null

            $stack.Children.Add($row) | Out-Null
        }

        $card.Child = $stack
        $panel.Children.Add($card) | Out-Null
    }
}

# ── Settings backup - export / import ────────────────────────────
(Find "BtnExportSettings").Add_Click({
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter           = "JSON backup (*.json)|*.json"
    $dlg.FileName         = "scy-settings-backup.json"
    $dlg.InitialDirectory = [System.Environment]::GetFolderPath("Desktop")
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            Save-Settings
            Copy-Item $script:settingsFile -Destination $dlg.FileName -Force
            Show-ThemedDialog "Settings exported to:`n$($dlg.FileName)" "Export complete" "OK" "Information"
        } catch {
            Show-ThemedDialog "Export failed:`n$_" "Export failed" "OK" "Error"
        }
    }
})

(Find "BtnImportSettings").Add_Click({
    Add-Type -AssemblyName System.Windows.Forms
    $dlg        = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "JSON backup (*.json)|*.json"
    $dlg.Title  = "Import settings backup"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $imported = Get-Content $dlg.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $imported.ThemeMode -and $null -eq $imported.Theme) {
                Show-ThemedDialog "This does not appear to be a valid Scy settings file." "Import failed" "OK" "Warning"
                return
            }

            if ($imported.LocalInstallFolder) { $script:localInstallFolder = $imported.LocalInstallFolder }
            if ($imported.ThemeMode)  { $script:themeMode  = [string]$imported.ThemeMode }
            elseif ($imported.Theme)  { $script:themeMode  = if ([string]$imported.Theme -in @("Blossom","Frost")) { "Light" } else { "Dark" } }
            if ($imported.Accent)     { $script:accentName = [string]$imported.Accent }
            elseif ($null -ne $imported.UseWindowsAccent -and [bool]$imported.UseWindowsAccent) { $script:accentName = "windows" }
            if ($imported.CustomAccent -and [string]$imported.CustomAccent -match '^#[0-9a-fA-F]{6}$') { $script:customAccent = [string]$imported.CustomAccent }
            elseif ($imported.CustomTheme -and $imported.CustomTheme.Accent -match '^#[0-9a-fA-F]{6}$') { $script:customAccent = [string]$imported.CustomTheme.Accent }
            if ($null -ne $imported.AutoCheckUpdates)   { $script:autoCheckUpdates   = [bool]$imported.AutoCheckUpdates }
            if ($null -ne $imported.AutoCheckSelfUpdate)  { $script:autoCheckSelfUpdate = [bool]$imported.AutoCheckSelfUpdate }
            if ($null -ne $imported.UseDevBranch)         { $script:useDevBranch        = [bool]$imported.UseDevBranch }
            if ($null -ne $imported.RememberWindowPosition) { $script:rememberWindowPosition = [bool]$imported.RememberWindowPosition }
            if ($imported.SpeedTestServer)              { $script:speedTestServer    = [string]$imported.SpeedTestServer }
            if ($null -ne $imported.QuickInstalls) {
                $script:quickInstalls.Clear()
                foreach ($qi in $imported.QuickInstalls) {
                    $cat = if ($qi.Category) { [string]$qi.Category } else { "" }
                    $script:quickInstalls.Add(@{Name=$qi.Name; Id=$qi.Id; Category=$cat})
                }
            }
            if ($null -ne $imported.QuickBundles) {
                $script:quickBundles.Clear()
                foreach ($b in $imported.QuickBundles) {
                    $apps = [System.Collections.Generic.List[hashtable]]::new()
                    if ($b.Apps) {
                        foreach ($a in $b.Apps) { $apps.Add(@{Name=[string]$a.Name; Id=[string]$a.Id}) }
                    }
                    $desc = if ($b.Description) { [string]$b.Description } else { "" }
                    $script:quickBundles.Add(@{Name=[string]$b.Name; Description=$desc; Apps=$apps})
                }
            }

            if ($null -ne $imported.CustomShortcutGroups) {
                $script:customShortcutGroups.Clear()
                foreach ($g in $imported.CustomShortcutGroups) { $script:customShortcutGroups.Add([string]$g) }
            }
            if ($null -ne $imported.CustomInstallCategories) {
                $script:customInstallCategories.Clear()
                foreach ($g in $imported.CustomInstallCategories) { $script:customInstallCategories.Add([string]$g) }
            }
            if ($null -ne $imported.HiddenDefaultShortcutGroups) {
                $script:hiddenDefaultShortcutGroups.Clear()
                foreach ($g in $imported.HiddenDefaultShortcutGroups) { $script:hiddenDefaultShortcutGroups.Add([string]$g) }
            }
            if ($null -ne $imported.HiddenDefaultInstallCategories) {
                $script:hiddenDefaultInstallCategories.Clear()
                foreach ($g in $imported.HiddenDefaultInstallCategories) { $script:hiddenDefaultInstallCategories.Add([string]$g) }
            }
            if ($null -ne $imported.HiddenCuratedApps) {
                $script:hiddenCuratedApps.Clear()
                foreach ($h in $imported.HiddenCuratedApps) { $script:hiddenCuratedApps.Add([string]$h) }
            }
            if ($null -ne $imported.RememberCleanTargets) { $script:rememberCleanTargets = [bool]$imported.RememberCleanTargets }
            if ($null -ne $imported.AutoScanLocalInstallers) { $script:autoScanLocalInstallers = [bool]$imported.AutoScanLocalInstallers }
            if ($null -ne $imported.RememberLocalInstallers) { $script:rememberLocalInstallers = [bool]$imported.RememberLocalInstallers }
            if ($null -ne $imported.LocalInstallerExtensions) {
                $script:localInstallerExtensions.Clear()
                foreach ($ext in $imported.LocalInstallerExtensions) { $script:localInstallerExtensions.Add([string]$ext) }
            }
            if ($null -ne $imported.CleanTargetSelection) {
                $script:cleanTargetSelection = @{}
                foreach ($prop in $imported.CleanTargetSelection.PSObject.Properties) {
                    $script:cleanTargetSelection[$prop.Name] = [bool]$prop.Value
                }
            }

            (Find "SettingsLocalFolder").Text = $script:localInstallFolder
            (Find "ToggleAutoCheckUpdates").IsChecked = $script:autoCheckUpdates
            (Find "ToggleAutoCheckSelfUpdate").IsChecked = $script:autoCheckSelfUpdate
            (Find "ToggleUseDevBranch").IsChecked = $script:useDevBranch
            (Find "ToggleRememberPosition").IsChecked = $script:rememberWindowPosition
            (Find "ToggleRememberCleanTargets").IsChecked = $script:rememberCleanTargets
            (Find "ToggleScanLocalInstallers").IsChecked = $script:autoScanLocalInstallers
            (Find "ToggleRememberLocalInstallers").IsChecked = $script:rememberLocalInstallers
            Apply-Theme
            Update-LocalInstallers
            Update-QuickInstalls
            Render-GroupSettings
            Save-Settings
            Show-ThemedDialog "Settings imported successfully." "Import complete" "OK" "Information"
        } catch {
            Show-ThemedDialog "Import failed:`n$_" "Import failed" "OK" "Error"
        }
    }
})

# ── Groups management ─────────────────────────────────────────────
function Render-GroupSettings {
    # Refresh disclosure counts so the headers stay in sync after add/remove
    $shortcutCount = $script:defaultShortcutGroups.Count + $script:customShortcutGroups.Count
    $installCount  = $script:defaultQuickCategories.Count + $script:customInstallCategories.Count
    $shortcutLabel = Find "ShortcutGroupsCount"
    $installLabel  = Find "InstallCategoriesCount"
    if ($shortcutLabel) {
        $shortcutLabel.Text = if ($shortcutCount -eq 1) { "1 group" } else { [string]$shortcutCount + " groups" }
    }
    if ($installLabel) {
        $installLabel.Text = if ($installCount -eq 1) { "1 category" } else { [string]$installCount + " categories" }
    }

    # -- Shortcut groups --
    $sgPanel = Find "SettingsShortcutGroupsPanel"
    $sgPanel.Children.Clear()

    foreach ($g in $script:defaultShortcutGroups) {
        $capturedName = $g
        $capturedHiddenList = $script:hiddenDefaultShortcutGroups
        $isHidden = $g -in $capturedHiddenList

        $card = New-Object System.Windows.Controls.Border
        # cy-design divided list: flush row, hairline bottom divider, no fill.
        $card.CornerRadius = [System.Windows.CornerRadius]::new(0)
        $card.Padding = [System.Windows.Thickness]::new(2, 9, 2, 9)
        $card.Margin = [System.Windows.Thickness]::new(0)
        $card.Background = [System.Windows.Media.Brushes]::Transparent
        $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
        $card.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
        if ($isHidden) { $card.Opacity = 0.5 }

        $row = New-Object System.Windows.Controls.Grid
        $rc0 = New-Object System.Windows.Controls.ColumnDefinition; $rc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $rc1 = New-Object System.Windows.Controls.ColumnDefinition; $rc1.Width = [System.Windows.GridLength]::Auto
        $row.ColumnDefinitions.Add($rc0) | Out-Null; $row.ColumnDefinitions.Add($rc1) | Out-Null

        $leftPanel = New-Object System.Windows.Controls.StackPanel
        $leftPanel.Orientation = "Horizontal"; $leftPanel.VerticalAlignment = "Center"
        $dot = New-Object System.Windows.Controls.TextBlock
        $dot.Text = [char]0x25CF; $dot.FontSize = 8; $dot.VerticalAlignment = "Center"
        $dot.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
        $dot.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
        $nameBlock = New-Object System.Windows.Controls.TextBlock
        $nameBlock.Text = $g; $nameBlock.FontSize = 12; $nameBlock.FontWeight = "Medium"
        $nameBlock.VerticalAlignment = "Center"
        $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
        $leftPanel.Children.Add($dot) | Out-Null; $leftPanel.Children.Add($nameBlock) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($leftPanel, 0)

        $rightPanel = New-Object System.Windows.Controls.StackPanel
        $rightPanel.Orientation = "Horizontal"; $rightPanel.VerticalAlignment = "Center"

        $hideBtn = New-Object System.Windows.Controls.Button
        $hideBtn.Content = if ($isHidden) { "Show" } else { "Hide" }
        $hideBtn.Style = $window.Resources["SecondaryButton"]
        $hideBtn.FontSize = 11; $hideBtn.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
        $hideBtn.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
        $hideBtn.Add_Click(({
            if ($capturedName -in $capturedHiddenList) {
                $capturedHiddenList.Remove($capturedName) | Out-Null
            } else {
                $capturedHiddenList.Add($capturedName)
            }
            Save-Settings
            Render-Shortcuts
            Render-GroupSettings
        }.GetNewClosure()))

        $badge = New-Object System.Windows.Controls.Border
        $badge.CornerRadius = [System.Windows.CornerRadius]::new(7)
        $badge.Padding = [System.Windows.Thickness]::new(8, 2, 8, 2)
        $badge.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "Surface2Brush")
        $badgeText = New-Object System.Windows.Controls.TextBlock
        $badgeText.Text = "Default"; $badgeText.FontSize = 10
        $badgeText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
        $badge.Child = $badgeText

        $rightPanel.Children.Add($hideBtn) | Out-Null; $rightPanel.Children.Add($badge) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($rightPanel, 1)

        $row.Children.Add($leftPanel) | Out-Null; $row.Children.Add($rightPanel) | Out-Null
        $card.Child = $row
        $sgPanel.Children.Add($card) | Out-Null
    }

    foreach ($g in @($script:customShortcutGroups)) {
        $capturedName = $g
        $capturedShortcutGroups = $script:customShortcutGroups
        $capturedDefaultGroups  = $script:defaultShortcutGroups
        $capturedShortcuts      = $script:shortcuts

        $card = New-Object System.Windows.Controls.Border
        # cy-design divided list: flush row, hairline bottom divider, no fill.
        $card.CornerRadius = [System.Windows.CornerRadius]::new(0)
        $card.Padding = [System.Windows.Thickness]::new(2, 9, 2, 9)
        $card.Margin = [System.Windows.Thickness]::new(0)
        $card.Background = [System.Windows.Media.Brushes]::Transparent
        $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
        $card.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)

        $row = New-Object System.Windows.Controls.Grid
        $rc0 = New-Object System.Windows.Controls.ColumnDefinition; $rc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $rc1 = New-Object System.Windows.Controls.ColumnDefinition; $rc1.Width = [System.Windows.GridLength]::Auto
        $row.ColumnDefinitions.Add($rc0) | Out-Null; $row.ColumnDefinitions.Add($rc1) | Out-Null

        $leftPanel = New-Object System.Windows.Controls.StackPanel
        $leftPanel.Orientation = "Horizontal"; $leftPanel.VerticalAlignment = "Center"
        $dot = New-Object System.Windows.Controls.TextBlock
        $dot.Text = [char]0x25CF; $dot.FontSize = 8; $dot.VerticalAlignment = "Center"
        $dot.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
        $dot.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "AccentBrush")
        $nameBlock = New-Object System.Windows.Controls.TextBlock
        $nameBlock.Text = $g; $nameBlock.FontSize = 12; $nameBlock.FontWeight = "Medium"
        $nameBlock.VerticalAlignment = "Center"
        $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
        $leftPanel.Children.Add($dot) | Out-Null; $leftPanel.Children.Add($nameBlock) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($leftPanel, 0)

        $rightPanel = New-Object System.Windows.Controls.StackPanel
        $rightPanel.Orientation = "Horizontal"; $rightPanel.VerticalAlignment = "Center"

        $renameBtn = New-Object System.Windows.Controls.Button
        $renameBtn.Content = "Rename"; $renameBtn.Style = $window.Resources["SecondaryButton"]
        $renameBtn.FontSize = 11; $renameBtn.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
        $renameBtn.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
        $renameBtn.Add_Click(({
            Ensure-VisualBasic; $newName = [Microsoft.VisualBasic.Interaction]::InputBox("Rename '$capturedName' to:", "Rename Group", $capturedName)
            if ([string]::IsNullOrWhiteSpace($newName) -or $newName.Trim() -eq $capturedName) { return }
            $newName = $newName.Trim()
            $allExisting = @($capturedDefaultGroups) + @($capturedShortcutGroups)
            if ($newName -in $allExisting) {
                Show-ThemedDialog "A group named '$newName' already exists." "Duplicate" "OK" "Warning"
                return
            }
            $idx = $capturedShortcutGroups.IndexOf($capturedName)
            if ($idx -ge 0) { $capturedShortcutGroups[$idx] = $newName }
            foreach ($sc in $capturedShortcuts) {
                if ($sc.Section -eq $capturedName) { $sc.Section = $newName }
            }
            Save-ShortcutsToSettings
            Render-Shortcuts
            Render-GroupSettings
        }.GetNewClosure()))

        $deleteBtn = New-Object System.Windows.Controls.Button
        $deleteBtn.Content = "Delete"; $deleteBtn.Style = $window.Resources["SecondaryButton"]
        $deleteBtn.FontSize = 11; $deleteBtn.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
        $deleteBtn.Foreground = $window.Resources["DangerBrush"]
        $deleteBtn.Add_Click(({
            $dlgResult = Show-ThemedDialog "Delete group '$capturedName'? Shortcuts in this group will be moved to 'Custom'." "Confirm delete" "YesNo" "Question"
            if ($dlgResult -ne "Yes") { return }
            $capturedShortcutGroups.Remove($capturedName) | Out-Null
            foreach ($sc in $capturedShortcuts) {
                if ($sc.Section -eq $capturedName) { $sc.Section = "Custom" }
            }
            Save-ShortcutsToSettings
            Render-Shortcuts
            Render-GroupSettings
        }.GetNewClosure()))

        $rightPanel.Children.Add($renameBtn) | Out-Null; $rightPanel.Children.Add($deleteBtn) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($rightPanel, 1)

        $row.Children.Add($leftPanel) | Out-Null; $row.Children.Add($rightPanel) | Out-Null
        $card.Child = $row
        $sgPanel.Children.Add($card) | Out-Null
    }

    # -- Install groups --
    $icPanel = Find "SettingsInstallCategoriesPanel"
    $icPanel.Children.Clear()

    foreach ($g in $script:defaultQuickCategories) {
        $capturedName = $g
        $capturedHiddenList = $script:hiddenDefaultInstallCategories
        $isHidden = $g -in $capturedHiddenList

        $card = New-Object System.Windows.Controls.Border
        # cy-design divided list: flush row, hairline bottom divider, no fill.
        $card.CornerRadius = [System.Windows.CornerRadius]::new(0)
        $card.Padding = [System.Windows.Thickness]::new(2, 9, 2, 9)
        $card.Margin = [System.Windows.Thickness]::new(0)
        $card.Background = [System.Windows.Media.Brushes]::Transparent
        $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
        $card.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
        if ($isHidden) { $card.Opacity = 0.5 }

        $row = New-Object System.Windows.Controls.Grid
        $rc0 = New-Object System.Windows.Controls.ColumnDefinition; $rc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $rc1 = New-Object System.Windows.Controls.ColumnDefinition; $rc1.Width = [System.Windows.GridLength]::Auto
        $row.ColumnDefinitions.Add($rc0) | Out-Null; $row.ColumnDefinitions.Add($rc1) | Out-Null

        $leftPanel = New-Object System.Windows.Controls.StackPanel
        $leftPanel.Orientation = "Horizontal"; $leftPanel.VerticalAlignment = "Center"
        $dot = New-Object System.Windows.Controls.TextBlock
        $dot.Text = [char]0x25CF; $dot.FontSize = 8; $dot.VerticalAlignment = "Center"
        $dot.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
        $dot.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
        $nameBlock = New-Object System.Windows.Controls.TextBlock
        $nameBlock.Text = $g; $nameBlock.FontSize = 12; $nameBlock.FontWeight = "Medium"
        $nameBlock.VerticalAlignment = "Center"
        $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
        $leftPanel.Children.Add($dot) | Out-Null; $leftPanel.Children.Add($nameBlock) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($leftPanel, 0)

        $rightPanel = New-Object System.Windows.Controls.StackPanel
        $rightPanel.Orientation = "Horizontal"; $rightPanel.VerticalAlignment = "Center"

        $hideBtn = New-Object System.Windows.Controls.Button
        $hideBtn.Content = if ($isHidden) { "Show" } else { "Hide" }
        $hideBtn.Style = $window.Resources["SecondaryButton"]
        $hideBtn.FontSize = 11; $hideBtn.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
        $hideBtn.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
        $hideBtn.Add_Click(({
            if ($capturedName -in $capturedHiddenList) {
                $capturedHiddenList.Remove($capturedName) | Out-Null
            } else {
                $capturedHiddenList.Add($capturedName)
            }
            Save-Settings
            Update-QuickInstalls
            Render-GroupSettings
        }.GetNewClosure()))

        $badge = New-Object System.Windows.Controls.Border
        $badge.CornerRadius = [System.Windows.CornerRadius]::new(7)
        $badge.Padding = [System.Windows.Thickness]::new(8, 2, 8, 2)
        $badge.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "Surface2Brush")
        $badgeText = New-Object System.Windows.Controls.TextBlock
        $badgeText.Text = "Default"; $badgeText.FontSize = 10
        $badgeText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
        $badge.Child = $badgeText

        $rightPanel.Children.Add($hideBtn) | Out-Null; $rightPanel.Children.Add($badge) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($rightPanel, 1)

        $row.Children.Add($leftPanel) | Out-Null; $row.Children.Add($rightPanel) | Out-Null
        $card.Child = $row
        $icPanel.Children.Add($card) | Out-Null
    }

    foreach ($g in @($script:customInstallCategories)) {
        $capturedName = $g
        $capturedInstallCategories  = $script:customInstallCategories
        $capturedDefaultCategories  = $script:defaultQuickCategories
        $capturedQuickInstalls      = $script:quickInstalls

        $card = New-Object System.Windows.Controls.Border
        # cy-design divided list: flush row, hairline bottom divider, no fill.
        $card.CornerRadius = [System.Windows.CornerRadius]::new(0)
        $card.Padding = [System.Windows.Thickness]::new(2, 9, 2, 9)
        $card.Margin = [System.Windows.Thickness]::new(0)
        $card.Background = [System.Windows.Media.Brushes]::Transparent
        $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
        $card.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)

        $row = New-Object System.Windows.Controls.Grid
        $rc0 = New-Object System.Windows.Controls.ColumnDefinition; $rc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $rc1 = New-Object System.Windows.Controls.ColumnDefinition; $rc1.Width = [System.Windows.GridLength]::Auto
        $row.ColumnDefinitions.Add($rc0) | Out-Null; $row.ColumnDefinitions.Add($rc1) | Out-Null

        $leftPanel = New-Object System.Windows.Controls.StackPanel
        $leftPanel.Orientation = "Horizontal"; $leftPanel.VerticalAlignment = "Center"
        $dot = New-Object System.Windows.Controls.TextBlock
        $dot.Text = [char]0x25CF; $dot.FontSize = 8; $dot.VerticalAlignment = "Center"
        $dot.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
        $dot.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "AccentBrush")
        $nameBlock = New-Object System.Windows.Controls.TextBlock
        $nameBlock.Text = $g; $nameBlock.FontSize = 12; $nameBlock.FontWeight = "Medium"
        $nameBlock.VerticalAlignment = "Center"
        $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
        $leftPanel.Children.Add($dot) | Out-Null; $leftPanel.Children.Add($nameBlock) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($leftPanel, 0)

        $rightPanel = New-Object System.Windows.Controls.StackPanel
        $rightPanel.Orientation = "Horizontal"; $rightPanel.VerticalAlignment = "Center"

        $renameBtn = New-Object System.Windows.Controls.Button
        $renameBtn.Content = "Rename"; $renameBtn.Style = $window.Resources["SecondaryButton"]
        $renameBtn.FontSize = 11; $renameBtn.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
        $renameBtn.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
        $renameBtn.Add_Click(({
            Ensure-VisualBasic; $newName = [Microsoft.VisualBasic.Interaction]::InputBox("Rename '$capturedName' to:", "Rename Category", $capturedName)
            if ([string]::IsNullOrWhiteSpace($newName) -or $newName.Trim() -eq $capturedName) { return }
            $newName = $newName.Trim()
            $allExisting = @($capturedDefaultCategories) + @($capturedInstallCategories)
            if ($newName -in $allExisting) {
                Show-ThemedDialog "A category named '$newName' already exists." "Duplicate" "OK" "Warning"
                return
            }
            $idx = $capturedInstallCategories.IndexOf($capturedName)
            if ($idx -ge 0) { $capturedInstallCategories[$idx] = $newName }
            foreach ($qi in $capturedQuickInstalls) {
                if ($qi.Category -eq $capturedName) { $qi.Category = $newName }
            }
            Save-Settings
            Update-QuickInstalls
            Render-GroupSettings
        }.GetNewClosure()))

        $deleteBtn = New-Object System.Windows.Controls.Button
        $deleteBtn.Content = "Delete"; $deleteBtn.Style = $window.Resources["SecondaryButton"]
        $deleteBtn.FontSize = 11; $deleteBtn.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
        $deleteBtn.Foreground = $window.Resources["DangerBrush"]
        $deleteBtn.Add_Click(({
            $dlgResult = Show-ThemedDialog "Delete category '$capturedName'? Apps in this category will become uncategorized." "Confirm delete" "YesNo" "Question"
            if ($dlgResult -ne "Yes") { return }
            $capturedInstallCategories.Remove($capturedName) | Out-Null
            foreach ($qi in $capturedQuickInstalls) {
                if ($qi.Category -eq $capturedName) { $qi.Category = "" }
            }
            Save-Settings
            Update-QuickInstalls
            Render-GroupSettings
        }.GetNewClosure()))

        $rightPanel.Children.Add($renameBtn) | Out-Null; $rightPanel.Children.Add($deleteBtn) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($rightPanel, 1)

        $row.Children.Add($leftPanel) | Out-Null; $row.Children.Add($rightPanel) | Out-Null
        $card.Child = $row
        $icPanel.Children.Add($card) | Out-Null
    }
}

# -- Add shortcut group --
(Find "NewShortcutGroupBox").Add_TextChanged({
    (Find "NewShortcutGroupPlaceholder").Visibility = if ($this.Text -eq "") { "Visible" } else { "Collapsed" }
})
(Find "BtnAddShortcutGroup").Add_Click({
    $name = (Find "NewShortcutGroupBox").Text.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $allExisting = @($script:defaultShortcutGroups) + @($script:customShortcutGroups)
    if ($name -in $allExisting) {
        Show-ThemedDialog "A group named '$name' already exists." "Duplicate" "OK" "Warning"
        return
    }
    $script:customShortcutGroups.Add($name)
    Save-Settings
    Render-Shortcuts
    Render-GroupSettings
    (Find "NewShortcutGroupBox").Text = ""
})

# -- Add install category --
(Find "NewInstallCategoryBox").Add_TextChanged({
    (Find "NewInstallCategoryPlaceholder").Visibility = if ($this.Text -eq "") { "Visible" } else { "Collapsed" }
})
(Find "BtnAddInstallCategory").Add_Click({
    $name = (Find "NewInstallCategoryBox").Text.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $allExisting = @($script:defaultQuickCategories) + @($script:customInstallCategories)
    if ($name -in $allExisting) {
        Show-ThemedDialog "A category named '$name' already exists." "Duplicate" "OK" "Warning"
        return
    }
    $script:customInstallCategories.Add($name)
    Save-Settings
    Update-QuickInstalls
    Render-GroupSettings
    (Find "NewInstallCategoryBox").Text = ""
})

# ── Credits ────────────────────────────────────────────────────────
(Find "BtnCreditsGitHub").Add_Click({
    Start-Process "https://github.com/0x89-y/Scy"
})
(Find "BtnCreditsWebsite").Add_Click({
    Start-Process "https://0x89-y.xyz/"
})

# Deferred to first Settings-tab visit (Invoke-ScyTabInit in Scy.ps1); building
# the group/category management cards is the bulk of the old Settings load cost.
# Render-GroupSettings

# ── Settings > Groups disclosure headers (collapsed by default) ───
function Toggle-GroupDisclosure {
    param([System.Windows.Controls.Border]$Header, $Content, $Chevron)
    if ($Content.Visibility -eq "Visible") {
        $Content.Visibility = "Collapsed"
        $Chevron.Text       = [string][char]0x25B8   # right-pointing triangle
    } else {
        $Content.Visibility = "Visible"
        $Chevron.Text       = [string][char]0x25BE   # down-pointing triangle
    }
}

$shortcutGroupsHeader     = Find "ShortcutGroupsHeader"
$shortcutGroupsContent    = Find "ShortcutGroupsContent"
$shortcutGroupsChevron    = Find "ShortcutGroupsChevron"
$installCategoriesHeader  = Find "InstallCategoriesHeader"
$installCategoriesContent = Find "InstallCategoriesContent"
$installCategoriesChevron = Find "InstallCategoriesChevron"

$shortcutGroupsHeader.Add_MouseLeftButtonUp({
    Toggle-GroupDisclosure -Header $shortcutGroupsHeader -Content $shortcutGroupsContent -Chevron $shortcutGroupsChevron
})
$installCategoriesHeader.Add_MouseLeftButtonUp({
    Toggle-GroupDisclosure -Header $installCategoriesHeader -Content $installCategoriesContent -Chevron $installCategoriesChevron
})
