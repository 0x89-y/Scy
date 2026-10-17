# ── System rail ───────────────────────────────────────────────
# Flat rail: Info's four blocks sit at the top level (they replace the old
# per-block load buttons), followed by the other sections.
$systemSectionInfo     = Find "SystemSection_Info"
$systemSectionCleanup  = Find "SystemSection_Cleanup"
$systemSectionBattery  = Find "SystemSection_Battery"
$systemSectionFirmware = Find "SystemSection_Firmware"
$systemSectionSfcDism  = Find "SystemSection_SfcDism"

$script:systemSections   = @($systemSectionInfo, $systemSectionCleanup, $systemSectionBattery, $systemSectionFirmware, $systemSectionSfcDism)
$script:systemNavLabels  = @("Info", "Cleanup", "Battery", "BIOS/UEFI", "SFC/DISM")

# Info blocks. Selecting one only shows it - it never gathers. The data comes
# from Populate-SysInfo, an async job started by each block's refresh button.
$script:sysInfoBlocks = @(
    @{ Label = "Operating system"; Block = "SysInfo_OS"       }
    @{ Label = "Hardware";         Block = "SysInfo_Hardware" }
    @{ Label = "Drives";           Block = "SysInfo_Drives"   }
    @{ Label = "Network adapters"; Block = "SysInfo_Network"  }
)

# Rail entries: Section = index into $systemSections, Info = index into $sysInfoBlocks
$script:systemRailItems = @()
for ($i = 0; $i -lt $script:sysInfoBlocks.Count; $i++) {
    $script:systemRailItems += @{ Label = $script:sysInfoBlocks[$i].Label; Section = 0; Info = $i }
}
for ($i = 1; $i -lt $script:systemNavLabels.Count; $i++) {
    $script:systemRailItems += @{ Label = $script:systemNavLabels[$i]; Section = $i; Info = -1 }
}
$script:systemRailIndex = 0

function Build-SystemRail {
    $panel = Find "SystemRail"
    if (-not $panel) { return }
    $panel.Children.Clear()
    for ($i = 0; $i -lt $script:systemRailItems.Count; $i++) {
        $idx = $i
        $panel.Children.Add(
            (New-RailEntry -Label $script:systemRailItems[$idx].Label `
                           -IsActive ($script:systemRailIndex -eq $idx) `
                           -OnClick ({ Set-SystemRail $idx }).GetNewClosure())) | Out-Null
    }
}

# Show only the selected Info block. Deliberately does no gathering.
function Apply-SysInfoFilter {
    param([int]$InfoIndex)
    for ($i = 0; $i -lt $script:sysInfoBlocks.Count; $i++) {
        $el = Find $script:sysInfoBlocks[$i].Block
        if ($el) { $el.Visibility = if ($i -eq $InfoIndex) { "Visible" } else { "Collapsed" } }
    }
}

function Set-SystemRail {
    param([int]$Index)
    if ($Index -lt 0 -or $Index -ge $script:systemRailItems.Count) { $Index = 0 }
    $script:systemRailIndex = $Index
    $item = $script:systemRailItems[$Index]

    $script:systemSubNavIndex = $item.Section
    for ($i = 0; $i -lt $script:systemSections.Count; $i++) {
        $script:systemSections[$i].Visibility = if ($i -eq $item.Section) { "Visible" } else { "Collapsed" }
    }
    if ($item.Section -eq 0) { Apply-SysInfoFilter $item.Info }

    # Nothing gathers on section entry - Battery and BIOS/UEFI load on demand via
    # their Refresh buttons, like the rest of the System tab.

    Build-SystemRail
}

# Back-compat shim: Global Search addresses System by section index.
function Set-SystemSubNav {
    param([int]$Index)
    for ($i = 0; $i -lt $script:systemRailItems.Count; $i++) {
        if ($script:systemRailItems[$i].Section -eq $Index) { Set-SystemRail $i; return }
    }
    Set-SystemRail 0
}

Set-SystemRail 0

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

