# ── Settings Tab ─────────────────────────────────────────────────

# ── Settings sub-navigation ──────────────────────────────────────
$settingsNavAppearance = Find "SettingsNav_Appearance"
$settingsNavGeneral    = Find "SettingsNav_General"
$settingsNavGroups     = Find "SettingsNav_Groups"
$settingsNavBackup     = Find "SettingsNav_Backup"

$settingsPanelAppearance = Find "SettingsPanel_Appearance"
$settingsPanelGeneral    = Find "SettingsPanel_General"
$settingsPanelGroups     = Find "SettingsPanel_Groups"
$settingsPanelBackup     = Find "SettingsPanel_Backup"

$script:settingsNavButtons = @($settingsNavAppearance, $settingsNavGeneral, $settingsNavGroups, $settingsNavBackup)
$script:settingsPanels     = @($settingsPanelAppearance, $settingsPanelGeneral, $settingsPanelGroups, $settingsPanelBackup)

function Set-SettingsSubNav {
    param([int]$Index)
    for ($i = 0; $i -lt $script:settingsPanels.Count; $i++) {
        $script:settingsPanels[$i].Visibility = if ($i -eq $Index) { "Visible" } else { "Collapsed" }
        $btn = $script:settingsNavButtons[$i]
        if ($i -eq $Index) {
            $btn.Foreground = $window.Resources["FgBrush"]
            $btn.BorderBrush = $window.Resources["AccentBrush"]
        } else {
            $btn.Foreground = $window.Resources["MutedText"]
            $btn.BorderBrush = $window.Resources["BorderBrush"]
        }
    }
}

Set-SettingsSubNav 0

$settingsNavAppearance.Add_Click({ Set-SettingsSubNav 0 })
$settingsNavGeneral.Add_Click({    Set-SettingsSubNav 1 })
$settingsNavGroups.Add_Click({     Set-SettingsSubNav 2 })
$settingsNavBackup.Add_Click({     Set-SettingsSubNav 3 })

$script:settingsFile = Join-Path $PSScriptRoot "..\settings.json"
$script:settings = @{}
$script:customShortcutGroups    = [System.Collections.Generic.List[string]]::new()
$script:customInstallCategories = [System.Collections.Generic.List[string]]::new()
$script:hiddenDefaultShortcutGroups    = [System.Collections.Generic.List[string]]::new()
$script:hiddenDefaultInstallCategories = [System.Collections.Generic.List[string]]::new()

# ── Theme definitions ─────────────────────────────────────────────
$script:themes = [ordered]@{
    Custom = @{
        WindowBg  = "#2e2e42"
        AppBg     = "#0a0a0f"
        Accent    = "#6c5ce7"
        Surface   = "#13131a"
        Surface2  = "#1a1a24"
        Border    = "#2a2a3a"
        MutedText = "#6b6b80"
        FgBrush   = "#e0e0e8"
        Success   = "#00b894"
        Warning   = "#fdcb6e"
        Danger    = "#e17055"
    }
    Aether = @{
        WindowBg     = "#2e2e42"
        AppBg        = "#0a0a0f"
        Accent       = "#6c5ce7"
        AccentHover  = "#7f70f0"
        Surface      = "#13131a"
        Surface2     = "#1a1a24"
        Border       = "#2a2a3a"
        MutedText    = "#6b6b80"
        FgBrush      = "#e0e0e8"
        SubText      = "#c0c0d0"
        WinCtrlFg    = "#9090a8"
        ScrollThumb  = "#3a3a52"
        InputBg      = "#0d0d16"
        HoverSurface = "#1e1e2e"
        Success      = "#00b894"
        Warning      = "#fdcb6e"
        Danger       = "#e17055"
    }
    Midnight = @{
        WindowBg     = "#1a1f2e"
        AppBg        = "#080c14"
        Accent       = "#4d9cf6"
        AccentHover  = "#6ab0ff"
        Surface      = "#0d1117"
        Surface2     = "#161b22"
        Border       = "#30363d"
        MutedText    = "#656d76"
        FgBrush      = "#e6edf3"
        SubText      = "#b1bac4"
        WinCtrlFg    = "#8b949e"
        ScrollThumb  = "#30363d"
        InputBg      = "#0a0e16"
        HoverSurface = "#161b22"
        Success      = "#3fb950"
        Warning      = "#d29922"
        Danger       = "#f85149"
    }
    Blossom = @{
        WindowBg     = "#ede8f8"
        AppBg        = "#f8f5ff"
        Accent       = "#6c5ce7"
        AccentHover  = "#7f70f0"
        Surface      = "#ffffff"
        Surface2     = "#f0ebfa"
        Border       = "#d4cce8"
        MutedText    = "#8c84a8"
        FgBrush      = "#2e2842"
        SubText      = "#4a4466"
        WinCtrlFg    = "#6e6890"
        ScrollThumb  = "#c8bef0"
        InputBg      = "#f8f5ff"
        HoverSurface = "#ede8f8"
        Success      = "#00896e"
        Warning      = "#c07c00"
        Danger       = "#c0392b"
    }
    Frost = @{
        WindowBg     = "#dde6f0"
        AppBg        = "#f1f5f9"
        Accent       = "#2563eb"
        AccentHover  = "#1d4ed8"
        Surface      = "#ffffff"
        Surface2     = "#eef2f8"
        Border       = "#cbd5e1"
        MutedText    = "#64748b"
        FgBrush      = "#1e293b"
        SubText      = "#334155"
        WinCtrlFg    = "#475569"
        ScrollThumb  = "#94a3b8"
        InputBg      = "#f8fafc"
        HoverSurface = "#e2e8f0"
        Success      = "#059669"
        Warning      = "#d97706"
        Danger       = "#dc2626"
    }
}

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

