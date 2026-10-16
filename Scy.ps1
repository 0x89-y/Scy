#Requires -Version 5.1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ── Splash Screen ─────────────────────────────────────────────
$splashVersion = "Scy"
$splashVersionPath = Join-Path $PSScriptRoot "version.json"
if (Test-Path $splashVersionPath) {
    try {
        $sv = Get-Content $splashVersionPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $splashVersion = "Scy v$($sv.version)"
    } catch {}
}

# Load shared theme palette (also used by Tab-Settings.ps1 at runtime)
. (Join-Path $PSScriptRoot "Themes.ps1")

# ── User data folder ─────────────────────────────────────────────
# Settings and notes live in %APPDATA%\Scy, apart from the program files, so
# installs, self-updates and reinstalls can never touch them (and they roam
# with the Windows profile). Older versions kept them next to Scy.ps1; move
# them over once. A file already in the data folder always wins.
$script:dataDir = Join-Path $env:APPDATA "Scy"
if (-not (Test-Path $script:dataDir)) { New-Item -ItemType Directory -Path $script:dataDir -Force | Out-Null }
foreach ($__f in @("settings.json", "notes.txt")) {
    $__old = Join-Path $PSScriptRoot $__f
    $__new = Join-Path $script:dataDir $__f
    if ((Test-Path -LiteralPath $__old) -and -not (Test-Path -LiteralPath $__new)) {
        try { Move-Item -LiteralPath $__old -Destination $__new -ErrorAction Stop } catch {}
    }
}

# Read theme from settings early so the splash matches the user's theme.
# cy-design model: mode (System/Light/Dark) picks the base; accent is separate
# and doesn't affect the splash's neutral colours.
$script:skipSplash = $false
$script:enableLogging = $false
$earlyMode = "System"
$settingsPath = Join-Path $script:dataDir "settings.json"
if (Test-Path $settingsPath) {
    try {
        $earlySettings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $earlySettings.SkipSplash)     { $script:skipSplash    = [bool]$earlySettings.SkipSplash }
        if ($null -ne $earlySettings.EnableLogging)  { $script:enableLogging = [bool]$earlySettings.EnableLogging }
        if ($earlySettings.ThemeMode) {
            $earlyMode = [string]$earlySettings.ThemeMode
        } elseif ($earlySettings.Theme) {
            # Back-compat: map old named themes to a mode.
            $earlyMode = if ($earlySettings.Theme -in @("Blossom","Frost")) { "Light" } else { "Dark" }
        }
    } catch {}
}
$t = $script:BuiltinThemes[(Resolve-ThemeMode $earlyMode)]
$script:splashColors = @{ AppBg = $t.AppBg; Border = $t.Border; Fg = $t.FgBrush; Muted = $t.MutedText }

# ── Optional debug log (Settings > General > Write a debug log; off by default) ──
# Defined early so startup/tab-load events can be logged. The toggle is mirrored
# into $script:enableLogging by Tab-Settings once it loads.
$script:logFile = Join-Path $env:LOCALAPPDATA "Scy\scy.log"
function Write-ScyLog {
    param([string]$Message, [string]$Level = "INFO")
    if (-not $script:enableLogging) { return }
    try {
        $dir = Split-Path $script:logFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $line = ("{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message)
        Add-Content -Path $script:logFile -Value $line -Encoding UTF8
    } catch {}
}
Write-ScyLog "Scy starting (v$($splashVersion -replace '^Scy v?',''))"

$splash = $null
if (-not $script:skipSplash) {

$splash = New-Object System.Windows.Window
$splash.WindowStyle         = "None"
$splash.ResizeMode          = "NoResize"
$splash.Width               = 400
$splash.Height              = 220
$splash.WindowStartupLocation = "CenterScreen"
$splash.AllowsTransparency  = $true
$splash.Background          = [System.Windows.Media.Brushes]::Transparent
$splash.Topmost             = $true
$splash.ShowInTaskbar       = $false

$splashBorder = New-Object System.Windows.Controls.Border
$splashBorder.Background      = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($script:splashColors.AppBg)))
$splashBorder.BorderBrush     = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($script:splashColors.Border)))
$splashBorder.BorderThickness = [System.Windows.Thickness]::new(1)
$splashBorder.CornerRadius    = [System.Windows.CornerRadius]::new(12)

$splashGrid = New-Object System.Windows.Controls.Grid
$r0 = New-Object System.Windows.Controls.RowDefinition; $r0.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
$r1 = New-Object System.Windows.Controls.RowDefinition; $r1.Height = [System.Windows.GridLength]::Auto
$r2 = New-Object System.Windows.Controls.RowDefinition; $r2.Height = [System.Windows.GridLength]::Auto
$splashGrid.RowDefinitions.Add($r0)
$splashGrid.RowDefinitions.Add($r1)
$splashGrid.RowDefinitions.Add($r2)