# ── Refresh All (background job) ──────────────────────────────────
# Gathers OS, hardware, drives and network in one job and fills every Info block.
function Populate-SysInfo {
    Set-BusyStatus "Gathering system info..."
    Start-SysInfoLoad

    Start-ScyJob `
        -Work {
            param($emit)
            $os  = Get-CimInstance Win32_OperatingSystem
            $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
            # Every adapter (laptops often have an integrated + a dedicated GPU)
            $gpu = (@(Get-CimInstance Win32_VideoController | ForEach-Object { ([string]$_.Name).Trim() } | Where-Object { $_ }) -join ", ")

            $uptime = (Get-Date) - $os.LastBootUpTime
            # Installed RAM (sum of the modules); "visible" is lower by what the
            # firmware/GPU reserves, so only fall back to it.
            $installed = (Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object -Property Capacity -Sum).Sum
            $ram    = if ($installed) { [math]::Round($installed / 1GB, 1) } else { [math]::Round($os.TotalVisibleMemorySize / 1MB, 1) }
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
                Complete-SysInfoLoad $false
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

            Complete-SysInfoLoad $true
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

# Each Info block's header has a refresh icon next to its copy icon. They all
# force the same async re-gather (Populate-SysInfo fills every block in one job).
foreach ($__refreshBtn in @("BtnRefreshOS", "BtnRefreshHardware", "BtnRefreshDrives", "BtnRefreshNetwork")) {
    $__b = Find $__refreshBtn
    if ($__b) { $__b.Add_Click({ Populate-SysInfo; Populate-ExecPolicy }) }
}

# ── "Not loaded yet" state ───────────────────────────────────────
# Info only gathers when asked. Until the first load, each block shows a one-line
# hint with a Load button in place of its (empty) rows.
$script:sysInfoHints = @()
foreach ($__blk in $script:sysInfoBlocks) {
    $__stack = (Find $__blk.Block).Child
    $__hint = New-Object System.Windows.Controls.StackPanel
    $__hint.Orientation = "Horizontal"
    $__hint.Tag = "SysInfoNotLoaded"
    $__text = New-Object System.Windows.Controls.TextBlock
    $__text.Text = "Not loaded yet."
    $__text.FontSize = 12
    $__text.VerticalAlignment = "Center"
    $__text.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    $__load = New-Object System.Windows.Controls.Button
    $__load.Content = "Load"
    $__load.Style = $window.Resources["SecondaryButton"]
    $__load.FontSize = 11
    $__load.Padding = [System.Windows.Thickness]::new(10, 3, 10, 3)
    $__load.Margin = [System.Windows.Thickness]::new(10, 0, 0, 0)
    $__load.Add_Click({ Populate-SysInfo; Populate-ExecPolicy })
    $__hint.Children.Add($__text) | Out-Null
    $__hint.Children.Add($__load) | Out-Null
    $__stack.Children.Insert(1, $__hint)
    $script:sysInfoHints += @{ Text = $__text; Button = $__load }
}

# Loaded: show the rows, hide the hint. Not loaded: the reverse. $Message
# replaces the hint text (e.g. while loading or after a failure).
function Set-SysInfoLoaded {
    param([bool]$Loaded, [string]$Message = "Not loaded yet.", [bool]$Busy = $false)
    foreach ($blk in $script:sysInfoBlocks) {
        $stack = (Find $blk.Block).Child
        for ($i = 1; $i -lt $stack.Children.Count; $i++) {
            $isHint = ($stack.Children[$i].Tag -eq "SysInfoNotLoaded")
            $stack.Children[$i].Visibility = if ($isHint -ne $Loaded) { "Visible" } else { "Collapsed" }
        }
    }
    foreach ($h in $script:sysInfoHints) {
        $h.Text.Text = $Message
        $h.Button.IsEnabled = -not $Busy
    }
    $script:sysInfoLoaded = $Loaded
}
Set-SysInfoLoaded $false

# Called by Populate-SysInfo. A refresh after the first load keeps showing the
# old values while it runs; only the very first load shows "Loading...".
function Start-SysInfoLoad {
    if (-not $script:sysInfoLoaded) { Set-SysInfoLoaded $false "Loading..." $true }
}
function Complete-SysInfoLoad {
    param([bool]$Ok)
    if ($Ok) { Set-SysInfoLoaded $true }
    elseif (-not $script:sysInfoLoaded) { Set-SysInfoLoaded $false "Couldn't load system info." }
}

# ── Copy-all buttons (OS, Hardware, Drives, Network) ─────────────
function Invoke-CopyAllFlash {
    param([System.Windows.Controls.Button]$Button, [string]$Text)
    [System.Windows.Clipboard]::SetText($Text)
    # Briefly show a checkmark, then put back what the button showed. The copy
    # buttons use the Segoe MDL2 icon font, which has its own checkmark glyph.
    $check = if ($Button.FontFamily.Source -eq "Segoe MDL2 Assets") { [string][char]0xE73E } else { [string][char]0x2713 }
    if ([string]$Button.Content -eq $check) { return }   # already flashing
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromSeconds(1.5)
    $t.Tag = @{ Button = $Button; Content = $Button.Content }
    $Button.Content = $check
    $t.Add_Tick({
        $args[0].Tag.Button.Content = $args[0].Tag.Content
        $args[0].Stop()
    })
    $t.Start()
}

(Find "BtnCopyOS").Add_Click({
    $lines = @(
        "OS: "        + (Find "SysOS").Text
        "Build: "     + (Find "SysBuild").Text
        "Computer: "  + (Find "SysComputer").Text
        "User: "      + (Find "SysUser").Text
        "Uptime: "    + (Find "SysUptime").Text
        "PS policy: " + (Find "SysExecPolicy").Text
    )
    Invoke-CopyAllFlash -Button $this -Text ($lines -join "`n")
})