function script:Apply-Theme {
    param([string]$ThemeName)
    $t = $script:themes[$ThemeName]
    if (-not $t) { return }

    # For Custom, derive the 6 auto-computed colors from the 11 primary keys
    if ($ThemeName -eq "Custom") {
        $t = $t.Clone()
        $t["AccentHover"]  = LightenHex $t["Accent"]    20
        $t["InputBg"]      = $t["AppBg"]
        $t["HoverSurface"] = LightenHex $t["Surface2"]  8
        $t["ScrollThumb"]  = LightenHex $t["Border"]    16
        $t["WinCtrlFg"]    = LerpHex    $t["MutedText"] $t["FgBrush"] 0.32
        $t["SubText"]      = LerpHex    $t["MutedText"] $t["FgBrush"] 0.73
    }

    # Replace each resource entry with a new SolidColorBrush (.psobject.BaseObject ensures
    # the actual CLR object is stored, not a PowerShell PSObject wrapper)
    $window.Resources["WindowBgBrush"]     = New-Brush $t.WindowBg
    $window.Resources["AppBgBrush"]        = New-Brush $t.AppBg
    $window.Resources["AccentBrush"]       = New-Brush $t.Accent
    $window.Resources["AccentHoverBrush"]  = New-Brush $t.AccentHover
    $window.Resources["SurfaceBrush"]      = New-Brush $t.Surface
    $window.Resources["Surface2Brush"]     = New-Brush $t.Surface2
    $window.Resources["BorderBrush"]       = New-Brush $t.Border
    $window.Resources["MutedText"]         = New-Brush $t.MutedText
    $window.Resources["FgBrush"]           = New-Brush $t.FgBrush
    $window.Resources["SubTextBrush"]      = New-Brush $t.SubText
    $window.Resources["WinCtrlFgBrush"]    = New-Brush $t.WinCtrlFg
    $window.Resources["ScrollThumbBrush"]  = New-Brush $t.ScrollThumb
    $window.Resources["InputBgBrush"]      = New-Brush $t.InputBg
    $window.Resources["HoverSurfaceBrush"] = New-Brush $t.HoverSurface
    $window.Resources["SuccessBrush"]      = New-Brush $t.Success
    $window.Resources["WarningBrush"]      = New-Brush $t.Warning
    $window.Resources["DangerBrush"]       = New-Brush $t.Danger

    # Window Background/Foreground set directly (root Window element can't use resource refs)
    $window.Background = New-Brush $t.WindowBg
    $window.Foreground = New-Brush $t.FgBrush

    # Highlight the active theme button
    foreach ($name in @("Aether","Midnight","Blossom","Frost","Custom")) {
        $btn = Find "Theme$name"
        if ($btn) {
            if ($name -eq $ThemeName) {
                $btn.BorderBrush = $window.Resources["AccentBrush"]
            } else {
                $btn.BorderBrush = $window.Resources["BorderBrush"]
            }
        }
    }

    # Show/hide custom color editor
    $customEditor = Find "CustomThemeEditor"
    if ($customEditor) {
        $customEditor.Visibility = if ($ThemeName -eq "Custom") {
            [System.Windows.Visibility]::Visible
        } else {
            [System.Windows.Visibility]::Collapsed
        }
        if ($ThemeName -eq "Custom") { Update-CustomSwatches }
    }

    # Show restart banner if theme changed from what was loaded at startup
    $banner = Find "ThemeRestartBanner"
    if ($banner) {
        $banner.Visibility = if ($ThemeName -ne $script:startupTheme) {
            [System.Windows.Visibility]::Visible
        } else {
            [System.Windows.Visibility]::Collapsed
        }
    }

    $script:currentTheme = $ThemeName
    Save-Settings
}

