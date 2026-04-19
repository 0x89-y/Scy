# ── System sub-navigation ──────────────────────────────────────
$systemNavInfo     = Find "SystemNav_Info"
$systemNavCleanup  = Find "SystemNav_Cleanup"
$systemNavBattery  = Find "SystemNav_Battery"
$systemNavFirmware = Find "SystemNav_Firmware"
$systemNavSfcDism  = Find "SystemNav_SfcDism"

$systemSectionInfo     = Find "SystemSection_Info"
$systemSectionCleanup  = Find "SystemSection_Cleanup"
$systemSectionBattery  = Find "SystemSection_Battery"
$systemSectionFirmware = Find "SystemSection_Firmware"
$systemSectionSfcDism  = Find "SystemSection_SfcDism"

$script:systemNavButtons = @($systemNavInfo, $systemNavCleanup, $systemNavBattery, $systemNavFirmware, $systemNavSfcDism)
$script:systemSections   = @($systemSectionInfo, $systemSectionCleanup, $systemSectionBattery, $systemSectionFirmware, $systemSectionSfcDism)

function Set-SystemSubNav {
    param([int]$Index)
    $script:systemSubNavIndex = $Index
    for ($i = 0; $i -lt $script:systemSections.Count; $i++) {
        $script:systemSections[$i].Visibility = if ($i -eq $Index) { "Visible" } else { "Collapsed" }
        $btn = $script:systemNavButtons[$i]
        if ($i -eq $Index) {
            $btn.Foreground = $window.Resources["FgBrush"]
            $btn.BorderBrush = $window.Resources["AccentBrush"]
        } else {
            $btn.Foreground = $window.Resources["MutedText"]
            $btn.BorderBrush = $window.Resources["BorderBrush"]
        }
    }
}

Set-SystemSubNav 0

$systemNavInfo.Add_Click({    Set-SystemSubNav 0 })
$systemNavCleanup.Add_Click({ Set-SystemSubNav 1 })
$systemNavBattery.Add_Click({  Set-SystemSubNav 2 })
$systemNavFirmware.Add_Click({ Set-SystemSubNav 3 })
$systemNavSfcDism.Add_Click({  Set-SystemSubNav 4 })

# -- System Info Tab ----------------------------------------------------------
$sysOS       = Find "SysOS"
$sysBuild    = Find "SysBuild"
$sysComputer = Find "SysComputer"
$sysUser     = Find "SysUser"
$sysUptime   = Find "SysUptime"
$hwCPU       = Find "HwCPU"
$hwCores     = Find "HwCores"
$hwRAM       = Find "HwRAM"
$hwGPU       = Find "HwGPU"
$diskPanel   = Find "DiskPanel"
$netPanel    = Find "NetAdapterPanel"

# Helper: one label/value row
function New-InfoRow {
    param(
        [string]$Label,
        [string]$Value,
        [string]$ValueBrushKey = "FgBrush",
        [bool]$Alternate = $false
    )

    $border = New-Object System.Windows.Controls.Border
    $border.Background = if ($Alternate) { $window.Resources["SurfaceBrush"] } else { $window.Resources["InputBgBrush"] }
    $border.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $border.Padding      = [System.Windows.Thickness]::new(10, 6, 10, 6)
    $border.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 3)

    $grid = New-Object System.Windows.Controls.Grid
    $c0   = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::Auto
    $c1   = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $grid.ColumnDefinitions.Add($c0)
    $grid.ColumnDefinitions.Add($c1)

    $lbl          = New-Object System.Windows.Controls.TextBlock
    $lbl.Text     = $Label
    $lbl.FontSize = 12
    $lbl.MinWidth = 110
    $lbl.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    [System.Windows.Controls.Grid]::SetColumn($lbl, 0)

    $val                     = New-Object System.Windows.Controls.TextBlock
    $val.Text                = $Value
    $val.FontSize            = 12
    $val.HorizontalAlignment = "Right"
    $val.TextAlignment       = "Right"
    $val.TextWrapping        = "Wrap"
    $val.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $ValueBrushKey)
    [System.Windows.Controls.Grid]::SetColumn($val, 1)

    $grid.Children.Add($lbl) | Out-Null
    $grid.Children.Add($val) | Out-Null
    $border.Child = $grid
    return $border
}

