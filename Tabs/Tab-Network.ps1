# -- Network Tools Tab ----------------------------------------------------------

# -- Network sub-navigation ---------------------------------------------------
$netNavDiagnostics = Find "NetNav_Diagnostics"
$netNavWifi        = Find "NetNav_Wifi"
$netNavHosts       = Find "NetNav_Hosts"

$netSectionDiagnostics = Find "NetSection_Diagnostics"
$netSectionWifi        = Find "NetSection_Wifi"
$netSectionHosts       = Find "NetSection_Hosts"

$script:netNavButtons = @($netNavDiagnostics, $netNavWifi, $netNavHosts)
$script:netSections   = @($netSectionDiagnostics, $netSectionWifi, $netSectionHosts)

function Set-NetSubNav {
    param([int]$Index)
    for ($i = 0; $i -lt $script:netSections.Count; $i++) {
        $script:netSections[$i].Visibility = if ($i -eq $Index) { "Visible" } else { "Collapsed" }
        $btn = $script:netNavButtons[$i]
        if ($i -eq $Index) {
            $btn.Foreground = $window.Resources["FgBrush"]
            $btn.BorderBrush = $window.Resources["AccentBrush"]
        } else {
            $btn.Foreground = $window.Resources["MutedText"]
            $btn.BorderBrush = $window.Resources["BorderBrush"]
        }
    }
}

Set-NetSubNav 0

$netNavDiagnostics.Add_Click({ Set-NetSubNav 0 })
$netNavWifi.Add_Click({        Set-NetSubNav 1 })
$netNavHosts.Add_Click({       Set-NetSubNav 2 })

$netHostBox         = Find "NetHostBox"
$netHostPlaceholder = Find "NetHostPlaceholder"
$netPingOutput      = Find "NetPingOutput"
$netSpeedOutput     = Find "NetSpeedOutput"
$netWifiPanel       = Find "NetWifiPanel"
$btnNetPing         = Find "BtnNetPing"
$btnNetTrace        = Find "BtnNetTrace"
$btnNetSpeed        = Find "BtnNetSpeed"
$btnNetWifi         = Find "BtnNetWifi"
$btnNetStop         = Find "BtnNetStop"

# -- Speed test server list --------------------------------------------------
$script:speedServers = [ordered]@{
    "Hetzner FSN1 (DE)"  = "https://fsn1-speed.hetzner.com/1GB.bin"
    "Hetzner NBG1 (DE)"  = "https://nbg1-speed.hetzner.com/1GB.bin"
    "Hetzner HEL1 (FI)"  = "https://hel1-speed.hetzner.com/1GB.bin"
    "Hetzner ASH  (USA)" = "https://ash-speed.hetzner.com/1GB.bin"
    "Hetzner HIL  (USA)" = "https://hil-speed.hetzner.com/1GB.bin"
    "OVH BHS (Canada)"   = "https://proof.ovh.ca/files/1Gb.dat"
}

# -- Server selector ComboBox -----------------------------------------------
$netSpeedServerBox = Find "NetSpeedServerBox"
$serverNames = @($script:speedServers.Keys)
foreach ($name in $serverNames) {
    $netSpeedServerBox.Items.Add($name) | Out-Null
}

# Select saved server or default to first
$savedName = $script:speedTestServer
if ($savedName -and $script:speedServers.Contains($savedName)) {
    $netSpeedServerBox.SelectedItem = $savedName
} else {
    $netSpeedServerBox.SelectedIndex = 0
}
$script:speedTestServer = $netSpeedServerBox.SelectedItem

$netSpeedServerBox.Add_SelectionChanged({
    $script:speedTestServer = $netSpeedServerBox.SelectedItem
    Save-Settings
})

# Shared process holder (ArrayList = .NET ref type, shared safely across runspaces)
$script:netProcHolder = [System.Collections.ArrayList]::new()

# -- Placeholder behaviour ---------------------------------------------------
$netHostBox.Add_GotFocus({  $netHostPlaceholder.Visibility = "Collapsed" })
$netHostBox.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($netHostBox.Text)) {
        $netHostPlaceholder.Visibility = "Visible"
    }
})
$netHostBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return) { Invoke-NetPing }
})

