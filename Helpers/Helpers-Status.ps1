# Shared status/notification chrome: the footer status line and the in-app toast.
# These live here rather than in a tab module because they belong to the window,
# not to any one tab - Info, Battery, Firmware, Installed and QR all drive them.
# Scy.ps1 defines $statusIndicator/$footerStatus before the tab loop, so this
# module can rely on them being present at load.

# ── Footer status line ───────────────────────────────────────────
function Set-BusyStatus {
    param([string]$Text)
    $statusIndicator.Text       = $Text
    $statusIndicator.Foreground = $window.Resources["WarningBrush"]
    $footerStatus.Text          = "Scy - " + $Text
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Set-ReadyStatus {
    $statusIndicator.Text       = "Ready"
    $statusIndicator.Foreground = $window.Resources["SuccessBrush"]
    $footerStatus.Text          = "Ready"
}

# ── In-app toast (Settings > General > Notify on long operations) ──
# Uses a WPF Border overlay in the main window. The click handler and the
# auto-hide timer are wired ONCE at script load, so neither relies on a
# nested closure SessionState (which silently dropped function-scope lookups).
$global:scyToast       = $window.FindName("ScyToast")
$global:scyToastTitle  = $window.FindName("ScyToastTitle")
$global:scyToastBody   = $window.FindName("ScyToastBody")
$global:scyToastTimer  = New-Object System.Windows.Threading.DispatcherTimer
$global:scyToastTimer.Interval = [TimeSpan]::FromSeconds(5)
$global:scyToastTimer.Add_Tick({
    try { $global:scyToastTimer.Stop() } catch {}
    try { $global:scyToast.Visibility = "Collapsed" } catch {}
})
if ($global:scyToast) {
    $global:scyToast.Add_PreviewMouseLeftButtonDown({
        try { $global:scyToastTimer.Stop() } catch {}
        try { $global:scyToast.Visibility = "Collapsed" } catch {}
    })
}

function Show-ScyToast {
    param([string]$Title, [string]$Body)
    # $enableNotifications is owned by Tab-Settings, which loads after this
    # module; before then it reads as $null and the toast simply stays quiet.
    if (-not $script:enableNotifications) { return }
    if (-not $global:scyToast) { return }

    $titleText = [string]$Title
    $bodyText  = [string]$Body

    $render = {
        try {
            $global:scyToastTitle.Text = $titleText
            $global:scyToastBody.Text  = $bodyText
            $global:scyToast.Visibility = "Visible"
            try { $global:scyToastTimer.Stop() } catch {}
            $global:scyToastTimer.Start()
        } catch {
            Write-Host "Show-ScyToast render error: $_"
        }
    }.GetNewClosure()

    if ($window.Dispatcher.CheckAccess()) {
        & $render
    } else {
        $window.Dispatcher.BeginInvoke([action]$render, [System.Windows.Threading.DispatcherPriority]::Normal) | Out-Null
    }
}