(Find "BtnCopyHardware").Add_Click({
    $lines = @(
        "CPU: "   + (Find "HwCPU").Text
        "Cores: " + (Find "HwCores").Text
        "RAM: "   + (Find "HwRAM").Text
        "GPU: "   + (Find "HwGPU").Text
    )
    Invoke-CopyAllFlash -Button $this -Text ($lines -join "`n")
})

(Find "BtnCopyDrives").Add_Click({
    $panel = Find "DiskPanel"
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($child in $panel.Children) {
        if ($child -isnot [System.Windows.Controls.Border]) { continue }
        $grid = $child.Child
        if ($grid -isnot [System.Windows.Controls.Grid]) { continue }
        $label = $null
        $value = $null
        foreach ($c in $grid.Children) {
            if ($c -is [System.Windows.Controls.TextBlock]) {
                if ($null -eq $label) { $label = $c.Text } else { $value = $c.Text }
            }
        }
        if ($label -and $value) { $lines.Add(("{0,-12} {1}" -f $label, $value)) }
    }
    if ($lines.Count -eq 0) { $lines.Add("(no drive info loaded)") }
    Invoke-CopyAllFlash -Button $this -Text ($lines -join "`n")
})

(Find "BtnCopyNetwork").Add_Click({
    $panel = Find "NetAdapterPanel"
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($child in $panel.Children) {
        if ($child -is [System.Windows.Controls.TextBlock]) {
            $lines.Add($child.Text)
        } elseif ($child -is [System.Windows.Controls.Border]) {
            $grid = $child.Child
            if ($grid -is [System.Windows.Controls.Grid]) {
                $label = $null; $value = $null
                foreach ($c in $grid.Children) {
                    if ($c -is [System.Windows.Controls.TextBlock]) {
                        if ($null -eq $label) { $label = $c.Text } else { $value = $c.Text }
                    }
                }
                if ($label -and $value) { $lines.Add(("{0,-12} {1}" -f $label, $value)) }
            } elseif ($grid -is [System.Windows.Controls.TextBlock]) {
                $lines.Add($grid.Text)
            }
        }
    }
    if ($lines.Count -eq 0) { $lines.Add("(no network info loaded)") }
    Invoke-CopyAllFlash -Button $this -Text ($lines -join "`n")
})