# Helper: adapter name header inside the network card
function New-AdapterHeader {
    param([string]$Name)
    $tb            = New-Object System.Windows.Controls.TextBlock
    $tb.Text       = $Name
    $tb.FontSize   = 11
    $tb.FontWeight = "SemiBold"
    $tb.Margin     = [System.Windows.Thickness]::new(0, 8, 0, 4)
    $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "AccentBrush")
    return $tb
}

# Helper: thin separator line
function New-Separator {
    $sep = New-Object System.Windows.Controls.Border
    $sep.Height  = 1
    $sep.Margin  = [System.Windows.Thickness]::new(0, 4, 0, 4)
    $sep.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BorderBrush")
    return $sep
}

# ── Populate OS card ─────────────────────────────────────────────
function Populate-OSInfo {
    param($os = $null)
    if (-not $os) { $os = Get-CimInstance Win32_OperatingSystem }
    $uptime = (Get-Date) - $os.LastBootUpTime

    $sysOS.Text       = $os.Caption + " " + $os.OSArchitecture
    $sysBuild.Text    = $os.BuildNumber + "  (" + $os.Version + ")"
    $sysComputer.Text = $env:COMPUTERNAME
    $sysUser.Text     = $env:USERNAME
    $sysUptime.Text   = [string]$uptime.Days + "d " + [string]$uptime.Hours + "h " + [string]$uptime.Minutes + "m"
}

# ── Populate Hardware card ────────────────────────────────────────
function Populate-HardwareInfo {
    param($os = $null)
    Set-BusyStatus "Gathering hardware info..."

    if (-not $os) { $os = Get-CimInstance Win32_OperatingSystem }
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $ram = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $gpu = (Get-CimInstance Win32_VideoController | Select-Object -First 1).Name

    $hwCPU.Text   = $cpu.Name.Trim()
    $hwCores.Text = [string]$cpu.NumberOfCores + " cores / " + [string]$cpu.NumberOfLogicalProcessors + " threads"
    $hwRAM.Text   = [string]$ram + " GB"
    $hwGPU.Text   = $gpu.Trim()

    Set-ReadyStatus
}

# ── Populate Drives card ──────────────────────────────────────────
function Populate-DriveInfo {
    $diskPanel.Children.Clear()
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $null -ne $_.Used }
    $alt    = $false
    foreach ($d in $drives) {
        $total    = $d.Used + $d.Free
        $free     = [math]::Round($d.Free / 1GB, 1)
        $tot      = [math]::Round($total / 1GB, 1)
        $pct      = if ($total -gt 0) { $d.Free / $total } else { 1 }
        $colorKey = if ($pct -lt 0.10) { "DangerBrush" } elseif ($pct -lt 0.20) { "WarningBrush" } else { "FgBrush" }
        $row      = New-InfoRow ($d.Name + ":\") ([string]$free + " GB free of " + [string]$tot + " GB") $colorKey $alt
        $diskPanel.Children.Add($row) | Out-Null
        $alt = -not $alt
    }
}