# -- Status helpers ----------------------------------------------------------
function Set-NetBusy([string]$msg) {
    $statusIndicator.Text       = "* $msg"
    $statusIndicator.Foreground = $window.Resources["WarningBrush"]
    $footerStatus.Text          = "Scy - $msg"
    $btnNetPing.IsEnabled       = $false
    $btnNetTrace.IsEnabled      = $false
    $btnNetSpeed.IsEnabled      = $false
    $btnNetStop.IsEnabled       = $true
    $btnNetStop.Opacity         = 1
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Set-NetReady {
    $statusIndicator.Text       = "* Ready"
    $statusIndicator.Foreground = $window.Resources["SuccessBrush"]
    $footerStatus.Text          = "Ready"
    $btnNetPing.IsEnabled       = $true
    $btnNetTrace.IsEnabled      = $true
    $btnNetSpeed.IsEnabled      = $true
    $btnNetStop.IsEnabled       = $false
    $btnNetStop.Opacity         = 0.4
    $script:netProcHolder.Clear()
}

# -- Live-streaming process runner -------------------------------------------
# Spawns a background runspace; output lines are appended via Dispatcher.Invoke
# so the UI stays fully responsive during long-running commands.
function Start-NetLiveExe {
    param(
        [string]$Exe,
        [string]$Arguments,
        [System.Windows.Controls.TextBox]$OutputBox,
        [string]$StatusText
    )

    Set-NetBusy $StatusText
    $OutputBox.Text = "> $Exe $Arguments`r`n$('-' * 60)`r`n"

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()

    $rs.SessionStateProxy.SetVariable("_exe",        $Exe)
    $rs.SessionStateProxy.SetVariable("_args",       $Arguments)
    $rs.SessionStateProxy.SetVariable("_box",        $OutputBox)
    $rs.SessionStateProxy.SetVariable("_win",        $window)
    $rs.SessionStateProxy.SetVariable("_si",         $statusIndicator)
    $rs.SessionStateProxy.SetVariable("_fs",         $footerStatus)
    $rs.SessionStateProxy.SetVariable("_pingBtn",    $btnNetPing)
    $rs.SessionStateProxy.SetVariable("_traceBtn",   $btnNetTrace)
    $rs.SessionStateProxy.SetVariable("_speedBtn",   $btnNetSpeed)
    $rs.SessionStateProxy.SetVariable("_stopBtn",    $btnNetStop)
    $rs.SessionStateProxy.SetVariable("_procHolder", $script:netProcHolder)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    $ps.AddScript({
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName               = $_exe
        $psi.Arguments              = $_args
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.CreateNoWindow         = $true

        $p = [System.Diagnostics.Process]::new()
        $p.StartInfo = $psi
        $p.Start() | Out-Null
        $_procHolder.Clear()
        $_procHolder.Add($p) | Out-Null

        while (-not $p.StandardOutput.EndOfStream) {
            $line = $p.StandardOutput.ReadLine()
            $_win.Dispatcher.Invoke([action]{
                $_box.AppendText("$line`r`n")
                $_box.ScrollToEnd()
            }, [System.Windows.Threading.DispatcherPriority]::Normal)
        }
        $p.WaitForExit()

        $_win.Dispatcher.Invoke([action]{
            $_si.Text            = "* Ready"
            $_si.Foreground      = $_win.Resources["SuccessBrush"]
            $_fs.Text            = "Ready"
            $_pingBtn.IsEnabled  = $true
            $_traceBtn.IsEnabled = $true
            $_speedBtn.IsEnabled = $true
            $_stopBtn.IsEnabled  = $false
            $_stopBtn.Opacity    = 0.4
            $_procHolder.Clear()
        }, [System.Windows.Threading.DispatcherPriority]::Normal)
    }) | Out-Null

    $ps.BeginInvoke() | Out-Null
}

# -- Ping --------------------------------------------------------------------
function Invoke-NetPing {
    $h = $netHostBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($h)) { $h = "8.8.8.8" }
    Start-NetLiveExe -Exe "ping" -Arguments "-n 4 $h" `
                     -OutputBox $netPingOutput -StatusText "Pinging $h..."
}

$btnNetPing.Add_Click({ Invoke-NetPing })

# -- Traceroute --------------------------------------------------------------
function Invoke-NetTrace {
    $h = $netHostBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($h)) { $h = "8.8.8.8" }
    Start-NetLiveExe -Exe "tracert" -Arguments "-d $h" `
                     -OutputBox $netPingOutput -StatusText "Tracing route to $h..."
}

$btnNetTrace.Add_Click({ Invoke-NetTrace })