$splashTitle            = New-Object System.Windows.Controls.TextBlock
$splashTitle.Text       = "Scy"
$splashTitle.FontSize   = 38
$splashTitle.FontWeight = [System.Windows.FontWeights]::Light
$splashTitle.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($script:splashColors.Fg)))
$splashTitle.HorizontalAlignment = "Center"
$splashTitle.VerticalAlignment   = "Bottom"
[System.Windows.Controls.Grid]::SetRow($splashTitle, 0)

$splashVer            = New-Object System.Windows.Controls.TextBlock
$splashVer.Text       = $splashVersion
$splashVer.FontSize   = 12
$splashVer.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($script:splashColors.Muted)))
$splashVer.HorizontalAlignment = "Center"
$splashVer.Margin     = [System.Windows.Thickness]::new(0, 4, 0, 0)
[System.Windows.Controls.Grid]::SetRow($splashVer, 1)

$splashLoading            = New-Object System.Windows.Controls.TextBlock
$splashLoading.Text       = "Loading..."
$splashLoading.FontSize   = 13
$splashLoading.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($script:splashColors.Muted)))
$splashLoading.HorizontalAlignment = "Center"
$splashLoading.Margin     = [System.Windows.Thickness]::new(0, 24, 0, 30)
[System.Windows.Controls.Grid]::SetRow($splashLoading, 2)

$splashGrid.Children.Add($splashTitle)   | Out-Null
$splashGrid.Children.Add($splashVer)     | Out-Null
$splashGrid.Children.Add($splashLoading) | Out-Null
$splashBorder.Child = $splashGrid
$splash.Content     = $splashBorder

# Animated dots timer with status text
$script:splashDotState = 0
$script:splashStatus   = "Loading"
$splashTimer = New-Object System.Windows.Threading.DispatcherTimer
$splashTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$splashTimer.Add_Tick({
    $script:splashDotState = ($script:splashDotState + 1) % 4
    $dots = "." * $script:splashDotState
    $splashLoading.Text = "$($script:splashStatus)$dots"
})
$splashTimer.Start()

$splash.Show()
} # end if (-not $script:skipSplash)

function Pump-Splash {
    if ($splash -and $splash.IsVisible) {
        $splash.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    }
}

try {

# ── XAML UI Definition ──────────────────────────────────────────
$script:splashStatus = "Loading UI"
$xamlString = Get-Content -Path (Join-Path $PSScriptRoot "Scy.xaml") -Raw -Encoding UTF8
Pump-Splash

# ── Build the Window ────────────────────────────────────────────
$window = [Windows.Markup.XamlReader]::Parse($xamlString)
Pump-Splash

# ── Helper: find named elements ─────────────────────────────────
function Find($name) { $window.FindName($name) }

# ── Missing admin rights ─────────────────────────────────────────
# Scy never checks up front whether it is elevated (antivirus heuristics flag
# that pattern). Admin-only actions simply try, and when Windows refuses we
# recognise the failure here and tell the user.
#
# Language-independent: matches on exception types / error codes, never on the
# (localized) message text.
function Test-ScyAccessDenied {
    param($ErrorRecord)
    if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
        if ($ErrorRecord.CategoryInfo.Category -eq 'PermissionDenied') { return $true }   # CIM cmdlets (DNS, TPM, ...)
        $ex = $ErrorRecord.Exception
    } else {
        $ex = $ErrorRecord
    }
    while ($ex) {
        if ($ex -is [System.UnauthorizedAccessException]) { return $true }
        if ($ex -is [System.Security.SecurityException]) { return $true }                # .NET registry writes
        if ($ex -is [System.ComponentModel.Win32Exception] -and $ex.NativeErrorCode -in 5, 740) { return $true }   # access denied / elevation required
        if ($ex.HResult -eq -2147024891) { return $true }                                # 0x80070005 E_ACCESSDENIED
        if ($ex.PSObject.Properties['NativeErrorCode'] -and [string]$ex.NativeErrorCode -eq 'AccessDenied') { return $true }
        $ex = $ex.InnerException
    }
    return $false
}

# ── winget exit codes ────────────────────────────────────────────
# Maps winget's documented return codes to readable text. Ok = the package ends
# up in the requested state (e.g. "already installed" counts as a success).
$script:wingetExitCodes = @{
    "8A150010" = @{ Ok = $false; Text = "No installer applies to this system" }
    "8A150011" = @{ Ok = $false; Text = "Installer hash mismatch - the download didn't match the manifest" }
    "8A150014" = @{ Ok = $false; Text = "No package found with that ID" }
    "8A15002B" = @{ Ok = $true;  Text = "Already up to date" }
    "8A150061" = @{ Ok = $true;  Text = "Already installed" }
    "8A150101" = @{ Ok = $false; Text = "The app is running - close it and try again" }
    "8A150102" = @{ Ok = $false; Text = "Another installation is in progress - try again later" }
    "8A150103" = @{ Ok = $false; Text = "A file is in use - close the app and try again" }
    "8A150104" = @{ Ok = $false; Text = "A dependency is missing" }
    "8A150105" = @{ Ok = $false; Text = "Not enough disk space" }
    "8A150106" = @{ Ok = $false; Text = "Not enough memory" }
    "8A150107" = @{ Ok = $false; Text = "No network connection" }
    "8A150109" = @{ Ok = $true;  Text = "Done - restart Windows to finish" }
    "8A15010A" = @{ Ok = $false; Text = "Restart Windows first, then try again" }
    "8A15010C" = @{ Ok = $false; Text = "Cancelled" }
    "8A15010D" = @{ Ok = $true;  Text = "Already installed" }
    "8A15010E" = @{ Ok = $false; Text = "A newer version is already installed" }
    "8A15010F" = @{ Ok = $false; Text = "Blocked by policy" }
}