# ── Populate Network card ─────────────────────────────────────────
function Populate-NetInfo {
    $netPanel.Children.Clear()
    try {
        $adapters  = Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }
        $addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                     Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.PrefixOrigin -ne 'WellKnown' }
        $routes    = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
        $dnsAll    = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue

        $active = @(foreach ($a in $adapters) {
            $ipv4 = $addresses | Where-Object { $_.InterfaceIndex -eq $a.InterfaceIndex } | Select-Object -First 1
            if (-not $ipv4) { continue }
            [PSCustomObject]@{
                Alias   = $a.Name
                IP      = $ipv4.IPAddress + "/" + $ipv4.PrefixLength
                Gateway = $(($routes | Where-Object { $_.InterfaceIndex -eq $a.InterfaceIndex } | Select-Object -First 1).NextHop)
                DNS     = $(($dnsAll | Where-Object { $_.InterfaceIndex -eq $a.InterfaceIndex }).ServerAddresses -join ", ")
            }
        })

        if ($active.Count -eq 0) {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text     = "No active network adapters found."
            $tb.FontSize = 12
            $tb.Margin   = [System.Windows.Thickness]::new(4, 2, 0, 2)
            $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
            $netPanel.Children.Add($tb) | Out-Null
            return
        }

        $first = $true
        foreach ($cfg in $active) {
            if (-not $first) { $netPanel.Children.Add((New-Separator)) | Out-Null }
            $first = $false

            $netPanel.Children.Add((New-AdapterHeader $cfg.Alias)) | Out-Null
            $netPanel.Children.Add((New-InfoRow "IP Address" $cfg.IP "FgBrush" $false)) | Out-Null

            $gw = if ($cfg.Gateway) { $cfg.Gateway } else { "N/A" }
            $netPanel.Children.Add((New-InfoRow "Gateway" $gw "FgBrush" $true)) | Out-Null

            $dns = if ($cfg.DNS) { $cfg.DNS } else { "N/A" }
            $netPanel.Children.Add((New-InfoRow "DNS" $dns "FgBrush" $false)) | Out-Null
        }
    } catch {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text     = "Could not retrieve network info: " + $_.Exception.Message
        $tb.FontSize = 12
        $tb.Margin   = [System.Windows.Thickness]::new(4, 2, 0, 2)
        $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "DangerBrush")
        $netPanel.Children.Add($tb) | Out-Null
    }
}

