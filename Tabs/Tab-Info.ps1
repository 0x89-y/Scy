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
$sysOS         = Find "SysOS"
$sysBuild      = Find "SysBuild"
$sysComputer   = Find "SysComputer"
$sysUser       = Find "SysUser"
$sysUptime     = Find "SysUptime"
$sysExecPolicy = Find "SysExecPolicy"
$hwCPU       = Find "HwCPU"
$hwCores     = Find "HwCores"
$hwRAM       = Find "HwRAM"
$hwGPU       = Find "HwGPU"
$diskPanel   = Find "DiskPanel"
$netPanel    = Find "NetAdapterPanel"

# Card helpers (New-InfoRow / New-AdapterHeader / New-Separator) live in
# Helpers\Helpers-Cards.ps1 and are dot-sourced from Scy.ps1.

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

    $smartMap = @{}
    try {
        $partitions = Get-Partition -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter }
        foreach ($p in $partitions) {
            try {
                $disk = $p | Get-Disk -ErrorAction Stop
                $phys = Get-PhysicalDisk -DeviceNumber $disk.Number -ErrorAction Stop
                $smartMap[[string]$p.DriveLetter] = $phys.HealthStatus
            } catch { }
        }
    } catch { }

    $alt = $false
    foreach ($d in $drives) {
        $total    = $d.Used + $d.Free
        $free     = [math]::Round($d.Free / 1GB, 1)
        $tot      = [math]::Round($total / 1GB, 1)
        $pct      = if ($total -gt 0) { $d.Free / $total } else { 1 }
        $colorKey = if ($pct -lt 0.10) { "DangerBrush" } elseif ($pct -lt 0.20) { "WarningBrush" } else { "FgBrush" }
        $row      = New-InfoRow ($d.Name + ":\") ([string]$free + " GB free of " + [string]$tot + " GB") $colorKey $alt
        $diskPanel.Children.Add($row) | Out-Null
        $alt = -not $alt

        $status = $smartMap[[string]$d.Name]
        $smartColor = switch ([string]$status) {
            'Healthy'   { 'SuccessBrush' }
            'Warning'   { 'WarningBrush' }
            'Unhealthy' { 'DangerBrush' }
            default     { 'MutedText' }
        }
        $smartText = if ($status) { [string]$status } else { 'Unknown' }
        $diskPanel.Children.Add((New-InfoRow "  SMART" $smartText $smartColor $alt)) | Out-Null
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

            $smartMap = @{}
            try {
                $partitions = Get-Partition -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter }
                foreach ($p in $partitions) {
                    try {
                        $disk = $p | Get-Disk -ErrorAction Stop
                        $phys = Get-PhysicalDisk -DeviceNumber $disk.Number -ErrorAction Stop
                        $smartMap[[string]$p.DriveLetter] = $phys.HealthStatus
                    } catch { }
                }
            } catch { }

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

                $status = $smartMap[[string]$d.Name]
                $smartColor = switch ([string]$status) {
                    'Healthy'   { 'SuccessBrush' }
                    'Warning'   { 'WarningBrush' }
                    'Unhealthy' { 'DangerBrush' }
                    default     { 'MutedText' }
                }
                $smartText = if ($status) { [string]$status } else { 'Unknown' }

                [PSCustomObject]@{
                    Name          = $d.Name + ":\"
                    Label         = [string]$free + " GB free of " + [string]$tot + " GB"
                    ColorKey      = if ($pct -lt 0.10) { "DangerBrush" } elseif ($pct -lt 0.20) { "WarningBrush" } else { "FgBrush" }
                    SmartStatus   = $smartText
                    SmartColorKey = $smartColor
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
                $diskPanel.Children.Add((New-InfoRow "  SMART" $dd.SmartStatus $dd.SmartColorKey $alt)) | Out-Null
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

# Shows the persistent PS execution policy (skips the Process scope, which is whatever Scy was launched with).
# Tooltip lists all scopes for full context.
function Populate-ExecPolicy {
    try {
        $list = Get-ExecutionPolicy -List
        $persistent      = $null
        $persistentScope = $null
        foreach ($entry in $list) {
            $scopeStr = [string]$entry.Scope
            if ($scopeStr -eq 'Process') { continue }
            $polStr = [string]$entry.ExecutionPolicy
            if ($polStr -ne 'Undefined') {
                $persistent      = $polStr
                $persistentScope = $scopeStr
                break
            }
        }
        if (-not $persistent) {
            $persistent      = 'Restricted'   # implicit default when every persistent scope is Undefined
            $persistentScope = 'default'
        }
        $sysExecPolicy.Text    = "$persistent ($persistentScope)"
        $sysExecPolicy.ToolTip = ($list | ForEach-Object { '{0,-15} {1}' -f $_.Scope, $_.ExecutionPolicy }) -join "`n"
        $brushKey = switch ($persistent) {
            'Restricted'    { 'SuccessBrush' }
            'AllSigned'     { 'SuccessBrush' }
            'RemoteSigned'  { 'FgBrush' }
            'Unrestricted'  { 'WarningBrush' }
            'Bypass'        { 'DangerBrush' }
            default         { 'FgBrush' }
        }
        $sysExecPolicy.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $brushKey)
    } catch {
        $sysExecPolicy.Text = 'Error'
        $sysExecPolicy.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'DangerBrush')
    }
}

(Find "BtnSysInfo").Add_Click({      Populate-SysInfo; Populate-ExecPolicy })
(Find "BtnOSInfo").Add_Click({       Populate-OSInfo       })
(Find "BtnHardwareInfo").Add_Click({ Populate-HardwareInfo })
(Find "BtnDriveInfo").Add_Click({    Populate-DriveInfo    })
(Find "BtnNetworkInfo").Add_Click({  Populate-NetInfo      })
(Find "BtnExecPolicy").Add_Click({   Populate-ExecPolicy   })

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