# -- Stop --------------------------------------------------------------------
$btnNetStop.Add_Click({
    if ($script:netProcHolder.Count -gt 0) {
        $p = $script:netProcHolder[0]
        if ($p -and -not $p.HasExited) {
            try { $p.Kill() } catch {}
        }
    }
})

# -- Speed test --------------------------------------------------------------
$btnNetSpeed.Add_Click({
    $selectedServer = $script:speedTestServer
    $serverUrl      = $script:speedServers[$selectedServer]
    $netSpeedOutput.Text = "> Running speed test via $selectedServer (8 streams, ~5s)...`r`n$('-' * 60)`r`n"
    Set-NetBusy "Speed test running..."
    # Speed test has no killable process, keep Stop disabled
    $btnNetStop.IsEnabled = $false
    $btnNetStop.Opacity   = 0.4

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()

    $rs.SessionStateProxy.SetVariable("_box",       $netSpeedOutput)
    $rs.SessionStateProxy.SetVariable("_win",       $window)
    $rs.SessionStateProxy.SetVariable("_si",        $statusIndicator)
    $rs.SessionStateProxy.SetVariable("_fs",        $footerStatus)
    $rs.SessionStateProxy.SetVariable("_speedBtn",  $btnNetSpeed)
    $rs.SessionStateProxy.SetVariable("_pingBtn",   $btnNetPing)
    $rs.SessionStateProxy.SetVariable("_traceBtn",  $btnNetTrace)
    $rs.SessionStateProxy.SetVariable("_stopBtn",   $btnNetStop)
    $rs.SessionStateProxy.SetVariable("_serverUrl", $serverUrl)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    $ps.AddScript({
        function Ui([string]$t) {
            $_win.Dispatcher.Invoke([action]{
                $_box.AppendText("$t`r`n")
                $_box.ScrollToEnd()
            }, [System.Windows.Threading.DispatcherPriority]::Normal)
        }

        try {
            # 8 parallel streams via RunspacePool (each worker gets its own runspace).
            # Shared [long[]] and [int[]] arrays are .NET reference types, so all
            # workers see the same objects despite running in separate runspaces.
            $url      = $_serverUrl
            $numConns = 8
            $total    = [long[]]::new(1)   # shared byte counter
            $phase    = [int[]]::new(1)    # 0=warmup  1=measure  2=stop
            $lk       = [object]::new()

            $workerScript = {
                param($url, $phase, $total, $lk)
                $localBytes = [long]0
                try {
                    $req           = [System.Net.HttpWebRequest]::Create($url)
                    $req.UserAgent = "Mozilla/5.0"
                    $req.Timeout   = 20000
                    $resp          = $req.GetResponse()
                    $str           = $resp.GetResponseStream()
                    $buf           = New-Object byte[] 524288   # 512 KB buffer
                    while ($phase[0] -lt 2) {
                        $r = $str.Read($buf, 0, $buf.Length)
                        if ($r -le 0) { break }
                        if ($phase[0] -eq 1) { $localBytes += $r }
                    }
                    $str.Close()
                    $resp.Close()
                } catch {}
                [System.Threading.Monitor]::Enter($lk)
                $total[0] += $localBytes
                [System.Threading.Monitor]::Exit($lk)
            }

            $pool = [runspacefactory]::CreateRunspacePool($numConns, $numConns)
            $pool.Open()

            Ui "Connecting ($numConns parallel streams)..."
            $jobs = 1..$numConns | ForEach-Object {
                $ps = [powershell]::Create()
                $ps.RunspacePool = $pool
                $ps.AddScript($workerScript) | Out-Null
                $ps.AddArgument($url)   | Out-Null
                $ps.AddArgument($phase) | Out-Null
                $ps.AddArgument($total) | Out-Null
                $ps.AddArgument($lk)    | Out-Null
                @{ PS = $ps; Handle = $ps.BeginInvoke() }
            }

            Ui "Warming up..."
            $phase[0] = 0
            Start-Sleep -Milliseconds 1500

            Ui "Measuring..."
            $phase[0] = 1
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            Start-Sleep -Milliseconds 3000
            $sw.Stop()
            $phase[0] = 2

            $jobs | ForEach-Object { try { $_.PS.EndInvoke($_.Handle) } catch {} }
            $pool.Close()

            $seconds = [math]::Round($sw.Elapsed.TotalSeconds, 3)
            $sizeMB  = [math]::Round($total[0] / 1MB, 2)
            $mbps    = [math]::Round(($total[0] * 8) / $sw.Elapsed.TotalSeconds / 1000000, 2)

            Ui ""
            Ui "Streams    : $numConns parallel"
            Ui "Sampled    : $sizeMB MB in $seconds s"
            Ui "Download   : $mbps Mbps"
            Ui ""
            Ui "Done."
        } catch {
            Ui "Error: $_"
        }

        $_win.Dispatcher.Invoke([action]{
            $_si.Text            = "* Ready"
            $_si.Foreground      = $_win.Resources["SuccessBrush"]
            $_fs.Text            = "Ready"
            $_speedBtn.IsEnabled = $true
            $_pingBtn.IsEnabled  = $true
            $_traceBtn.IsEnabled = $true
            $_stopBtn.IsEnabled  = $false
            $_stopBtn.Opacity    = 0.4
        }, [System.Windows.Threading.DispatcherPriority]::Normal)
    }) | Out-Null

    $ps.BeginInvoke() | Out-Null
})

