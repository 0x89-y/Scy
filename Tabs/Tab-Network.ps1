# -- Network Tools Tab ----------------------------------------------------------

# -- Network sub-navigation ---------------------------------------------------
$netNavDiagnostics = Find "NetNav_Diagnostics"
$netNavWifi        = Find "NetNav_Wifi"
$netNavHosts       = Find "NetNav_Hosts"
$netNavDNS         = Find "NetNav_DNS"

$netSectionDiagnostics = Find "NetSection_Diagnostics"
$netSectionWifi        = Find "NetSection_Wifi"
$netSectionHosts       = Find "NetSection_Hosts"
$netSectionDNS         = Find "NetSection_DNS"

$script:netNavButtons = @($netNavDiagnostics, $netNavWifi, $netNavHosts, $netNavDNS)
$script:netSections   = @($netSectionDiagnostics, $netSectionWifi, $netSectionHosts, $netSectionDNS)

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
$netNavDNS.Add_Click({         Set-NetSubNav 3 })

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

# -- Wi-Fi QR code dialog ----------------------------------------------------
function Show-WifiQRDialog([string]$ssid, [string]$password, [string]$authType) {
    # Escape special chars for WiFi QR format
    $escSsid = $ssid -replace '([\\;,:""])', '\$1'
    $escPwd  = $password -replace '([\\;,:""])', '\$1'

    $wifiString = if ($authType -eq "nopass") {
        "WIFI:T:nopass;S:$escSsid;;"
    } else {
        "WIFI:T:$authType;S:$escSsid;P:$escPwd;;"
    }

    # Generate QR code -- always use black-on-white for best scanner compatibility
    $qrImage = New-QRCodeImage -Text $wifiString -ModuleSize 6 `
        -Dark ([System.Windows.Media.Colors]::Black) `
        -Light ([System.Windows.Media.Colors]::White)

    # Build themed dialog (matches Show-ThemedDialog style)
    $dlg = New-Object System.Windows.Window
    $dlg.Title               = "Wi-Fi QR Code"
    $dlg.WindowStyle         = "None"
    $dlg.ResizeMode          = "NoResize"
    $dlg.SizeToContent       = "WidthAndHeight"
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner               = $window
    $dlg.Background          = $window.Resources["WindowBgBrush"]
    $dlg.Foreground          = $window.Resources["FgBrush"]
    $dlg.Add_MouseLeftButtonDown({ $this.DragMove() })

    $outerBorder = New-Object System.Windows.Controls.Border
    $outerBorder.BorderBrush     = $window.Resources["BorderBrush"]
    $outerBorder.BorderThickness = [System.Windows.Thickness]::new(1)
    $outerBorder.CornerRadius    = [System.Windows.CornerRadius]::new(8)
    $outerBorder.Background      = $window.Resources["WindowBgBrush"]

    $root = New-Object System.Windows.Controls.StackPanel

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
    $titleText.Text       = "Wi-Fi QR Code"
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
    $closeBtn.Add_Click({ $dlg.Close() })

    $titleGrid.Children.Add($titleText) | Out-Null
    $titleGrid.Children.Add($closeBtn)  | Out-Null
    $titleBar.Child = $titleGrid

    # ── Body ──
    $body = New-Object System.Windows.Controls.StackPanel
    $body.HorizontalAlignment = "Center"
    $body.Margin = [System.Windows.Thickness]::new(24, 16, 24, 8)

    # Network name
    $ssidBlock            = New-Object System.Windows.Controls.TextBlock
    $ssidBlock.Text       = $ssid
    $ssidBlock.FontSize   = 15
    $ssidBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
    $ssidBlock.Foreground = $window.Resources["FgBrush"]
    $ssidBlock.HorizontalAlignment = "Center"
    $ssidBlock.Margin     = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $body.Children.Add($ssidBlock) | Out-Null

    # QR code image (white background border for contrast in dark theme)
    $qrBorder = New-Object System.Windows.Controls.Border
    $qrBorder.Background   = [System.Windows.Media.Brushes]::White
    $qrBorder.CornerRadius = [System.Windows.CornerRadius]::new(6)
    $qrBorder.Padding      = [System.Windows.Thickness]::new(8)
    $qrBorder.HorizontalAlignment = "Center"

    $img = New-Object System.Windows.Controls.Image
    $img.Source = $qrImage
    $img.Width  = $qrImage.PixelWidth
    $img.Height = $qrImage.PixelHeight
    $img.SetValue([System.Windows.Media.RenderOptions]::BitmapScalingModeProperty,
        [System.Windows.Media.BitmapScalingMode]::NearestNeighbor)
    $qrBorder.Child = $img
    $body.Children.Add($qrBorder) | Out-Null

    # Hint text
    $hint            = New-Object System.Windows.Controls.TextBlock
    $hint.Text       = "Scan with your phone camera to connect"
    $hint.FontSize   = 11
    $hint.Foreground = $window.Resources["MutedText"]
    $hint.HorizontalAlignment = "Center"
    $hint.Margin     = [System.Windows.Thickness]::new(0, 10, 0, 0)
    $body.Children.Add($hint) | Out-Null

    # ── Close button row ──
    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.HorizontalAlignment = "Center"
    $btnPanel.Margin = [System.Windows.Thickness]::new(0, 12, 0, 16)

    $dlgCloseBtn         = New-Object System.Windows.Controls.Button
    $dlgCloseBtn.Content = "Close"
    $dlgCloseBtn.Style   = $window.Resources["SecondaryButton"]
    $dlgCloseBtn.Padding = [System.Windows.Thickness]::new(24, 7, 24, 7)
    $dlgCloseBtn.Add_Click({ $dlg.Close() })
    $btnPanel.Children.Add($dlgCloseBtn) | Out-Null

    $root.Children.Add($titleBar) | Out-Null
    $root.Children.Add($body)     | Out-Null
    $root.Children.Add($btnPanel) | Out-Null
    $outerBorder.Child = $root
    $dlg.Content = $outerBorder

    $dlg.ShowDialog() | Out-Null
}

