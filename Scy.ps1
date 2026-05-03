#Requires -Version 5.1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ── Lazy-load Microsoft.VisualBasic (only needed for InputBox dialogs) ──
$script:vbLoaded = $false
function Ensure-VisualBasic {
    if (-not $script:vbLoaded) {
        Add-Type -AssemblyName Microsoft.VisualBasic
        $script:vbLoaded = $true
    }
}

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

# Read theme from settings early so the splash matches the user's theme
$aether = $script:BuiltinThemes["Aether"]
$script:splashColors = @{ AppBg = $aether.AppBg; Border = $aether.Border; Fg = $aether.FgBrush; Muted = $aether.MutedText }
$settingsPath = Join-Path $PSScriptRoot "settings.json"
if (Test-Path $settingsPath) {
    try {
        $earlySettings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($earlySettings.Theme -eq "Custom" -and $earlySettings.CustomTheme) {
            $ct = $earlySettings.CustomTheme
            if ($ct.AppBg -and $ct.Border -and $ct.FgBrush -and $ct.MutedText) {
                $script:splashColors = @{ AppBg = $ct.AppBg; Border = $ct.Border; Fg = $ct.FgBrush; Muted = $ct.MutedText }
            }
        } elseif ($earlySettings.Theme -and $script:BuiltinThemes[$earlySettings.Theme]) {
            $t = $script:BuiltinThemes[$earlySettings.Theme]
            $script:splashColors = @{ AppBg = $t.AppBg; Border = $t.Border; Fg = $t.FgBrush; Muted = $t.MutedText }
        }
    } catch {}
}

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

# ── Named controls ───────────────────────────────────────────────
$statusIndicator = Find "StatusIndicator"
$footerStatus    = Find "FooterStatus"
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
function Start-ScyJob {
    param(
        [Parameter(Mandatory)][scriptblock]$Work,
        [scriptblock]$OnLine,
        [scriptblock]$OnComplete,
        [hashtable]$Variables = @{},
        [hashtable]$Context   = @{},
        [switch]$ReturnHandle
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
    if ($ReturnHandle) {
        return [pscustomobject]@{ PS = $ps; RS = $rs; Handle = $handle }
    }
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

# ── Helper: run a user scriptblock off the UI thread, stream output ───
function Run-Command {
    param(
        [System.Windows.Controls.TextBox]$OutputBox,
        [scriptblock]$ScriptBlock,
        [string]$Label,
        [string]$StatusText = "Running..."
    )

    $statusIndicator.Text       = "● $StatusText"
    $statusIndicator.Foreground = $window.Resources["WarningBrush"]
    $footerStatus.Text          = "Scy - $StatusText"

    Write-Output-Box $OutputBox "`r`n▶ Running: $Label`r`n$('─' * 60)" -Clear

    Start-ScyJob `
        -Variables @{ userCode = $ScriptBlock.ToString() } `
        -Context   @{ Box = $OutputBox } `
        -Work {
            param($emit)
            $sb  = [scriptblock]::Create($userCode)
            $out = & $sb 2>&1 | Out-String
            & $emit $out
        } `
        -OnLine {
            param($line, $ctx)
            $ctx.Box.AppendText($line)
            $ctx.Box.ScrollToEnd()
        } `
        -OnComplete {
            param($result, $err, $ctx)
            if ($err) {
                $ctx.Box.AppendText("`r`n✖ Error: $err`r`n")
            } else {
                $ctx.Box.AppendText("`r`n✔ Done.`r`n")
            }
            $ctx.Box.ScrollToEnd()
            $statusIndicator.Text       = "● Ready"
            $statusIndicator.Foreground = $window.Resources["SuccessBrush"]
            $footerStatus.Text          = "Ready"
        } | Out-Null
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
    $outerBorder.CornerRadius    = [System.Windows.CornerRadius]::new(8)
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

# ══════════════════════════════════════════════════════════════════
#  TAB HANDLERS
# ══════════════════════════════════════════════════════════════════
$script:splashStatus = "Loading packages"
Pump-Splash
. (Join-Path $PSScriptRoot "Helpers\Helpers-Cards.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Updates.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Installs.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Uninstall.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Tweaks.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Settings.ps1")
$script:splashStatus = "Loading system"
Pump-Splash
. (Join-Path $PSScriptRoot "Tabs\Tab-Info.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Battery.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Firmware.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Cleanup.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-SfcDism.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Shortcuts.ps1")
$script:splashStatus = "Loading network"
Pump-Splash
. (Join-Path $PSScriptRoot "Tabs\Tab-RegBookmarks.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Network.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-ActiveDirectory.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Hosts.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-SSH.ps1")
. (Join-Path $PSScriptRoot "Tabs\QRCode.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-QRCode.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Notes.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Export.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-FileHash.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-PasswordGen.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-GlobalSearch.ps1")
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

# ── Startup ──────────────────────────────────────────────────────
$psVersion.Text = "$($PSVersionTable.PSVersion)"

# Reuse version already read for splash
(Find "AppVersion").Text = $splashVersion

# Single admin check, reused by the button handler
$script:isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

(Find "BtnRunAsAdmin").Add_Click({
    if ($script:isAdmin) {
        Show-ThemedDialog "Already running as Administrator!" "Info" "OK" "Information"
    } else {
        Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        $window.Close()
    }
})

if ($script:isAdmin) {
    $window.Title = "Scy [Administrator]"
    (Find "BtnRunAsAdmin").Content   = "Admin (active)"
    (Find "BtnRunAsAdmin").IsEnabled = $false
}

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

$window.ShowDialog() | Out-Null
