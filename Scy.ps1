#Requires -Version 5.1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

# ── XAML UI Definition ──────────────────────────────────────────
$xamlString = Get-Content -Path (Join-Path $PSScriptRoot "Scy.xaml") -Raw -Encoding UTF8

# ── Build the Window ────────────────────────────────────────────
$window = [Windows.Markup.XamlReader]::Parse($xamlString)

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

# ── Helper: run a command async-ish (keeps UI responsive-ish) ───
function Run-Command {
    param(
        [System.Windows.Controls.TextBox]$OutputBox,
        [scriptblock]$ScriptBlock,
        [string]$Label,
        [string]$StatusText = "Running..."
    )
    $statusIndicator.Text = "● $StatusText"
    $statusIndicator.Foreground = $window.Resources["WarningBrush"]
    $footerStatus.Text = "Scy - $StatusText"
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

    Write-Output-Box $OutputBox "`r`n▶ Running: $Label`r`n$('─' * 60)" -Clear
    try {
        $result = & $ScriptBlock 2>&1 | Out-String
        Write-Output-Box $OutputBox $result
        Write-Output-Box $OutputBox "`r`n✔ Done."
    } catch {
        Write-Output-Box $OutputBox "`r`n✖ Error: $_"
    }

    $statusIndicator.Text = "● Ready"
    $statusIndicator.Foreground = $window.Resources["SuccessBrush"]
    $footerStatus.Text = "Ready"
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
. (Join-Path $PSScriptRoot "Tabs\Tab-Updates.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Installs.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Uninstall.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Tweaks.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Settings.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Info.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Battery.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Firmware.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Cleanup.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Shortcuts.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-RegBookmarks.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Network.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Hosts.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-SSH.ps1")
. (Join-Path $PSScriptRoot "Tabs\QRCode.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-QRCode.ps1")
. (Join-Path $PSScriptRoot "Tabs\Tab-Notes.ps1")

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

# ── Run as Admin ─────────────────────────────────────────────────
(Find "BtnRunAsAdmin").Add_Click({
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Show-ThemedDialog "Already running as Administrator!" "Info" "OK" "Information"
    } else {
        Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        $window.Close()
    }
})

# ── Startup ──────────────────────────────────────────────────────
$psVersion.Text = "$($PSVersionTable.PSVersion)"

# Set app version from version.json
$appVersionRun = Find "AppVersion"
$versionJsonPath = Join-Path $PSScriptRoot "version.json"
if (Test-Path $versionJsonPath) {
    try {
        $vInfo = Get-Content $versionJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $appVersionRun.Text = "Scy v$($vInfo.version)"
    } catch { $appVersionRun.Text = "Scy" }
} else { $appVersionRun.Text = "Scy" }

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
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

# ── Show the window ─────────────────────────────────────────────
$window.ShowDialog() | Out-Null