# -- Wi-Fi passwords ---------------------------------------------------------
$btnNetWifi.Add_Click({
    $netWifiPanel.Children.Clear()
    $statusIndicator.Text       = "* Reading Wi-Fi profiles..."
    $statusIndicator.Foreground = $window.Resources["WarningBrush"]
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

    try {
        # Use XML export to avoid locale-dependent text parsing (netsh text
        # output is translated on non-English Windows, but XML element names
        # like <name>, <keyMaterial>, <authentication> are always English).
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "scy_wifi_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        try { netsh wlan export profile folder="$tempDir" key=clear 2>&1 | Out-Null } catch {}

        $xmlFiles = Get-ChildItem -Path $tempDir -Filter "*.xml" -ErrorAction SilentlyContinue
        $profiles = @()
        foreach ($xf in $xmlFiles) {
            try {
                $xml  = [xml](Get-Content $xf.FullName -Raw)
                $profiles += [PSCustomObject]@{
                    Name     = $xml.WLANProfile.name
                    Password = if ($xml.WLANProfile.MSM.security.sharedKey.keyMaterial) {
                                   $xml.WLANProfile.MSM.security.sharedKey.keyMaterial
                               } else { "(open / no password)" }
                    AuthType = switch -Wildcard ($xml.WLANProfile.MSM.security.authEncryption.authentication) {
                                   "*SAE*"  { "SAE" }
                                   "*WPA2*" { "WPA" }
                                   "*WPA*"  { "WPA" }
                                   "open"   { "nopass" }
                                   default  { "WPA" }
                               }
                }
            } catch {}
        }
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

        if (-not $profiles) {
            $tb          = [System.Windows.Controls.TextBlock]::new()
            $tb.Text     = "No saved Wi-Fi profiles found (or Wi-Fi adapter not present)."
            $tb.FontSize = 12
            $tb.SetResourceReference(
                [System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
            $netWifiPanel.Children.Add($tb) | Out-Null
        } else {
            $alt = $false
            foreach ($prof in $profiles) {
                $name     = $prof.Name
                $password = $prof.Password
                $authType = $prof.AuthType

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
                $c2   = [System.Windows.Controls.ColumnDefinition]::new()
                $c2.Width = [System.Windows.GridLength]::Auto
                $grid.ColumnDefinitions.Add($c0)
                $grid.ColumnDefinitions.Add($c1)
                $grid.ColumnDefinitions.Add($c2)

                $nameBlock            = [System.Windows.Controls.TextBlock]::new()
                $nameBlock.Text       = $name
                $nameBlock.FontSize   = 12
                $nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
                $nameBlock.VerticalAlignment = "Center"
                $nameBlock.SetResourceReference(
                    [System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
                [System.Windows.Controls.Grid]::SetColumn($nameBlock, 0)

                $pwBlock                     = [System.Windows.Controls.TextBlock]::new()
                $pwBlock.Text                = $password
                $pwBlock.FontSize            = 12
                $pwBlock.FontFamily          = [System.Windows.Media.FontFamily]::new("Consolas")
                $pwBlock.HorizontalAlignment = "Right"
                $pwBlock.VerticalAlignment   = "Center"
                $pwBlock.SetResourceReference(
                    [System.Windows.Controls.TextBlock]::ForegroundProperty, "AccentBrush")
                [System.Windows.Controls.Grid]::SetColumn($pwBlock, 1)

                # QR code button
                $qrBtn            = [System.Windows.Controls.Button]::new()
                $qrBtn.Content    = "QR"
                $qrBtn.Style      = $window.Resources["SecondaryButton"]
                $qrBtn.Padding    = [System.Windows.Thickness]::new(8, 3, 8, 3)
                $qrBtn.Margin     = [System.Windows.Thickness]::new(8, 0, 0, 0)
                $qrBtn.FontSize   = 11
                $qrBtn.Cursor     = [System.Windows.Input.Cursors]::Hand
                $qrBtn.VerticalAlignment = "Center"
                [System.Windows.Controls.Grid]::SetColumn($qrBtn, 2)

                $capturedName     = $name
                $capturedPassword = $password
                $capturedAuth     = $authType
                $qrBtn.Add_Click({
                    Show-WifiQRDialog $capturedName $capturedPassword $capturedAuth
                }.GetNewClosure())

                $grid.Children.Add($nameBlock) | Out-Null
                $grid.Children.Add($pwBlock)   | Out-Null
                $grid.Children.Add($qrBtn)     | Out-Null
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

# -- DNS Switcher ---------------------------------------------------------------
$dnsAdapterBox          = Find "DnsAdapterBox"
$dnsCurrentDisplay      = Find "DnsCurrentDisplay"
$dnsStatusText          = Find "DnsStatusText"
$dnsPrimaryBox          = Find "DnsPrimaryBox"
$dnsSecondaryBox        = Find "DnsSecondaryBox"
$dnsPrimaryPlaceholder  = Find "DnsPrimaryPlaceholder"
$dnsSecondaryPlaceholder = Find "DnsSecondaryPlaceholder"
$btnDnsRefreshAdapters  = Find "BtnDnsRefreshAdapters"
$btnDnsApplyCustom      = Find "BtnDnsApplyCustom"
$btnDnsCloudflare       = Find "BtnDnsCloudflare"
$btnDnsGoogle           = Find "BtnDnsGoogle"
$btnDnsQuad9            = Find "BtnDnsQuad9"
$btnDnsOpenDNS          = Find "BtnDnsOpenDNS"
$btnDnsDHCP             = Find "BtnDnsDHCP"
$dnsAdminBanner         = Find "DnsAdminBanner"
$dnsDoHCheckbox         = Find "DnsDoHCheckbox"
$dnsDoHStatus           = Find "DnsDoHStatus"
$dnsDoHUnsupportedBanner = Find "DnsDoHUnsupportedBanner"

# Check admin status
$script:dnsIsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $script:dnsIsAdmin) {
    $dnsAdminBanner.Visibility = "Visible"
}

# Check DoH support (requires Windows 10 Build 19628+ or Windows 11)
$script:dohSupported = $false
try {
    $null = Get-Command Set-DnsClientDohServerAddress -ErrorAction Stop
    $script:dohSupported = $true
    $dnsDoHStatus.Text       = "Supported"
    $dnsDoHStatus.Foreground = $window.Resources["SuccessBrush"]
} catch {
    $dnsDoHCheckbox.IsEnabled = $false
    $dnsDoHUnsupportedBanner.Visibility = "Visible"
    $dnsDoHStatus.Text       = "Not available"
    $dnsDoHStatus.Foreground = $window.Resources["MutedText"]
}

# Placeholder toggle helpers
$dnsPrimaryBox.Add_GotFocus({   $dnsPrimaryPlaceholder.Visibility   = "Collapsed" })
$dnsPrimaryBox.Add_LostFocus({  if ($dnsPrimaryBox.Text -eq "")   { $dnsPrimaryPlaceholder.Visibility   = "Visible" } })
$dnsSecondaryBox.Add_GotFocus({ $dnsSecondaryPlaceholder.Visibility = "Collapsed" })
$dnsSecondaryBox.Add_LostFocus({ if ($dnsSecondaryBox.Text -eq "") { $dnsSecondaryPlaceholder.Visibility = "Visible" } })

# DNS profiles: Name -> @{ Primary; Secondary; DohTemplate }
$script:dnsProfiles = @{
    "Cloudflare" = @{
        Primary     = "1.1.1.1"
        Secondary   = "1.0.0.1"
        DohTemplate = "https://cloudflare-dns.com/dns-query"
    }
    "Google" = @{
        Primary     = "8.8.8.8"
        Secondary   = "8.8.4.4"
        DohTemplate = "https://dns.google/dns-query"
    }
    "Quad9" = @{
        Primary     = "9.9.9.9"
        Secondary   = "149.112.112.112"
        DohTemplate = "https://dns.quad9.net/dns-query"
    }
    "OpenDNS" = @{
        Primary     = "208.67.222.222"
        Secondary   = "208.67.220.220"
        DohTemplate = "https://doh.opendns.com/dns-query"
    }
}

function Get-DnsAdapters {
    Get-NetAdapter | Where-Object { $_.Status -eq "Up" } |
        Select-Object -Property Name, InterfaceIndex, InterfaceDescription |
        Sort-Object Name
}

function Update-DnsAdapterList {
    $dnsAdapterBox.Items.Clear()
    $script:dnsAdapters = @(Get-DnsAdapters)
    foreach ($a in $script:dnsAdapters) {
        $dnsAdapterBox.Items.Add($a.Name) | Out-Null
    }
    if ($dnsAdapterBox.Items.Count -gt 0) {
        $dnsAdapterBox.SelectedIndex = 0
    }
}

function Get-CurrentDnsForAdapter {
    param([string]$AdapterName)
    try {
        $cfg = Get-DnsClientServerAddress -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction Stop
        if ($cfg.ServerAddresses.Count -eq 0) { return "DHCP (Automatic)" }
        $display = $cfg.ServerAddresses -join ", "
        # Check if any of the current DNS servers have DoH registered
        if ($script:dohSupported) {
            $dohServers = Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue
            $hasDoH = $false
            foreach ($addr in $cfg.ServerAddresses) {
                if ($dohServers | Where-Object { $_.ServerAddress -eq $addr -and $_.AutoUpgrade }) {
                    $hasDoH = $true; break
                }
            }
            if ($hasDoH) { $display += "  [DoH]" }
        }
        return $display
    } catch {
        return "Unknown"
    }
}

function Update-DnsCurrentDisplay {
    if ($dnsAdapterBox.SelectedItem) {
        $dns = Get-CurrentDnsForAdapter -AdapterName $dnsAdapterBox.SelectedItem
        $dnsCurrentDisplay.Text = $dns
    }
}

function Register-DohServer {
    param(
        [string]$ServerAddress,
        [string]$DohTemplate
    )
    if (-not $script:dohSupported -or -not $DohTemplate) { return }
    try {
        # Check if already registered
        $existing = Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue |
            Where-Object { $_.ServerAddress -eq $ServerAddress }
        if (-not $existing) {
            Add-DnsClientDohServerAddress -ServerAddress $ServerAddress `
                -DohTemplate $DohTemplate -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction Stop
        }
    } catch {
        # Silently continue — registration may already exist via system policy
    }
}

function Set-DnsForAdapter {
    param(
        [string]$AdapterName,
        [string]$Primary,
        [string]$Secondary,
        [string]$DohTemplate
    )
    if (-not $script:dnsIsAdmin) {
        [System.Windows.MessageBox]::Show(
            "DNS changes require running as Administrator.`nPlease restart Scy with elevated privileges.",
            "Scy - DNS", "OK", "Warning") | Out-Null
        return
    }
    try {
        $useDoH = $dnsDoHCheckbox.IsChecked -and $script:dohSupported
        $statusLabel = if ($useDoH) { "Applying with DoH..." } else { "Applying..." }
        $dnsStatusText.Text       = $statusLabel
        $dnsStatusText.Foreground = $window.Resources["WarningBrush"]

        $addresses = @($Primary)
        if ($Secondary -and $Secondary.Trim() -ne "") { $addresses += $Secondary }

        # Register DoH templates before setting DNS addresses
        if ($useDoH -and $DohTemplate) {
            Register-DohServer -ServerAddress $Primary -DohTemplate $DohTemplate
            if ($Secondary -and $Secondary.Trim() -ne "") {
                Register-DohServer -ServerAddress $Secondary -DohTemplate $DohTemplate
            }
        }

        Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ServerAddresses $addresses

        # Flush DNS cache so new settings take effect immediately
        Clear-DnsClientCache -ErrorAction SilentlyContinue

        $resultLabel = if ($useDoH) { "Applied with DoH" } else { "Applied" }
        $dnsStatusText.Text       = $resultLabel
        $dnsStatusText.Foreground = $window.Resources["SuccessBrush"]
        Update-DnsCurrentDisplay
    } catch {
        $dnsStatusText.Text       = "Error: $_"
        $dnsStatusText.Foreground = $window.Resources["DangerBrush"]
    }
}

function Reset-DnsToDHCP {
    param([string]$AdapterName)
    if (-not $script:dnsIsAdmin) {
        [System.Windows.MessageBox]::Show(
            "DNS changes require running as Administrator.`nPlease restart Scy with elevated privileges.",
            "Scy - DNS", "OK", "Warning") | Out-Null
        return
    }
    try {
        $dnsStatusText.Text       = "Resetting..."
        $dnsStatusText.Foreground = $window.Resources["WarningBrush"]

        Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ResetServerAddresses
        Clear-DnsClientCache -ErrorAction SilentlyContinue

        $dnsStatusText.Text       = "Reset to DHCP"
        $dnsStatusText.Foreground = $window.Resources["SuccessBrush"]
        Update-DnsCurrentDisplay
    } catch {
        $dnsStatusText.Text       = "Error: $_"
        $dnsStatusText.Foreground = $window.Resources["DangerBrush"]
    }
}

# Load adapters on init
Update-DnsAdapterList

# Update current DNS display when adapter selection changes
$dnsAdapterBox.Add_SelectionChanged({ Update-DnsCurrentDisplay })

# Refresh button
$btnDnsRefreshAdapters.Add_Click({
    Update-DnsAdapterList
    $dnsStatusText.Text       = "Refreshed"
    $dnsStatusText.Foreground = $window.Resources["SuccessBrush"]
})

# Preset profile buttons
$btnDnsCloudflare.Add_Click({
    if ($dnsAdapterBox.SelectedItem) {
        $p = $script:dnsProfiles["Cloudflare"]
        Set-DnsForAdapter -AdapterName $dnsAdapterBox.SelectedItem -Primary $p.Primary -Secondary $p.Secondary -DohTemplate $p.DohTemplate
    }
})
$btnDnsGoogle.Add_Click({
    if ($dnsAdapterBox.SelectedItem) {
        $p = $script:dnsProfiles["Google"]
        Set-DnsForAdapter -AdapterName $dnsAdapterBox.SelectedItem -Primary $p.Primary -Secondary $p.Secondary -DohTemplate $p.DohTemplate
    }
})
$btnDnsQuad9.Add_Click({
    if ($dnsAdapterBox.SelectedItem) {
        $p = $script:dnsProfiles["Quad9"]
        Set-DnsForAdapter -AdapterName $dnsAdapterBox.SelectedItem -Primary $p.Primary -Secondary $p.Secondary -DohTemplate $p.DohTemplate
    }
})
$btnDnsOpenDNS.Add_Click({
    if ($dnsAdapterBox.SelectedItem) {
        $p = $script:dnsProfiles["OpenDNS"]
        Set-DnsForAdapter -AdapterName $dnsAdapterBox.SelectedItem -Primary $p.Primary -Secondary $p.Secondary -DohTemplate $p.DohTemplate
    }
})
$btnDnsDHCP.Add_Click({
    if ($dnsAdapterBox.SelectedItem) {
        Reset-DnsToDHCP -AdapterName $dnsAdapterBox.SelectedItem
    }
})

# Custom DNS apply
$btnDnsApplyCustom.Add_Click({
    if (-not $dnsAdapterBox.SelectedItem) { return }
    $primary = $dnsPrimaryBox.Text.Trim()
    if ($primary -eq "") {
        $dnsStatusText.Text       = "Enter a primary DNS"
        $dnsStatusText.Foreground = $window.Resources["WarningBrush"]
        return
    }
    # Basic IP validation
    $ipRegex = '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'
    if ($primary -notmatch $ipRegex) {
        $dnsStatusText.Text       = "Invalid primary IP"
        $dnsStatusText.Foreground = $window.Resources["DangerBrush"]
        return
    }
    $secondary = $dnsSecondaryBox.Text.Trim()
    if ($secondary -ne "" -and $secondary -notmatch $ipRegex) {
        $dnsStatusText.Text       = "Invalid secondary IP"
        $dnsStatusText.Foreground = $window.Resources["DangerBrush"]
        return
    }
    Set-DnsForAdapter -AdapterName $dnsAdapterBox.SelectedItem -Primary $primary -Secondary $secondary
})