# ── Refresh All (background job) ──────────────────────────────────
function Populate-SysInfo {
    Set-BusyStatus "Gathering system info..."

    Start-ScyJob `
        -Work {
            param($emit)
            $os  = Get-CimInstance Win32_OperatingSystem
            $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
            $gpu = (Get-CimInstance Win32_VideoController | Select-Object -First 1).Name

            $uptime = (Get-Date) - $os.LastBootUpTime
            $ram    = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $null -ne $_.Used }

            $adapters  = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
            $addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                         Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.PrefixOrigin -ne 'WellKnown' }
            $routes    = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
            $dnsAll    = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue

            $netData = @(foreach ($a in $adapters) {
                $ipv4 = $addresses | Where-Object { $_.InterfaceIndex -eq $a.InterfaceIndex } | Select-Object -First 1
                if (-not $ipv4) { continue }
                [PSCustomObject]@{
                    Alias   = $a.Name
                    IP      = $ipv4.IPAddress + "/" + $ipv4.PrefixLength
                    Gateway = $(($routes | Where-Object { $_.InterfaceIndex -eq $a.InterfaceIndex } | Select-Object -First 1).NextHop)
                    DNS     = $(($dnsAll | Where-Object { $_.InterfaceIndex -eq $a.InterfaceIndex }).ServerAddresses -join ", ")
                }
            })

            $driveData = @(foreach ($d in $drives) {
                $total = $d.Used + $d.Free
                $free  = [math]::Round($d.Free / 1GB, 1)
                $tot   = [math]::Round($total / 1GB, 1)
                $pct   = if ($total -gt 0) { $d.Free / $total } else { 1 }
                [PSCustomObject]@{
                    Name     = $d.Name + ":\"
                    Label    = [string]$free + " GB free of " + [string]$tot + " GB"
                    ColorKey = if ($pct -lt 0.10) { "DangerBrush" } elseif ($pct -lt 0.20) { "WarningBrush" } else { "FgBrush" }
                }
            })

            return @{
                OsCaption    = $os.Caption
                OsArch       = $os.OSArchitecture
                OsBuild      = $os.BuildNumber
                OsVersion    = $os.Version
                Uptime       = $uptime
                CpuName      = $cpu.Name.Trim()
                CpuCores     = $cpu.NumberOfCores
                CpuThreads   = $cpu.NumberOfLogicalProcessors
                Ram          = $ram
                GpuName      = $gpu.Trim()
                DriveData    = $driveData
                NetData      = $netData
            }
        } `
        -OnComplete {
            param($d, $err, $ctx)
            if ($err) {
                Set-ReadyStatus
                return
            }

            # OS card
            $sysOS.Text       = $d.OsCaption + " " + $d.OsArch
            $sysBuild.Text    = $d.OsBuild + "  (" + $d.OsVersion + ")"
            $sysComputer.Text = $env:COMPUTERNAME
            $sysUser.Text     = $env:USERNAME
            $sysUptime.Text   = [string]$d.Uptime.Days + "d " + [string]$d.Uptime.Hours + "h " + [string]$d.Uptime.Minutes + "m"

            # Hardware card
            $hwCPU.Text   = $d.CpuName
            $hwCores.Text = [string]$d.CpuCores + " cores / " + [string]$d.CpuThreads + " threads"
            $hwRAM.Text   = [string]$d.Ram + " GB"
            $hwGPU.Text   = $d.GpuName

            # Drives card
            $diskPanel.Children.Clear()
            $alt = $false
            foreach ($dd in $d.DriveData) {
                $diskPanel.Children.Add((New-InfoRow $dd.Name $dd.Label $dd.ColorKey $alt)) | Out-Null
                $alt = -not $alt
            }

            # Network card
            $netPanel.Children.Clear()
            if ($d.NetData.Count -eq 0) {
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text     = "No active network adapters found."
                $tb.FontSize = 12
                $tb.Margin   = [System.Windows.Thickness]::new(4, 2, 0, 2)
                $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                $netPanel.Children.Add($tb) | Out-Null
            } else {
                $first = $true
                foreach ($cfg in $d.NetData) {
                    if (-not $first) { $netPanel.Children.Add((New-Separator)) | Out-Null }
                    $first = $false

                    $netPanel.Children.Add((New-AdapterHeader $cfg.Alias)) | Out-Null
                    $netPanel.Children.Add((New-InfoRow "IP Address" $cfg.IP "FgBrush" $false)) | Out-Null

                    $gw = if ($cfg.Gateway) { $cfg.Gateway } else { "N/A" }
                    $netPanel.Children.Add((New-InfoRow "Gateway" $gw "FgBrush" $true)) | Out-Null

                    $dns = if ($cfg.DNS) { $cfg.DNS } else { "N/A" }
                    $netPanel.Children.Add((New-InfoRow "DNS" $dns "FgBrush" $false)) | Out-Null
                }
            }

            Set-ReadyStatus
        } | Out-Null
}

(Find "BtnSysInfo").Add_Click({      Populate-SysInfo      })
(Find "BtnOSInfo").Add_Click({       Populate-OSInfo       })
(Find "BtnHardwareInfo").Add_Click({ Populate-HardwareInfo })
(Find "BtnDriveInfo").Add_Click({    Populate-DriveInfo    })
(Find "BtnNetworkInfo").Add_Click({  Populate-NetInfo      })

# ── Copy all hardware info button ─────────────────────────────────
$btnCopyHw     = Find "BtnCopyHardware"
$capturedHwBtn = $btnCopyHw
$btnCopyHw.Add_Click({
    $cpu   = (Find "HwCPU").Text
    $cores = (Find "HwCores").Text
    $ram   = (Find "HwRAM").Text
    $gpu   = (Find "HwGPU").Text
    $text  = "CPU: $cpu`nCores: $cores`nRAM: $ram`nGPU: $gpu"
    [System.Windows.Clipboard]::SetText($text)
    $capturedHwBtn.Content = "✓"
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromSeconds(1.5)
    $t.Tag = $capturedHwBtn
    $t.Add_Tick({
        $args[0].Tag.Content = "copy all"
        $args[0].Stop()
    })
    $t.Start()
}.GetNewClosure())