function script:Update-CustomSwatches {
    $t = $script:themes["Custom"]
    foreach ($key in $t.Keys) {
        $swatch = Find "CustomSwatch_$key"
        if ($swatch) { $swatch.Background = New-Brush $t[$key] }
    }
}

# ── Load / Save settings ──────────────────────────────────────────
function Save-Settings {
    try {
        @{
            LocalInstallFolder = $script:localInstallFolder
            Theme              = $script:currentTheme
            CustomTheme        = $script:themes["Custom"]
            AutoCheckUpdates   = $script:autoCheckUpdates
            ConfirmationSounds    = $script:confirmationSounds
            RememberWindowPosition = $script:rememberWindowPosition
            SpeedTestServer    = $script:speedTestServer
            WindowGeometry     = $script:windowGeometry
            QuickInstalls      = @($script:quickInstalls | ForEach-Object { @{Name=$_.Name; Id=$_.Id; Category=$_.Category} })
            QuickBundles       = @($script:quickBundles  | ForEach-Object { @{Name=$_.Name; Description=$_.Description; Apps=@($_.Apps | ForEach-Object { @{Name=$_.Name; Id=$_.Id} })} })
            Shortcuts              = $script:settings.Shortcuts
            CustomShortcutGroups   = @($script:customShortcutGroups)
            CustomInstallCategories = @($script:customInstallCategories)
            HiddenDefaultShortcutGroups    = @($script:hiddenDefaultShortcutGroups)
            HiddenDefaultInstallCategories = @($script:hiddenDefaultInstallCategories)
            RememberCleanTargets           = $script:rememberCleanTargets
            CleanTargetSelection           = $script:cleanTargetSelection
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
$script:currentTheme       = "Aether"
$script:autoCheckUpdates   = $false
$script:confirmationSounds    = $false
$script:rememberWindowPosition = $false
$script:rememberCleanTargets   = $false
$script:cleanTargetSelection   = @{}
$script:windowGeometry     = $null
$script:speedTestServer    = "Hetzner FSN1 (DE)"

if (Test-Path $script:settingsFile) {
    try {
        $saved = Get-Content $script:settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($saved.LocalInstallFolder) { $script:localInstallFolder = $saved.LocalInstallFolder }
        if ($saved.Theme)              { $script:currentTheme = $saved.Theme }
        if ($null -ne $saved.AutoCheckUpdates)   { $script:autoCheckUpdates   = [bool]$saved.AutoCheckUpdates }
        if ($null -ne $saved.ConfirmationSounds)    { $script:confirmationSounds    = [bool]$saved.ConfirmationSounds }
        if ($null -ne $saved.RememberWindowPosition) { $script:rememberWindowPosition = [bool]$saved.RememberWindowPosition }
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
        if ($saved.CustomTheme) {
            foreach ($prop in $saved.CustomTheme.PSObject.Properties) {
                $script:themes["Custom"][$prop.Name] = $prop.Value
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
        if ($null -ne $saved.RememberCleanTargets) { $script:rememberCleanTargets = [bool]$saved.RememberCleanTargets }
        if ($null -ne $saved.CleanTargetSelection) {
            $script:cleanTargetSelection = @{}
            foreach ($prop in $saved.CleanTargetSelection.PSObject.Properties) {
                $script:cleanTargetSelection[$prop.Name] = [bool]$prop.Value
            }
        }
    } catch {}
}

# Remove stale derived keys from older settings files
foreach ($staleKey in @("AccentHover","SubText","WinCtrlFg","ScrollThumb","InputBg","HoverSurface")) {
    $script:themes["Custom"].Remove($staleKey)
}

(Find "SettingsLocalFolder").Text = $script:localInstallFolder
(Find "ToggleAutoCheckUpdates").IsChecked = $script:autoCheckUpdates
(Find "ToggleConfirmSounds").IsChecked    = $script:confirmationSounds
(Find "ToggleRememberPosition").IsChecked = $script:rememberWindowPosition
(Find "ToggleRememberCleanTargets").IsChecked = $script:rememberCleanTargets
Update-LocalInstallers
Update-QuickInstalls

# Apply the saved/default theme on startup
$script:startupTheme = $script:currentTheme
Apply-Theme $script:currentTheme

# Initialize shortcuts after settings are loaded
Initialize-Shortcuts

# Trigger update check on launch if enabled (deferred until window is rendered)
if ($script:autoCheckUpdates) {
    $window.Dispatcher.BeginInvoke([action]{
        (Find "BtnCheckUpdates").RaiseEvent(
            [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
        )
    }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
}

# ── Theme button handlers ─────────────────────────────────────────
(Find "ThemeAether").Add_Click(   { Apply-Theme "Aether"   })
(Find "ThemeMidnight").Add_Click( { Apply-Theme "Midnight" })
(Find "ThemeBlossom").Add_Click(  { Apply-Theme "Blossom"  })
(Find "ThemeFrost").Add_Click(    { Apply-Theme "Frost"    })
(Find "ThemeCustom").Add_Click(   { Apply-Theme "Custom"   })

# ── Theme restart banner (info only, no auto-restart) ──────────

# ── Custom theme color pick handlers ─────────────────────────────
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing       -ErrorAction SilentlyContinue

$script:customColorKeys = @(
    "WindowBg","AppBg","Accent","Surface","Surface2",
    "Border","MutedText","FgBrush","Success","Warning","Danger"
)

foreach ($colorKey in $script:customColorKeys) {
    $capturedKey = $colorKey
    $handler = {
        $hex = $script:themes["Custom"][$capturedKey]
        $r = [Convert]::ToInt32($hex.Substring(1,2), 16)
        $g = [Convert]::ToInt32($hex.Substring(3,2), 16)
        $b = [Convert]::ToInt32($hex.Substring(5,2), 16)
        $dlg          = New-Object System.Windows.Forms.ColorDialog
        $dlg.FullOpen = $true
        $dlg.Color    = [System.Drawing.Color]::FromArgb($r, $g, $b)
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $c    = $dlg.Color
            $script:themes["Custom"][$capturedKey] = "#{0:X2}{1:X2}{2:X2}" -f $c.R, $c.G, $c.B
            Apply-Theme "Custom"
        }
    }.GetNewClosure()
    (Find "CustomPick_$capturedKey").Add_Click($handler)
}

# ── Custom theme color reset handlers ────────────────────────────
$script:aetherDefaults = $script:themes["Aether"]

foreach ($colorKey in $script:customColorKeys) {
    $capturedKey = $colorKey
    $handler = {
        $script:themes["Custom"][$capturedKey] = $script:aetherDefaults[$capturedKey]
        Apply-Theme "Custom"
    }.GetNewClosure()
    (Find "CustomReset_$capturedKey").Add_Click($handler)
}

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

# ── Confirmation sounds toggle ────────────────────────────────────
(Find "ToggleConfirmSounds").Add_Checked({   $script:confirmationSounds = $true;  Save-Settings })
(Find "ToggleConfirmSounds").Add_Unchecked({ $script:confirmationSounds = $false; Save-Settings })

# ── Remember window position toggle ──────────────────────────────
(Find "ToggleRememberPosition").Add_Checked({   $script:rememberWindowPosition = $true;  Save-Settings })
(Find "ToggleRememberPosition").Add_Unchecked({ $script:rememberWindowPosition = $false; Save-Settings })

(Find "ToggleRememberCleanTargets").Add_Checked({   $script:rememberCleanTargets = $true;  Save-Settings })
(Find "ToggleRememberCleanTargets").Add_Unchecked({ $script:rememberCleanTargets = $false; Save-Settings })

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
        $remoteJson = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/0x89-y/Scy/main/version.json" `
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

    $btnInstallSelfUpdate.IsEnabled = $false
    $btnCheckSelfUpdate.IsEnabled   = $false
    $selfUpdateStatusText.Text       = "Downloading update..."
    $selfUpdateStatusText.Foreground = $window.Resources["WarningBrush"]
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

    try {
        $zipUrl  = "https://github.com/0x89-y/Scy/archive/refs/heads/main.zip"
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

        # The ZIP extracts to Scy-main/ subfolder
        $sourceDir = Join-Path $extPath "Scy-main"
        $targetDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

        # Copy files, preserving settings.json
        Get-ChildItem -Path $sourceDir -Recurse -File | ForEach-Object {
            $relativePath = $_.FullName.Substring($sourceDir.Length + 1)
            # Skip settings.json to preserve user settings
            if ($relativePath -eq "settings.json") { return }
            $destFile = Join-Path $targetDir $relativePath
            $destDir  = Split-Path $destFile -Parent
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Copy-Item $_.FullName -Destination $destFile -Force
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

        Show-ThemedDialog "Scy has been updated to the latest version.`nPlease restart Scy to apply changes." "Update complete" "OK" "Information"
    } catch {
        $selfUpdateStatusText.Text       = "Update failed: $_"
        $selfUpdateStatusText.Foreground = $window.Resources["DangerBrush"]
    }

    $btnInstallSelfUpdate.IsEnabled = $true
    $btnCheckSelfUpdate.IsEnabled   = $true
})

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

# ── Custom theme export / import ──────────────────────────────────
(Find "BtnExportTheme").Add_Click({
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter           = "Scy theme (*.scytheme)|*.scytheme|JSON (*.json)|*.json"
    $dlg.FileName         = "my-theme.scytheme"
    $dlg.InitialDirectory = [System.Environment]::GetFolderPath("Desktop")
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $export = @{ ScyTheme = "1.0" }
            foreach ($key in $script:themes["Custom"].Keys) { $export[$key] = $script:themes["Custom"][$key] }
            $export | ConvertTo-Json | Set-Content -Path $dlg.FileName -Encoding UTF8
            Show-ThemedDialog "Theme exported to:`n$($dlg.FileName)" "Export complete" "OK" "Information"
        } catch {
            Show-ThemedDialog "Export failed:`n$_" "Export failed" "OK" "Error"
        }
    }
})

(Find "BtnImportTheme").Add_Click({
    Add-Type -AssemblyName System.Windows.Forms
    $dlg        = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Scy theme (*.scytheme)|*.scytheme|JSON (*.json)|*.json"
    $dlg.Title  = "Import theme"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $imported = Get-Content $dlg.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $imported.ScyTheme) {
                Show-ThemedDialog "This does not appear to be a valid Scy theme file." "Import failed" "OK" "Warning"
                return
            }
            $validKeys = @("WindowBg","AppBg","Accent","Surface","Surface2","Border","MutedText","FgBrush","Success","Warning","Danger")
            foreach ($key in $validKeys) {
                if ($imported.PSObject.Properties[$key]) {
                    $script:themes["Custom"][$key] = $imported.$key
                }
            }
            Apply-Theme "Custom"
            Show-ThemedDialog "Theme imported successfully." "Import complete" "OK" "Information"
        } catch {
            Show-ThemedDialog "Import failed:`n$_" "Import failed" "OK" "Error"
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
            if ($null -eq $imported.Theme) {
                Show-ThemedDialog "This does not appear to be a valid Scy settings file." "Import failed" "OK" "Warning"
                return
            }

            if ($imported.LocalInstallFolder) { $script:localInstallFolder = $imported.LocalInstallFolder }
            if ($imported.Theme)              { $script:currentTheme = $imported.Theme }
            if ($null -ne $imported.AutoCheckUpdates)   { $script:autoCheckUpdates   = [bool]$imported.AutoCheckUpdates }
            if ($null -ne $imported.ConfirmationSounds)    { $script:confirmationSounds    = [bool]$imported.ConfirmationSounds }
            if ($null -ne $imported.RememberWindowPosition) { $script:rememberWindowPosition = [bool]$imported.RememberWindowPosition }
            if ($imported.SpeedTestServer)              { $script:speedTestServer    = [string]$imported.SpeedTestServer }
            if ($imported.CustomTheme) {
                foreach ($prop in $imported.CustomTheme.PSObject.Properties) {
                    $script:themes["Custom"][$prop.Name] = $prop.Value
                }
            }
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
            if ($null -ne $imported.RememberCleanTargets) { $script:rememberCleanTargets = [bool]$imported.RememberCleanTargets }
            if ($null -ne $imported.CleanTargetSelection) {
                $script:cleanTargetSelection = @{}
                foreach ($prop in $imported.CleanTargetSelection.PSObject.Properties) {
                    $script:cleanTargetSelection[$prop.Name] = [bool]$prop.Value
                }
            }

            foreach ($staleKey in @("AccentHover","SubText","WinCtrlFg","ScrollThumb","InputBg","HoverSurface")) {
                $script:themes["Custom"].Remove($staleKey)
            }

            (Find "SettingsLocalFolder").Text = $script:localInstallFolder
            (Find "ToggleAutoCheckUpdates").IsChecked = $script:autoCheckUpdates
            (Find "ToggleConfirmSounds").IsChecked    = $script:confirmationSounds
            (Find "ToggleRememberPosition").IsChecked = $script:rememberWindowPosition
            (Find "ToggleRememberCleanTargets").IsChecked = $script:rememberCleanTargets
            Apply-Theme $script:currentTheme
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
    # -- Shortcut groups --
    $sgPanel = Find "SettingsShortcutGroupsPanel"
    $sgPanel.Children.Clear()

    foreach ($g in $script:defaultShortcutGroups) {
        $capturedName = $g
        $capturedHiddenList = $script:hiddenDefaultShortcutGroups
        $isHidden = $g -in $capturedHiddenList

        $card = New-Object System.Windows.Controls.Border
        $card.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $card.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
        $card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
        $card.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "InputBgBrush")
        $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
        $card.BorderThickness = [System.Windows.Thickness]::new(1)
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
        $badge.CornerRadius = [System.Windows.CornerRadius]::new(3)
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
        $card.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $card.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
        $card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
        $card.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "InputBgBrush")
        $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
        $card.BorderThickness = [System.Windows.Thickness]::new(1)

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
            $newName = [Microsoft.VisualBasic.Interaction]::InputBox("Rename '$capturedName' to:", "Rename Group", $capturedName)
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
            $dlgResult = Show-ThemedDialog "Delete group '$capturedName'? Shortcuts in this group will be moved to 'Custom'." "Confirm Delete" "YesNo" "Question"
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
        $card.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $card.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
        $card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
        $card.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "InputBgBrush")
        $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
        $card.BorderThickness = [System.Windows.Thickness]::new(1)
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
        $badge.CornerRadius = [System.Windows.CornerRadius]::new(3)
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
        $card.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $card.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
        $card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
        $card.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "InputBgBrush")
        $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
        $card.BorderThickness = [System.Windows.Thickness]::new(1)

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
            $newName = [Microsoft.VisualBasic.Interaction]::InputBox("Rename '$capturedName' to:", "Rename Category", $capturedName)
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
            $dlgResult = Show-ThemedDialog "Delete category '$capturedName'? Packages in this category will become uncategorized." "Confirm Delete" "YesNo" "Question"
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

Render-GroupSettings