# Keys are 8-digit hex strings: '{0:X8}' formats the (negative Int32) exit code
# the same way on every PowerShell version, unlike 0x8A15... literals.
function Get-WingetResult {
    param([int]$ExitCode)
    if ($ExitCode -eq 0) { return @{ Ok = $true; Text = "Done" } }
    $hex = '{0:X8}' -f $ExitCode
    if ($script:wingetExitCodes.ContainsKey($hex)) { return $script:wingetExitCodes[$hex] }
    return @{ Ok = $false; Text = "winget exit code 0x$hex" }
}

function Show-AdminRequiredError {
    param([string]$Action)
    Show-ThemedDialog ("$Action requires administrator rights.`n`nClose Scy, then right-click the Scy shortcut and choose 'Run as administrator'.") `
        "Administrator rights required" "OK" "Error" | Out-Null
}

# ── Tab registry ─────────────────────────────────────────────────
# The single place that knows the top-level tabs. Keys are the TabItem headers
# in Scy.xaml; everything (default tab, Global Search, first-visit init) looks
# tabs up by name, so reordering tabs in the XAML can't break anything.
#   SubNav - function that opens a section of the tab by index
#   Init   - functions run the first time the tab is shown (Invoke-ScyTabInit)
$script:scyTabs = [ordered]@{
    "Apps"             = @{ SubNav = "Set-PkgSubNav";       Init = @() }
    "Tweaks"           = @{ SubNav = $null;                 Init = @("Rebuild-TweaksPanel") }
    "System"           = @{ SubNav = "Set-SystemSubNav";    Init = @() }
    "Bookmarks"        = @{ SubNav = "Set-BookmarksSubNav"; Init = @() }
    "Network"          = @{ SubNav = "Set-NetSubNav";       Init = @("Initialize-DnsDohStatus", "Load-HostsEntries", "Populate-SSHKeys") }
    "Active Directory" = @{ SubNav = "Set-AdSubNav";        Init = @("Test-AdEnvironment") }
    "Tools"            = @{ SubNav = "Set-ToolsSubNav";     Init = @() }
    "Settings"         = @{ SubNav = "Set-SettingsSubNav";  Init = @("Build-TabVisibilityList", "Render-LocalExtensions", "Render-GroupSettings", "Render-Changelog") }
}

function Get-ScyTabItem {
    param([string]$Name)
    foreach ($item in (Find "MainTabControl").Items) {
        if ([string]$item.Header -eq $Name) { return $item }
    }
}

# Switch to a top-level tab by name and optionally open one of its sections.
function Select-ScyTab {
    param([string]$Name, $SubNavIndex = $null)
    $item = Get-ScyTabItem $Name
    if (-not $item) { return }
    (Find "MainTabControl").SelectedItem = $item
    $subNav = if ($script:scyTabs.Contains($Name)) { $script:scyTabs[$Name].SubNav } else { $null }
    if ($null -ne $SubNavIndex -and $subNav -and (Get-Command $subNav -ErrorAction SilentlyContinue)) {
        & $subNav $SubNavIndex
    }
}

# ── Named controls ───────────────────────────────────────────────
$script:statusIndicator = Find "StatusIndicator"
$script:footerStatus    = Find "FooterStatus"
$psVersion       = Find "PSVersion"

# ── Helper: append text to an output box ─────────────────────────
function Write-Output-Box {
    param([System.Windows.Controls.TextBox]$Box, [string]$Text, [switch]$Clear)
    if ($Clear) { $Box.Text = "" }
    $Box.AppendText("$Text`r`n")
    $Box.ScrollToEnd()
}

# ── Helper: run work on a background runspace, marshal results to UI ───
# Work runs on a worker thread. OnLine/OnComplete run on the UI thread via
# Dispatcher.Invoke.
#
# Inside Start-ScyJob's OnLine/OnComplete bodies do NOT read $script:
# state via .GetNewClosure(): the worker runspace remaps $script: lookups
# to the closure's scope, breaking shared state. Use -Context (passed as
# the final callback argument), or alias to a local before the closure.
#
# .GetNewClosure() on UI-thread Add_Click / Add_MouseLeftButtonUp handlers
# is fine and idiomatic here, used to capture per-iteration locals (e.g.
# the current $cb / $capturedItem inside a foreach loop). The trap above
# is specific to Start-ScyJob callbacks that try to reach $script: state.
#
# Inside Work, call `& $emit "line"` to push output to the UI.
# Variables hashtable entries become variables in the worker runspace.
#
# Each job gets its own runspace. Finished jobs are disposed by a UI-thread sweep
# (below) rather than from the worker itself, so cleanup never runs inside the
# runspace being torn down.
$script:scyJobs = [System.Collections.Generic.List[object]]::new()
$script:scyJobSweeper = New-Object System.Windows.Threading.DispatcherTimer
$script:scyJobSweeper.Interval = [TimeSpan]::FromSeconds(2)
$script:scyJobSweeper.Add_Tick({
    for ($i = $script:scyJobs.Count - 1; $i -ge 0; $i--) {
        $j = $script:scyJobs[$i]
        if ($j.PS.InvocationStateInfo.State -notin 'Completed', 'Failed', 'Stopped') { continue }
        try { $j.PS.EndInvoke($j.Handle) | Out-Null } catch {}
        try { $j.PS.Dispose() } catch {}
        try { $j.RS.Dispose() } catch {}
        $script:scyJobs.RemoveAt($i)
    }
    if ($script:scyJobs.Count -eq 0) { $script:scyJobSweeper.Stop() }
})

function Start-ScyJob {
    param(
        [Parameter(Mandatory)][scriptblock]$Work,
        [scriptblock]$OnLine,
        [scriptblock]$OnComplete,
        [hashtable]$Variables = @{},
        [hashtable]$Context   = @{}
    )

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions  = 'ReuseThread'
    $rs.Open()

    $rs.SessionStateProxy.SetVariable('__win',     $window)
    $rs.SessionStateProxy.SetVariable('__onLine',  $OnLine)
    $rs.SessionStateProxy.SetVariable('__onDone',  $OnComplete)
    $rs.SessionStateProxy.SetVariable('__ctx',     $Context)
    $rs.SessionStateProxy.SetVariable('__workTxt', $Work.ToString())

    foreach ($k in $Variables.Keys) {
        $rs.SessionStateProxy.SetVariable($k, $Variables[$k])
    }

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript({
        $__result = $null
        $__err    = $null

        $emit = {
            param($line)
            if ($__onLine) {
                $__win.Dispatcher.Invoke(
                    [action]{ & $__onLine $line $__ctx },
                    [System.Windows.Threading.DispatcherPriority]::Normal)
            }
        }

        try {
            $sb = [scriptblock]::Create($__workTxt)
            $__result = & $sb $emit
        } catch { $__err = $_ }

        if ($__onDone) {
            $__win.Dispatcher.Invoke(
                [action]{ & $__onDone $__result $__err $__ctx },
                [System.Windows.Threading.DispatcherPriority]::Normal)
        }
    }) | Out-Null

    $handle = $ps.BeginInvoke()
    $script:scyJobs.Add([pscustomobject]@{ PS = $ps; RS = $rs; Handle = $handle })
    if (-not $script:scyJobSweeper.IsEnabled) { $script:scyJobSweeper.Start() }
}

# ── Progress bar helpers ──────────────────────────────────────────
# Show or update a Border+ProgressBar+Label triplet. Pass $Value = $null
# for indeterminate mode.
function Show-ScyProgress {
    param(
        [Parameter(Mandatory)]$Border,
        [Parameter(Mandatory)]$Bar,
        [Parameter(Mandatory)]$Label,
        [string]$Text = "",
        $Value = $null,
        [int]$Max = 100
    )
    $Border.Visibility = "Visible"
    $Label.Text        = $Text
    $Bar.Maximum       = $Max
    if ($null -eq $Value) {
        $Bar.IsIndeterminate = $true
    } else {
        $Bar.IsIndeterminate = $false
        $Bar.Value           = [double]$Value
    }
}

function Hide-ScyProgress {
    param($Border, $Bar)
    if ($Border) { $Border.Visibility   = "Collapsed" }
    if ($Bar)    { $Bar.IsIndeterminate = $false; $Bar.Value = 0 }
}

# ── Helper: toggle output panel visibility ───────────────────────
function Toggle-Output {
    param([string]$BorderName, [string]$BtnName)
    $border = Find $BorderName
    $btn    = Find $BtnName
    if ($border.Visibility -eq "Visible") {
        $border.Visibility = "Collapsed"
        $btn.Content = "Show output"
    } else {
        $border.Visibility = "Visible"
        $btn.Content = "Hide output"
    }
}

(Find "BtnToggleUpdates").Add_Click(  { Toggle-Output "OutBorderUpdates"   "BtnToggleUpdates"   })

# ── Helper: themed message dialog ─────────────────────────────────
# Replaces [System.Windows.MessageBox]::Show() with a dark-themed window.
# Usage:
#   Show-ThemedDialog "Message text" "Title" "OK"               → always returns "OK"
#   Show-ThemedDialog "Are you sure?" "Confirm" "YesNo"         → returns "Yes" or "No"
#   Show-ThemedDialog "Message" "Title" "OK" "Warning"          → shows ⚠ icon
#   Show-ThemedDialog "Message" "Title" "OK" "Error"            → shows ✖ icon
#   Show-ThemedDialog "Message" "Title" "OK" "Information"      → shows ℹ icon
function Show-ThemedDialog {
    param(
        [string]$Message,
        [string]$Title = "Scy",
        [string]$Buttons = "OK",         # "OK" or "YesNo"
        [string]$Icon    = "None"        # "Warning", "Error", "Information", "None"
    )

    $dlg = New-Object System.Windows.Window
    $dlg.Title               = $Title
    $dlg.WindowStyle         = "None"
    $dlg.ResizeMode          = "NoResize"
    $dlg.SizeToContent       = "WidthAndHeight"
    $dlg.MinWidth            = 360
    $dlg.MaxWidth            = 500
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner               = $window
    $dlg.Background          = $window.Resources["WindowBgBrush"]
    $dlg.Foreground          = $window.Resources["FgBrush"]

    # Allow dragging
    $dlg.Add_MouseLeftButtonDown({ $this.DragMove() })

    # Outer border
    $outerBorder = New-Object System.Windows.Controls.Border
    $outerBorder.BorderBrush     = $window.Resources["BorderBrush"]
    $outerBorder.BorderThickness = [System.Windows.Thickness]::new(1)
    $outerBorder.CornerRadius    = [System.Windows.CornerRadius]::new(16)
    $outerBorder.Background      = $window.Resources["WindowBgBrush"]

    $root = New-Object System.Windows.Controls.StackPanel
    $root.Margin = [System.Windows.Thickness]::new(0)

    # ── Title bar ──
    $titleBar = New-Object System.Windows.Controls.Border
    $titleBar.Background = $window.Resources["SurfaceBrush"]
    $titleBar.Padding    = [System.Windows.Thickness]::new(16, 10, 16, 10)

    $titleGrid = New-Object System.Windows.Controls.Grid
    $tc0 = New-Object System.Windows.Controls.ColumnDefinition
    $tc0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $tc1 = New-Object System.Windows.Controls.ColumnDefinition
    $tc1.Width = [System.Windows.GridLength]::Auto
    $titleGrid.ColumnDefinitions.Add($tc0)
    $titleGrid.ColumnDefinitions.Add($tc1)

    $titleText            = New-Object System.Windows.Controls.TextBlock
    $titleText.Text       = $Title
    $titleText.FontSize   = 13
    $titleText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $titleText.Foreground = $window.Resources["FgBrush"]
    $titleText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.Grid]::SetColumn($titleText, 0)

    $closeBtn = New-Object System.Windows.Controls.Button
    $closeBtn.Content     = [char]0x2715
    $closeBtn.FontSize    = 12
    $closeBtn.FontWeight  = [System.Windows.FontWeights]::Bold
    $closeBtn.Padding     = [System.Windows.Thickness]::new(6, 2, 6, 2)
    $closeBtn.Cursor      = [System.Windows.Input.Cursors]::Hand
    $closeBtn.Style       = $window.Resources["DangerButton"]
    $closeBtn.Foreground  = $window.Resources["DangerBrush"]
    $closeBtn.BorderThickness = [System.Windows.Thickness]::new(0)
    [System.Windows.Controls.Grid]::SetColumn($closeBtn, 1)
    $closeBtn.Add_Click({ $dlg.Tag = "Close"; $dlg.Close() })

    $titleGrid.Children.Add($titleText) | Out-Null
    $titleGrid.Children.Add($closeBtn)  | Out-Null
    $titleBar.Child = $titleGrid

    # ── Body ──
    $body = New-Object System.Windows.Controls.StackPanel
    $body.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $body.Margin      = [System.Windows.Thickness]::new(20, 20, 20, 16)

    # Icon
    $iconText = switch ($Icon) {
        "Warning"     { [char]0x26A0 }
        "Error"       { [char]0x2716 }
        "Information" { [char]0x2139 }
        "Question"    { "?" }
        default       { $null }
    }
    $iconColor = switch ($Icon) {
        "Warning"     { $window.Resources["WarningBrush"] }
        "Error"       { $window.Resources["DangerBrush"] }
        "Information" { $window.Resources["AccentBrush"] }
        "Question"    { $window.Resources["AccentBrush"] }
        default       { $null }
    }
    if ($iconText) {
        $iconBlock            = New-Object System.Windows.Controls.TextBlock
        $iconBlock.Text       = $iconText
        $iconBlock.FontSize   = 24
        $iconBlock.Foreground = $iconColor
        $iconBlock.Margin     = [System.Windows.Thickness]::new(0, 0, 14, 0)
        $iconBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
        $body.Children.Add($iconBlock) | Out-Null
    }

    $msgBlock              = New-Object System.Windows.Controls.TextBlock
    $msgBlock.Text         = $Message
    $msgBlock.FontSize     = 13
    $msgBlock.Foreground   = $window.Resources["FgBrush"]
    $msgBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $msgBlock.MaxWidth     = 380
    $msgBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $body.Children.Add($msgBlock) | Out-Null

    # ── Button row ──
    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation         = [System.Windows.Controls.Orientation]::Horizontal
    $btnPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $btnPanel.Margin              = [System.Windows.Thickness]::new(20, 0, 20, 16)

    if ($Buttons -eq "YesNo") {
        $noBtn         = New-Object System.Windows.Controls.Button
        $noBtn.Content = "No"
        $noBtn.Style   = $window.Resources["SecondaryButton"]
        $noBtn.Padding = [System.Windows.Thickness]::new(20, 7, 20, 7)
        $noBtn.Margin  = [System.Windows.Thickness]::new(0, 0, 8, 0)
        $noBtn.Foreground = $window.Resources["FgBrush"]
        $noBtn.Add_Click({ $dlg.Tag = "No"; $dlg.Close() })

        $yesBtn         = New-Object System.Windows.Controls.Button
        $yesBtn.Content = "Yes"
        $yesBtn.Padding = [System.Windows.Thickness]::new(20, 7, 20, 7)
        $yesBtn.Style      = $window.Resources["ActionButton"]
        $yesBtn.Background = $window.Resources["AccentBrush"]
        $yesBtn.Foreground = [System.Windows.Media.Brushes]::White
        $yesBtn.Add_Click({ $dlg.Tag = "Yes"; $dlg.Close() })

        $btnPanel.Children.Add($yesBtn) | Out-Null
        $btnPanel.Children.Add($noBtn)  | Out-Null
    } else {
        $okBtn         = New-Object System.Windows.Controls.Button
        $okBtn.Content = "OK"
        $okBtn.Style   = $window.Resources["ActionButton"]
        $okBtn.Padding = [System.Windows.Thickness]::new(24, 7, 24, 7)
        $okBtn.Add_Click({ $dlg.Tag = "OK"; $dlg.Close() })
        $btnPanel.Children.Add($okBtn) | Out-Null
    }

    $root.Children.Add($titleBar) | Out-Null
    $root.Children.Add($body)     | Out-Null
    $root.Children.Add($btnPanel) | Out-Null
    $outerBorder.Child = $root
    $dlg.Content = $outerBorder

    $dlg.Tag = if ($Buttons -eq "YesNo") { "No" } else { "OK" }
    $dlg.ShowDialog() | Out-Null

    return $dlg.Tag
}

# ── Helper: themed single-line input dialog ───────────────────────
# Replaces the unthemed VisualBasic InputBox. Returns the entered text, or
# $null when the user cancels (Esc, Cancel or the close button).
function Show-ThemedInput {
    param(
        [string]$Prompt,
        [string]$Title   = "Scy",
        [string]$Default = ""
    )

    $dlg = New-Object System.Windows.Window
    $dlg.Title                 = $Title
    $dlg.WindowStyle           = "None"
    $dlg.ResizeMode            = "NoResize"
    $dlg.SizeToContent         = "Height"
    $dlg.Width                 = 400
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner                 = $window
    $dlg.Background            = $window.Resources["WindowBgBrush"]
    $dlg.Foreground            = $window.Resources["FgBrush"]
    $dlg.Tag                   = $null
    $dlg.Add_MouseLeftButtonDown({ try { $this.DragMove() } catch {} })

    $outer = New-Object System.Windows.Controls.Border
    $outer.BorderBrush     = $window.Resources["BorderBrush"]
    $outer.BorderThickness = [System.Windows.Thickness]::new(1)
    $outer.Background      = $window.Resources["WindowBgBrush"]

    $root = New-Object System.Windows.Controls.StackPanel

    $titleBar = New-Object System.Windows.Controls.Border
    $titleBar.Background = $window.Resources["SurfaceBrush"]
    $titleBar.Padding    = [System.Windows.Thickness]::new(16, 10, 16, 10)
    $titleText            = New-Object System.Windows.Controls.TextBlock
    $titleText.Text       = $Title
    $titleText.FontSize   = 13
    $titleText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $titleText.Foreground = $window.Resources["FgBrush"]
    $titleBar.Child = $titleText

    $body = New-Object System.Windows.Controls.StackPanel
    $body.Margin = [System.Windows.Thickness]::new(20, 16, 20, 12)

    $promptText              = New-Object System.Windows.Controls.TextBlock
    $promptText.Text         = $Prompt
    $promptText.FontSize     = 12
    $promptText.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $promptText.Foreground   = $window.Resources["FgBrush"]
    $promptText.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 8)

    $box = New-Object System.Windows.Controls.TextBox
    $box.Text            = $Default
    $box.FontSize        = 12
    $box.Padding         = [System.Windows.Thickness]::new(6, 5, 6, 5)
    $box.Background      = $window.Resources["InputBgBrush"]
    $box.Foreground      = $window.Resources["FgBrush"]
    $box.CaretBrush      = $window.Resources["FgBrush"]
    $box.BorderBrush     = $window.Resources["BorderStrongBrush"]
    $box.BorderThickness = [System.Windows.Thickness]::new(1)

    $body.Children.Add($promptText) | Out-Null
    $body.Children.Add($box)        | Out-Null

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation         = [System.Windows.Controls.Orientation]::Horizontal
    $btnPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $btnPanel.Margin              = [System.Windows.Thickness]::new(20, 0, 20, 16)

    $okBtn           = New-Object System.Windows.Controls.Button
    $okBtn.Content   = "OK"
    $okBtn.Style     = $window.Resources["ActionButton"]
    $okBtn.Padding   = [System.Windows.Thickness]::new(20, 7, 20, 7)
    $okBtn.Margin    = [System.Windows.Thickness]::new(0, 0, 8, 0)
    $okBtn.IsDefault = $true                          # Enter submits
    $okBtn.Add_Click({ $dlg.Tag = [string]$box.Text; $dlg.Close() })

    $cancelBtn            = New-Object System.Windows.Controls.Button
    $cancelBtn.Content    = "Cancel"
    $cancelBtn.Style      = $window.Resources["SecondaryButton"]
    $cancelBtn.Padding    = [System.Windows.Thickness]::new(20, 7, 20, 7)
    $cancelBtn.Foreground = $window.Resources["FgBrush"]
    $cancelBtn.IsCancel   = $true                      # Esc cancels
    $cancelBtn.Add_Click({ $dlg.Close() })

    $btnPanel.Children.Add($okBtn)     | Out-Null
    $btnPanel.Children.Add($cancelBtn) | Out-Null

    $root.Children.Add($titleBar) | Out-Null
    $root.Children.Add($body)     | Out-Null
    $root.Children.Add($btnPanel) | Out-Null
    $outer.Child = $root
    $dlg.Content = $outer

    $dlg.Add_ContentRendered({ $box.Focus() | Out-Null; $box.SelectAll() })
    $dlg.ShowDialog() | Out-Null
    return $dlg.Tag
}

# ══════════════════════════════════════════════════════════════════
#  TAB HANDLERS
# ══════════════════════════════════════════════════════════════════
$script:splashStatus = "Loading packages"
Pump-Splash

# Order is load-bearing (Helpers + Installs define shared helpers/data used by
# other tabs; GlobalSearch must be last). foreach runs in the current (script)
# scope, so dot-sourcing inside it still defines functions at script scope.
# Heavy per-tab initial work is deferred to first visit (Invoke-ScyTabInit).
$__tabFiles = @(
    "Helpers\Helpers-Cards.ps1"
    "Helpers\Helpers-Rail.ps1"
    "Helpers\Helpers-Status.ps1"
    "Tabs\Tab-Updates.ps1"
    "Tabs\Tab-Installs.ps1"
    "Tabs\Tab-Tweaks.ps1"
    "Tabs\Tab-Settings.ps1"
    "Tabs\Tab-Info.ps1"
    "Tabs\Tab-Battery.ps1"
    "Tabs\Tab-Firmware.ps1"
    "Tabs\Tab-Cleanup.ps1"
    "Tabs\Tab-SfcDism.ps1"
    "Tabs\Tab-Shortcuts.ps1"
    "Tabs\Tab-RegBookmarks.ps1"
    "Tabs\Tab-Network.ps1"
    "Tabs\Tab-ActiveDirectory.ps1"
    "Tabs\Tab-Hosts.ps1"
    "Tabs\Tab-SSH.ps1"
    "Tabs\QRCode.ps1"
    "Tabs\Tab-QRCode.ps1"
    "Tabs\Tab-Notes.ps1"
    "Tabs\Tab-Installed.ps1"
    "Tabs\Tab-FileHash.ps1"
    "Tabs\Tab-PasswordGen.ps1"
    "Tabs\Tab-GlobalSearch.ps1"
)
# Per-tab crash isolation: a parse/runtime error in one module is caught so the
# rest of the app still loads (a broken tab no longer kills startup). try/catch
# does not introduce a new scope, so dot-sourcing inside it still defines the
# module's functions at script scope.
$script:tabLoadErrors = [System.Collections.Generic.List[string]]::new()
# Splash text is keyed to the module that is about to load, not to its position,
# so inserting or reordering a module can't silently mislabel the progress.
$__splashAt = @{
    "Tab-Info.ps1"    = "Loading system"
    "Tab-Network.ps1" = "Loading network"
}
foreach ($__rel in $__tabFiles) {
    $__leaf = Split-Path $__rel -Leaf
    if ($__splashAt.ContainsKey($__leaf)) { $script:splashStatus = $__splashAt[$__leaf]; Pump-Splash }
    try {
        . (Join-Path $PSScriptRoot $__rel)
    } catch {
        $__name = [System.IO.Path]::GetFileNameWithoutExtension($__rel)
        $script:tabLoadErrors.Add("$__name : $($_.Exception.Message)")
        Write-ScyLog "Module failed to load: $__rel -> $($_.Exception.Message)" "ERROR"
    }
}
$script:splashStatus = "Almost ready"
Pump-Splash

# ── Restore saved window geometry ────────────────────────────────
if ($script:rememberWindowPosition -and $script:windowGeometry) {
    $window.Left   = $script:windowGeometry.Left
    $window.Top    = $script:windowGeometry.Top
    $window.Width  = $script:windowGeometry.Width
    $window.Height = $script:windowGeometry.Height
    if ($script:windowGeometry.State -eq "Maximized") { $window.WindowState = "Maximized" }
} else {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $window.Left = ($wa.Width  - $window.Width)  / 2 + $wa.Left
    $window.Top  = ($wa.Height - $window.Height) / 2 + $wa.Top
}

$window.Add_Closing({
    if ($script:rememberWindowPosition) {
        if ($window.WindowState -eq "Normal") {
            $script:windowGeometry = @{ Left=$window.Left; Top=$window.Top; Width=$window.Width; Height=$window.Height; State="Normal" }
        } else {
            $rb = $window.RestoreBounds
            $script:windowGeometry = @{ Left=$rb.Left; Top=$rb.Top; Width=$rb.Width; Height=$rb.Height; State="Maximized" }
        }
    } else {
        $script:windowGeometry = $null
    }
    Save-Settings
})

# ── Window chrome buttons ────────────────────────────────────────
(Find "BtnMinimize").Add_Click({ $window.WindowState = "Minimized" })
(Find "BtnMaximize").Add_Click({
    $window.WindowState = if ($window.WindowState -eq "Maximized") { "Normal" } else { "Maximized" }
})
(Find "BtnClose").Add_Click({ $window.Close() })

# Settings has no tab-strip header; the title-bar cog selects it.
(Find "BtnSettingsCog").Add_Click({ Select-ScyTab "Settings" })

# ── Startup ──────────────────────────────────────────────────────
$psVersion.Text = "$($PSVersionTable.PSVersion)"

# Reuse version already read for splash
(Find "AppVersion").Text = $splashVersion

# ── Update banner click handler (visible from every tab) ───────
(Find "UpdateBanner").Add_MouseLeftButtonDown({
    # Trigger the existing self-update install button in Settings
    (Find "BtnInstallSelfUpdate").RaiseEvent(
        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
    )
})

} catch {
    $errMsg = "Scy failed to start:`n`n$($_.Exception.Message)`n`n$($_.ScriptStackTrace)"
    if ($splashTimer) { $splashTimer.Stop() }
    if ($splash) { $splash.Close(); $splash = $null }
    [System.Windows.MessageBox]::Show($errMsg, "Scy startup error", "OK", "Error") | Out-Null
    throw
} finally {
    # ── Close splash and show the window ──────────────────────────────
    if ($splashTimer) { $splashTimer.Stop() }
    if ($splash) { $splash.Close(); $splash = $null }
}

# ── Deferred per-tab initialization (lazy "first visit" work) ─────────
# Heavy startup work (folder scans, key enumeration, domain/DoH probes) is
# moved off the dot-source critical path and run the first time its owning
# top-level tab is shown (the Init list in $script:scyTabs). Apps and System
# load nothing on entry - their data is fetched on demand.
$script:scyTabInitDone = @{}
function Invoke-ScyTabInit {
    param([string]$Name)
    if (-not $Name -or $script:scyTabInitDone[$Name]) { return }
    $script:scyTabInitDone[$Name] = $true
    $entry = $script:scyTabs[$Name]
    if (-not $entry) { return }
    foreach ($fn in $entry.Init) {
        # Each step is isolated so one failure doesn't skip the rest
        try {
            if (Get-Command $fn -ErrorAction SilentlyContinue) { & $fn }
        } catch {
            Write-ScyLog "First-visit init '$fn' for tab '$Name' failed: $($_.Exception.Message)" "ERROR"
        }
    }
}

$script:mainTabControl = Find "MainTabControl"
$script:mainTabControl.Add_SelectionChanged({
    param($s, $e)
    # SelectionChanged bubbles up from ComboBoxes inside the tabs; only react to the tab control itself.
    if ($e.OriginalSource -ne $s) { return }
    if ($s.SelectedItem) { Invoke-ScyTabInit ([string]$s.SelectedItem.Header) }
})

# ── Apply default top-level tab on launch ────────────────────────────
if ($script:defaultTab) { Select-ScyTab $script:defaultTab }

# Initialize whatever tab we're actually landing on (the default, or the first).
if ($script:mainTabControl.SelectedItem) {
    Invoke-ScyTabInit ([string]$script:mainTabControl.SelectedItem.Header)
}

# Surface any modules that failed to load (crash isolation kept the app alive).
if ($script:tabLoadErrors -and $script:tabLoadErrors.Count -gt 0) {
    $window.Dispatcher.BeginInvoke([action]{
        $list = ($script:tabLoadErrors | ForEach-Object { "  - " + $_ }) -join "`n"
        Show-ThemedDialog ("Some parts of Scy failed to load and were skipped:`n`n" + $list + "`n`nThe rest of the app is working normally.") "Partial load" "OK" "Warning" | Out-Null
    }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
}

$window.ShowDialog() | Out-Null