# -- Wi-Fi passwords ---------------------------------------------------------
$btnNetWifi.Add_Click({
    $netWifiPanel.Children.Clear()
    $statusIndicator.Text       = "* Reading Wi-Fi profiles..."
    $statusIndicator.Foreground = $window.Resources["WarningBrush"]
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

    try {
        $raw      = netsh wlan show profiles 2>&1
        $profiles = $raw | Select-String "All User Profile" |
                    ForEach-Object { ($_ -replace ".*:\s*", "").Trim() }

        if (-not $profiles) {
            $tb          = [System.Windows.Controls.TextBlock]::new()
            $tb.Text     = "No saved Wi-Fi profiles found (or Wi-Fi adapter not present)."
            $tb.FontSize = 12
            $tb.SetResourceReference(
                [System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
            $netWifiPanel.Children.Add($tb) | Out-Null
        } else {
            $alt = $false
            foreach ($name in $profiles) {
                $details  = netsh wlan show profile name="$name" key=clear 2>&1
                $pwdLine  = $details | Select-String "Key Content"
                $password = if ($pwdLine) {
                    ($pwdLine -replace ".*:\s*", "").Trim()
                } else { "(open / no password)" }

                $border              = [System.Windows.Controls.Border]::new()
                $border.Background   = if ($alt) {
                    $window.Resources["SurfaceBrush"]
                } else {
                    $window.Resources["InputBgBrush"]
                }
                $border.CornerRadius = [System.Windows.CornerRadius]::new(4)
                $border.Padding      = [System.Windows.Thickness]::new(10, 7, 10, 7)
                $border.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 3)

                $grid = [System.Windows.Controls.Grid]::new()
                $c0   = [System.Windows.Controls.ColumnDefinition]::new()
                $c0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
                $c1   = [System.Windows.Controls.ColumnDefinition]::new()
                $c1.Width = [System.Windows.GridLength]::Auto
                $grid.ColumnDefinitions.Add($c0)
                $grid.ColumnDefinitions.Add($c1)

                $nameBlock            = [System.Windows.Controls.TextBlock]::new()
                $nameBlock.Text       = $name
                $nameBlock.FontSize   = 12
                $nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
                $nameBlock.SetResourceReference(
                    [System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
                [System.Windows.Controls.Grid]::SetColumn($nameBlock, 0)

                $pwBlock                     = [System.Windows.Controls.TextBlock]::new()
                $pwBlock.Text                = $password
                $pwBlock.FontSize            = 12
                $pwBlock.FontFamily          = [System.Windows.Media.FontFamily]::new("Consolas")
                $pwBlock.HorizontalAlignment = "Right"
                $pwBlock.SetResourceReference(
                    [System.Windows.Controls.TextBlock]::ForegroundProperty, "AccentBrush")
                [System.Windows.Controls.Grid]::SetColumn($pwBlock, 1)

                $grid.Children.Add($nameBlock) | Out-Null
                $grid.Children.Add($pwBlock)   | Out-Null
                $border.Child = $grid
                $netWifiPanel.Children.Add($border) | Out-Null

                $alt = -not $alt
            }
        }
    } catch {
        $tb            = [System.Windows.Controls.TextBlock]::new()
        $tb.Text       = "Error: $_"
        $tb.FontSize   = 12
        $tb.Foreground = $window.Resources["DangerBrush"]
        $netWifiPanel.Children.Add($tb) | Out-Null
    }

    $statusIndicator.Text       = "* Ready"
    $statusIndicator.Foreground = $window.Resources["SuccessBrush"]
    $footerStatus.Text          = "Ready"
})
