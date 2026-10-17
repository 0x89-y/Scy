# -- Network Tools Tab ----------------------------------------------------------

# -- Network rail --------------------------------------------------------------
# Flat rail: the three Diagnostics tools sit at the top level alongside the
# other sections (no "Diagnostics" parent entry).
$script:netNavLabels = @("Diagnostics", "Wi-Fi", "Hosts", "DNS", "SSH")

$netSectionDiagnostics = Find "NetSection_Diagnostics"
$netSectionWifi        = Find "NetSection_Wifi"
$netSectionHosts       = Find "NetSection_Hosts"
$netSectionDNS         = Find "NetSection_DNS"
$netSectionSSH         = Find "NetSection_SSH"

$script:netSections   = @($netSectionDiagnostics, $netSectionWifi, $netSectionHosts, $netSectionDNS, $netSectionSSH)

$script:netDiagLabels  = @("Ping & traceroute", "Speed test", "NSLookup")
$script:netDiagFilter  = $script:netDiagLabels[0]

# Rail entries: Section = index into $netSections, Tool = diagnostics tool (or $null)
$script:netRailItems = @(
    @{ Label = "Ping & traceroute"; Section = 0; Tool = "Ping & traceroute" }
    @{ Label = "Speed test";        Section = 0; Tool = "Speed test"        }
    @{ Label = "NSLookup";          Section = 0; Tool = "NSLookup"          }
    @{ Label = "Wi-Fi";             Section = 1; Tool = $null               }
    @{ Label = "Hosts";             Section = 2; Tool = $null               }
    @{ Label = "DNS";               Section = 3; Tool = $null               }
    @{ Label = "SSH";               Section = 4; Tool = $null               }
)
$script:netRailIndex = 0

function Get-NetDiagSections {
    return @((Find "NetDiag_Ping"), (Find "NetDiag_Speed"), (Find "NetDiag_NSLookup"))
}

# Show only the selected diagnostics tool.
function Apply-NetDiagFilter {
    $sections = Get-NetDiagSections
    for ($i = 0; $i -lt $sections.Count; $i++) {
        if (-not $sections[$i]) { continue }
        $sections[$i].Visibility =
            if ($script:netDiagLabels[$i] -eq $script:netDiagFilter) { "Visible" } else { "Collapsed" }
    }
}

# Flat rail: plain entries, styled like every other single-level rail.
function Build-NetRail {
    $panel = Find "NetRail"
    if (-not $panel) { return }
    $panel.Children.Clear()

    for ($i = 0; $i -lt $script:netRailItems.Count; $i++) {
        $idx = $i
        $panel.Children.Add(
            (New-RailEntry -Label $script:netRailItems[$idx].Label `
                           -IsActive ($script:netRailIndex -eq $idx) `
                           -OnClick ({ Set-NetRail $idx }).GetNewClosure())) | Out-Null
    }
}

# Select a rail entry: show its section, and (for diagnostics) just its tool.
function Set-NetRail {
    param([int]$Index)
    if ($Index -lt 0 -or $Index -ge $script:netRailItems.Count) { $Index = 0 }
    $script:netRailIndex = $Index
    $item = $script:netRailItems[$Index]

    $script:netSubNavIndex = $item.Section
    for ($i = 0; $i -lt $script:netSections.Count; $i++) {
        $script:netSections[$i].Visibility = if ($i -eq $item.Section) { "Visible" } else { "Collapsed" }
    }
    if ($item.Tool) { $script:netDiagFilter = $item.Tool }

    Apply-NetDiagFilter
    Build-NetRail
}

# Back-compat shim: Global Search still addresses Network by section index
# (0 = Diagnostics, 1 = Wi-Fi, ...). Map that to the first matching rail entry.
function Set-NetSubNav {
    param([int]$Index)
    for ($i = 0; $i -lt $script:netRailItems.Count; $i++) {
        if ($script:netRailItems[$i].Section -eq $Index) { Set-NetRail $i; return }
    }
    Set-NetRail 0
}

$script:netSubNavIndex = 0
Set-NetRail 0

$netHostBox         = Find "NetHostBox"
$netHostPlaceholder = Find "NetHostPlaceholder"
$netWifiPanel       = Find "NetWifiPanel"
$btnNetPing         = Find "BtnNetPing"
$btnNetTrace        = Find "BtnNetTrace"
$btnNetSpeed        = Find "BtnNetSpeed"
$btnNetWifi         = Find "BtnNetWifi"
$btnNetStop         = Find "BtnNetStop"

# -- Speed test server list --------------------------------------------------
# Automatic uses Cloudflare's speed-test service (nearest location, also measures
# upload); the others are plain test files, download only. Cloudflare has no
# Url: its endpoints are built in the test job. Streams is how many parallel
# downloads the host allows per IP - Hetzner answers more than 2 with HTTP 429,
# OVH more than 4.
$script:speedServers = [ordered]@{
    "Automatic (Cloudflare, nearest)" = @{ Cloudflare = $true;  Url = $null; Streams = 8 }
    "Hetzner FSN1 (DE)"               = @{ Cloudflare = $false; Url = "https://fsn1-speed.hetzner.com/1GB.bin"; Streams = 2 }
    "Hetzner NBG1 (DE)"               = @{ Cloudflare = $false; Url = "https://nbg1-speed.hetzner.com/1GB.bin"; Streams = 2 }
    "Hetzner HEL1 (FI)"               = @{ Cloudflare = $false; Url = "https://hel1-speed.hetzner.com/1GB.bin"; Streams = 2 }
    "Hetzner ASH (USA)"               = @{ Cloudflare = $false; Url = "https://ash-speed.hetzner.com/1GB.bin"; Streams = 2 }
    "Hetzner HIL (USA)"               = @{ Cloudflare = $false; Url = "https://hil-speed.hetzner.com/1GB.bin"; Streams = 2 }
    "Hetzner SIN (Singapore)"         = @{ Cloudflare = $false; Url = "https://sin-speed.hetzner.com/1GB.bin"; Streams = 2 }
    "OVH RBX (France)"                = @{ Cloudflare = $false; Url = "https://proof.ovh.net/files/1Gb.dat"; Streams = 4 }
    "OVH BHS (Canada)"                = @{ Cloudflare = $false; Url = "https://proof.ovh.ca/files/1Gb.dat"; Streams = 4 }
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

# Stop flag for ping/traceroute: the Stop button sets it, the job checks it
# between probes (a synchronized hashtable is shared safely across runspaces)
$script:netCancel = [hashtable]::Synchronized(@{ Stop = $false })

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
    $footerStatus.Text          = "Scy - $msg"
    $btnNetPing.IsEnabled       = $false
    $btnNetTrace.IsEnabled      = $false
    $btnNetStop.IsEnabled       = $true
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Set-NetReady {
    $footerStatus.Text          = "Ready"
    $btnNetPing.IsEnabled       = $true
    $btnNetTrace.IsEnabled      = $true
    $btnNetStop.IsEnabled       = $false
}

# -- Ping / traceroute: text forms --------------------------------------------
# Both use .NET's Ping class instead of ping.exe / tracert.exe: those print
# localized text in the console code page, which came through garbled (umlauts
# in the German timeout message turned into replacement characters). The Ping
# class returns status codes and numbers, so the results view below is built
# from data, and these functions give the plain-text form used by Copy.
# They are unit-tested.

# "DestinationHostUnreachable" -> "Destination host unreachable"
function ConvertTo-PingStatusText {
    param([string]$Status)
    $words = ($Status -creplace '(?<=[a-z])(?=[A-Z])', ' ').ToLower()
    if (-not $words) { return "Unknown error" }
    return $words.Substring(0, 1).ToUpper() + $words.Substring(1)
}

function Format-PingReply {
    param([string]$Status, [string]$Address, [long]$Time, [int]$Ttl)
    switch ($Status) {
        "Success"  { return "Reply from ${Address}: $Time ms" + $(if ($Ttl -gt 0) { ", TTL $Ttl" } else { "" }) }
        "TimedOut" { return "Request timed out" }
        default {
            $text = ConvertTo-PingStatusText $Status
            if ($Address -and $Address -ne "0.0.0.0" -and $Address -ne "::") { return "Reply from ${Address}: $($text.ToLower())" }
            return $text
        }
    }
}

# Numbers for a ping run. $Times are the round-trip times of the replies.
function Get-PingStats {
    param([int]$Sent, [long[]]$Times = @())
    $times    = @($Times)
    $received = $times.Count
    $stats = @{
        Sent = $Sent; Received = $received; Lost = $Sent - $received
        Loss = if ($Sent -gt 0) { [int][math]::Round(100 * ($Sent - $received) / $Sent) } else { 0 }
        Min  = $null; Avg = $null; Max = $null
    }
    if ($received -gt 0) {
        $m = $times | Measure-Object -Minimum -Maximum -Average
        $stats.Min = [long]$m.Minimum; $stats.Avg = [long][math]::Round($m.Average); $stats.Max = [long]$m.Maximum
    }
    return $stats
}

# Summary lines after a ping run (text form)
function Get-PingSummary {
    param([int]$Sent, [long[]]$Times = @())
    $s     = Get-PingStats -Sent $Sent -Times $Times
    $lines = @("Sent $($s.Sent), received $($s.Received), lost $($s.Lost) ($($s.Loss)% loss)")
    if ($s.Received -gt 0) { $lines += "Min $($s.Min) ms, avg $($s.Avg) ms, max $($s.Max) ms" }
    return ,$lines
}

# One traceroute hop: "  3   12 ms       *   10 ms    79.127.195.209"
# $Times holds one entry per probe: a round-trip time, or $null for no answer.
function Format-TraceHop {
    param([int]$Hop, [object[]]$Times, [string]$Address)
    $cols = foreach ($t in @($Times)) { if ($null -eq $t) { "{0,8}" -f "*" } else { "{0,8}" -f "$t ms" } }
    $where = if ($Address) { $Address } else { "Request timed out" }
    return ("{0,3}" -f $Hop) + ($cols -join "") + "    " + $where
}

# -- Ping / traceroute: results view ------------------------------------------
# A stats line (ping), a column header, one row per reply or hop, and a footer.
# All state lives in $script:netProbe; the job callbacks only call these functions.
$netProbeTitle   = Find "NetProbeTitle"
$netProbeStats   = Find "NetProbeStats"
$netProbeHeader  = Find "NetProbeHeader"
$netProbeRows    = Find "NetProbeRows"
$netProbeFooter  = Find "NetProbeFooter"
$btnNetProbeCopy = Find "BtnNetProbeCopy"
$script:netProbe = @{ Mode = $null; Lines = @(); Sent = 0; Times = @(); Bars = @() }

# Column widths per mode; "*" takes the rest
$script:netProbeColumns = @{
    Ping  = @(36, "*", 70, 150, 64)        # #, result, time, latency bar, TTL
    Trace = @(36, "*", 70, 70, 70)         # hop, address, three probes
}

function New-NetProbeText {
    param([string]$Text, [string]$Brush = "FgBrush", [string]$Align = "Left", [switch]$Bold, [double]$Size = 12)
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Text
    $tb.FontSize = $Size
    $tb.TextAlignment = $Align
    $tb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $tb.VerticalAlignment = "Center"
    if ($Bold) { $tb.FontWeight = [System.Windows.FontWeights]::SemiBold }
    $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $Brush)
    return $tb
}

# A grid row with one element per column: of the current ping/trace mode, or
# $Widths when given (NSLookup uses the same rows)
function New-NetProbeRow {
    param([object[]]$Cells, [double]$Padding = 4, [object[]]$Widths)
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = [System.Windows.Thickness]::new(0, $Padding, 0, $Padding)
    $cols = if ($Widths) { $Widths } else { $script:netProbeColumns[$script:netProbe.Mode] }
    for ($i = 0; $i -lt $cols.Count; $i++) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = if ($cols[$i] -eq "*") { [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) } else { [System.Windows.GridLength]::new([double]$cols[$i]) }
        $grid.ColumnDefinitions.Add($cd)
        if ($i -lt $Cells.Count -and $Cells[$i]) {
            $cell = $Cells[$i]
            if ($i -gt 0) { $cell.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0) }
            [System.Windows.Controls.Grid]::SetColumn($cell, $i)
            $grid.Children.Add($cell) | Out-Null
        }
    }
    return $grid
}

# Back to the empty state, showing $Message
function Reset-NetProbe {
    param([string]$Message = "Enter a host above and click Ping or Traceroute.")
    $script:netProbe = @{ Mode = $null; Lines = @(); Sent = 0; Times = @(); Bars = @() }
    $netProbeTitle.Text = $Message
    $netProbeTitle.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    $netProbeStats.Children.Clear();  $netProbeStats.Visibility  = "Collapsed"
    $netProbeHeader.Child = $null;    $netProbeHeader.Visibility = "Collapsed"
    $netProbeRows.Children.Clear()
    $netProbeFooter.Visibility = "Collapsed"
    $btnNetProbeCopy.Visibility = "Collapsed"
}

function Start-NetProbeView {
    param([string]$Mode, [string]$Label)
    Reset-NetProbe
    $script:netProbe.Mode = $Mode
    $netProbeTitle.Text = if ($Mode -eq "Ping") { "Pinging $Label" } else { "Tracing route to $Label (max 30 hops)" }
    $netProbeTitle.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
    $script:netProbe.Lines += if ($Mode -eq "Ping") { "Pinging $Label with 32 bytes of data:" } else { "Tracing route to $Label (max 30 hops):" }
    $script:netProbe.Lines += ""

    $labels = if ($Mode -eq "Ping") { @("#", "Result", "Time", "", "TTL") } else { @("Hop", "Address", "1", "2", "3") }
    $cells = for ($i = 0; $i -lt $labels.Count; $i++) {
        New-NetProbeText $labels[$i] "MutedText" $(if ($i -ge 2) { "Right" } else { "Left" }) -Size 11
    }
    $netProbeHeader.Child = New-NetProbeRow -Cells $cells -Padding 0
    $netProbeHeader.Visibility = "Visible"
    if ($Mode -eq "Ping") { Update-NetPingStats }
}

# The stats line: label/value pairs, loss colored by how bad it is
function Update-NetPingStats {
    $s = Get-PingStats -Sent $script:netProbe.Sent -Times $script:netProbe.Times
    $netProbeStats.Children.Clear()
    # Leading commas keep each pair a 3-item array (not flattened into the list)
    $pairs = @(
        ,@("Sent", "$($s.Sent)", "FgBrush")
        ,@("Received", "$($s.Received)", "FgBrush")
        ,@("Loss", "$($s.Loss)%", $(if ($s.Sent -eq 0 -or $s.Loss -eq 0) { "FgBrush" } elseif ($s.Loss -lt 100) { "WarningBrush" } else { "DangerBrush" }))
    )
    if ($s.Received -gt 0) { $pairs += ,@("Min", "$($s.Min) ms", "FgBrush"); $pairs += ,@("Avg", "$($s.Avg) ms", "FgBrush"); $pairs += ,@("Max", "$($s.Max) ms", "FgBrush") }
    foreach ($p in $pairs) {
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Orientation = "Horizontal"
        $sp.Margin = [System.Windows.Thickness]::new(0, 0, 20, 0)
        $sp.Children.Add((New-NetProbeText $p[0] "MutedText")) | Out-Null
        $v = New-NetProbeText $p[1] $p[2] -Bold
        $v.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
        $sp.Children.Add($v) | Out-Null
        $netProbeStats.Children.Add($sp) | Out-Null
    }
    $netProbeStats.Visibility = "Visible"
}

# Latency bars are relative to the slowest reply so far
function Update-NetPingBars {
    $max = [math]::Max(1, (@($script:netProbe.Times) + 1 | Measure-Object -Maximum).Maximum)
    foreach ($b in $script:netProbe.Bars) {
        $b.Fill.Width = [math]::Max(3, [math]::Round(150 * $b.Time / $max))
    }
}

function Add-NetPingReply {
    param($m)
    $script:netProbe.Sent++
    $ok = ($m.Status -eq "Success")
    $result = if ($ok) { New-NetProbeText $m.Address } else { New-NetProbeText (Format-PingReply -Status $m.Status -Address $m.Address) "DangerBrush" }
    $time   = if ($ok) { New-NetProbeText "$($m.Time) ms" -Align Right } else { New-NetProbeText "-" "MutedText" -Align Right }
    $bar = $null
    if ($ok) {
        $script:netProbe.Times += [long]$m.Time
        $bar = New-Object System.Windows.Controls.Grid
        $bar.Height = 6; $bar.VerticalAlignment = "Center"
        $track = New-Object System.Windows.Controls.Border
        $track.CornerRadius = [System.Windows.CornerRadius]::new(3)
        $track.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BorderBrush")
        $fill = New-Object System.Windows.Controls.Border
        $fill.CornerRadius = [System.Windows.CornerRadius]::new(3)
        $fill.HorizontalAlignment = "Left"
        $fill.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "AccentBrush")
        $bar.Children.Add($track) | Out-Null
        $bar.Children.Add($fill) | Out-Null
        $script:netProbe.Bars += @{ Fill = $fill; Time = [long]$m.Time }
    }
    $ttl = if ($ok -and $m.Ttl -gt 0) { New-NetProbeText "$($m.Ttl)" "MutedText" -Align Right } else { $null }
    $netProbeRows.Children.Add((New-NetProbeRow -Cells @((New-NetProbeText "$($m.Seq)" "MutedText"), $result, $time, $bar, $ttl))) | Out-Null
    $script:netProbe.Lines += Format-PingReply -Status $m.Status -Address $m.Address -Time $m.Time -Ttl $m.Ttl
    Update-NetPingBars
    Update-NetPingStats
}

function Add-NetTraceHop {
    param($m)
    $where = New-Object System.Windows.Controls.StackPanel
    $where.VerticalAlignment = "Center"
    if ($m.Address) {
        $where.Children.Add((New-NetProbeText $m.Address)) | Out-Null
        if ($m.HostName) { $where.Children.Add((New-NetProbeText $m.HostName "MutedText" -Size 11)) | Out-Null }
    } else {
        $where.Children.Add((New-NetProbeText "No reply" "MutedText")) | Out-Null
    }
    $cells = @((New-NetProbeText "$($m.Hop)" "MutedText"), $where)
    foreach ($t in @($m.Times)) {
        $cells += if ($null -eq $t) { New-NetProbeText "*" "MutedText" -Align Right } else { New-NetProbeText "$t ms" -Align Right }
    }
    $netProbeRows.Children.Add((New-NetProbeRow -Cells $cells)) | Out-Null
    $addr = if ($m.HostName) { "$($m.HostName) [$($m.Address)]" } else { $m.Address }
    $script:netProbe.Lines += Format-TraceHop -Hop $m.Hop -Times $m.Times -Address $addr
}

# $Text: closing line ("Trace complete.", "Stopped.", ...) or $null
function Complete-NetProbe {
    param([string]$Text, [string]$Brush = "MutedText")
    if ($script:netProbe.Mode -eq "Ping" -and $script:netProbe.Sent -gt 0) {
        $script:netProbe.Lines += ""
        $script:netProbe.Lines += Get-PingSummary -Sent $script:netProbe.Sent -Times $script:netProbe.Times
    }
    if ($Text) {
        $netProbeFooter.Text = $Text
        $netProbeFooter.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $Brush)
        $netProbeFooter.Visibility = "Visible"
        $script:netProbe.Lines += ""
        $script:netProbe.Lines += $Text
    }
    if ($netProbeRows.Children.Count -gt 0) { $btnNetProbeCopy.Visibility = "Visible" }
}

$btnNetProbeCopy.Add_Click({
    Invoke-CopyAllFlash -Button $this -Text (($script:netProbe.Lines | Where-Object { $null -ne $_ }) -join "`r`n").Trim()
})

# -- Ping / traceroute job ----------------------------------------------------
# Resolves the host, then pings it ($Mode "Ping") or probes it hop by hop with
# rising TTLs ($Mode "Trace"). Sends plain data back; the view above draws it.
function Start-NetProbe {
    param([ValidateSet("Ping", "Trace")][string]$Mode, [string]$Target)

    $script:netCancel.Stop = $false
    Set-NetBusy $(if ($Mode -eq "Ping") { "Pinging $Target..." } else { "Tracing route to $Target..." })
    Reset-NetProbe $(if ($Mode -eq "Ping") { "Pinging $Target..." } else { "Tracing route to $Target..." })

    Start-ScyJob `
        -Variables @{ mode = $Mode; target = $Target; cancel = $script:netCancel } `
        -Context   @{ Mode = $Mode } `
        -Work {
            param($emit)
            # Resolve once (IPv4 preferred, like the classic tools) so every row
            # shows the address actually probed
            $ip = $null
            if (-not [System.Net.IPAddress]::TryParse($target, [ref]$ip)) {
                try {
                    $all = [System.Net.Dns]::GetHostAddresses($target)
                    $ip  = @($all | Where-Object { $_.AddressFamily -eq 'InterNetwork' }) + @($all) | Select-Object -First 1
                } catch { $ip = $null }
                if (-not $ip) { & $emit @{ Kind = 'error'; Text = "Could not find host '$target'. Check the name and try again." }; return }
            }
            $label = if ($ip.ToString() -eq $target) { $target } else { "$target [$ip]" }
            & $emit @{ Kind = 'start'; Label = $label }

            $pinger = [System.Net.NetworkInformation.Ping]::new()
            $buffer = [byte[]]::new(32)
            try {
                if ($mode -eq "Ping") {
                    for ($i = 0; $i -lt 4 -and -not $cancel.Stop; $i++) {
                        $started = [DateTime]::UtcNow
                        $r = $pinger.Send($ip, 2000, $buffer)
                        $ttl = if ($r.Options) { $r.Options.Ttl } else { 0 }
                        & $emit @{ Kind = 'reply'; Seq = $i + 1; Status = [string]$r.Status; Address = [string]$r.Address; Time = $r.RoundtripTime; Ttl = $ttl }
                        # One ping per second, like ping.exe; wake early on Stop
                        while ($i -lt 3 -and -not $cancel.Stop -and ([DateTime]::UtcNow - $started).TotalMilliseconds -lt 1000) { Start-Sleep -Milliseconds 50 }
                    }
                    & $emit @{ Kind = 'end'; Text = $(if ($cancel.Stop) { "Stopped." } else { $null }) }
                } else {
                    $reached = $false
                    $names = @{}
                    for ($ttl = 1; $ttl -le 30 -and -not $reached -and -not $cancel.Stop; $ttl++) {
                        $opts  = [System.Net.NetworkInformation.PingOptions]::new($ttl, $true)
                        $times = @(); $from = $null
                        for ($probe = 0; $probe -lt 3 -and -not $cancel.Stop; $probe++) {
                            $sw = [Diagnostics.Stopwatch]::StartNew()
                            $r  = $pinger.Send($ip, 1000, $buffer, $opts)
                            if ($r.Status -eq 'Success' -or $r.Status -eq 'TtlExpired') {
                                # RoundtripTime is 0 for TtlExpired replies; time it ourselves
                                $times += $sw.ElapsedMilliseconds
                                $from = [string]$r.Address
                                if ($r.Status -eq 'Success') { $reached = $true }
                            } else {
                                $times += $null
                            }
                        }
                        if ($cancel.Stop -and $times.Count -lt 3) { break }   # don't show a half-probed hop
                        # Reverse lookup, capped so a slow DNS server can't stall the trace
                        $hostName = $null
                        if ($from) {
                            if (-not $names.ContainsKey($from)) {
                                $names[$from] = $null
                                try {
                                    $task = [System.Net.Dns]::GetHostEntryAsync($from)
                                    if ($task.Wait(700) -and $task.Result.HostName -ne $from) { $names[$from] = $task.Result.HostName }
                                } catch { }
                            }
                            $hostName = $names[$from]
                        }
                        & $emit @{ Kind = 'hop'; Hop = $ttl; Times = $times; Address = $from; HostName = $hostName }
                    }
                    $end = if ($reached) { "Trace complete." } elseif ($cancel.Stop) { "Stopped." } else { "Target not reached within 30 hops." }
                    & $emit @{ Kind = 'end'; Text = $end }
                }
            } finally {
                $pinger.Dispose()
            }
        } `
        -OnLine {
            param($m, $ctx)
            switch ($m.Kind) {
                'start' { Start-NetProbeView -Mode $ctx.Mode -Label $m.Label }
                'reply' { Add-NetPingReply $m }
                'hop'   { Add-NetTraceHop $m }
                'end'   { Complete-NetProbe $m.Text }
                'error' { Reset-NetProbe $m.Text; $netProbeTitle.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "DangerBrush") }
            }
        } `
        -OnComplete {
            param($result, $err, $ctx)
            if ($err) { Complete-NetProbe "Error: $($err.Exception.Message)" "DangerBrush" }
            Set-NetReady
        } | Out-Null
}

# -- Target host -------------------------------------------------------------
# Returns the host to ping/trace, or $null if the box holds something that isn't
# a hostname / IP (spaces, a leading dash and other stray characters are rejected).
function Get-NetTargetHost {
    $h = $netHostBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($h)) { return "8.8.8.8" }
    if ($h -match '^[A-Za-z0-9_][A-Za-z0-9.\-_:%]*$') { return $h }
    Reset-NetProbe "Enter a hostname or IP address (e.g. example.com or 1.1.1.1)."
    return $null
}

# -- Ping --------------------------------------------------------------------
function Invoke-NetPing {
    $h = Get-NetTargetHost
    if (-not $h) { return }
    Start-NetProbe -Mode Ping -Target $h
}

$btnNetPing.Add_Click({ Invoke-NetPing })

# -- Traceroute --------------------------------------------------------------
function Invoke-NetTrace {
    $h = Get-NetTargetHost
    if (-not $h) { return }
    Start-NetProbe -Mode Trace -Target $h
}

$btnNetTrace.Add_Click({ Invoke-NetTrace })

# -- Stop --------------------------------------------------------------------
$btnNetStop.Add_Click({ $script:netCancel.Stop = $true })

# -- Speed test --------------------------------------------------------------
# Latency (median of small requests on one kept-alive connection), then download
# over parallel streams (as many as the server allows), then upload over 4
# (Cloudflare only - the test-file servers can't receive). Each phase warms up,
# then measures for a fixed time with live numbers. Stream errors are collected
# and reported: a dead server, a moved test file or a rate limit (HTTP 429) used
# to show up as a silent "0 Mbps".
$netSpeedStatus  = Find "NetSpeedStatus"
$netSpeedMetrics = Find "NetSpeedMetrics"
$netSpeedDown    = Find "NetSpeedDown"
$netSpeedUp      = Find "NetSpeedUp"
$netSpeedUpUnit  = Find "NetSpeedUpUnit"
$netSpeedPing    = Find "NetSpeedPing"
$netSpeedDetails = Find "NetSpeedDetails"
$script:speedCancel  = [hashtable]::Synchronized(@{ Stop = $false })
$script:speedRunning = $false

# A stream's error code ("Timeout", "HTTP 404", ...) -> readable text (unit-tested)
function ConvertTo-SpeedErrorText {
    param([string]$Code)
    if ($Code -match '^HTTP (\d+)$') {
        switch ([int]$Matches[1]) {
            403     { return "the server refused the request (HTTP 403)" }
            404     { return "the test file wasn't found (HTTP 404)" }
            429     { return "too many requests, try again later (HTTP 429)" }
            default { return "the server answered with HTTP $($Matches[1])" }
        }
    }
    switch ($Code) {
        "Timeout"               { return "the connection timed out" }
        "NameResolutionFailure" { return "the server name couldn't be found" }
        "ConnectFailure"        { return "couldn't connect to the server" }
        "SecureChannelFailure"  { return "the secure (TLS) connection failed" }
        "ConnectionClosed"      { return "the server closed the connection" }
        "ReceiveFailure"        { return "the connection broke off" }
        "SendFailure"           { return "sending to the server failed" }
        default { if ($Code) { return (ConvertTo-PingStatusText $Code).ToLower() } else { return "unknown error" } }
    }
}

# 8.4 / 95 / 940: one decimal below 10 Mbps, whole numbers above (unit-tested)
function Format-SpeedMbps {
    param([double]$Mbps)
    $fmt = if ($Mbps -lt 10) { "{0:0.0}" } else { "{0:0}" }
    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, $fmt, $Mbps)
}

function Set-SpeedRunning {
    param([bool]$On)
    $script:speedRunning = $On
    $btnNetSpeed.Content   = if ($On) { "Stop" } else { "Start" }
    $btnNetSpeed.Style     = $window.Resources[$(if ($On) { "SecondaryButton" } else { "ActionButton" })]
    $btnNetSpeed.IsEnabled = $true
    $netSpeedServerBox.IsEnabled = -not $On
    if ($On) { Set-BusyStatus "Speed test running..." } else { Set-ReadyStatus }
}

function Set-SpeedStatus {
    param([string]$Text, [string]$Brush = "MutedText")
    $netSpeedStatus.Text = $Text
    $netSpeedStatus.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $Brush)
}

function Start-SpeedTest {
    $name   = [string]$netSpeedServerBox.SelectedItem
    $server = $script:speedServers[$name]
    if (-not $server) { return }
    $script:speedCancel.Stop = $false
    Set-SpeedRunning $true
    Set-SpeedStatus "Connecting to $name..."
    $netSpeedDown.Text = "-"; $netSpeedUp.Text = "-"; $netSpeedPing.Text = "-"
    $netSpeedUpUnit.Visibility = "Visible"
    $netSpeedUp.ToolTip = $null
    $netSpeedMetrics.Visibility = "Visible"
    $netSpeedDetails.Visibility = "Collapsed"

    Start-ScyJob `
        -Variables @{ isCf = $server.Cloudflare; url = $server.Url; streams = $server.Streams; cancel = $script:speedCancel } `
        -Context   @{ Server = $name; Cloudflare = $server.Cloudflare } `
        -Work {
            param($emit)
            [System.Net.ServicePointManager]::DefaultConnectionLimit = [Math]::Max([System.Net.ServicePointManager]::DefaultConnectionLimit, 32)
            $cfBase  = "https://speed.cloudflare.com"
            $downUrl = if ($isCf) { "$cfBase/__down?bytes=90000000" } else { $url }   # Cloudflare refuses 100 MB+
            $pingUrl = if ($isCf) { "$cfBase/__down?bytes=0" } else { $url }

            # WebException -> short code ("HTTP 404", "Timeout", ...); the workers get its text
            $errCodeText = {
                param($ex)
                while ($ex -and -not ($ex -is [System.Net.WebException]) -and $ex.InnerException) { $ex = $ex.InnerException }
                if ($ex -is [System.Net.WebException]) {
                    if ($ex.Response -and $ex.Response.StatusCode) { return "HTTP " + [int]$ex.Response.StatusCode }
                    return [string]$ex.Status
                }
                return $ex.GetType().Name
            }.ToString()
            $errCode = [scriptblock]::Create($errCodeText)

            # -- Latency: the first request includes the TLS handshake, so it's dropped
            & $emit @{ Kind = 'status'; Text = "Measuring latency..." }
            $times = @(); $colo = $null; $pingErr = $null
            for ($i = 0; $i -lt 6 -and -not $cancel.Stop; $i++) {
                try {
                    $req = [System.Net.HttpWebRequest]::Create($pingUrl)
                    $req.UserAgent = "Scy"; $req.Timeout = 10000; $req.KeepAlive = $true
                    if (-not $isCf) { $req.AddRange(0, 0) }
                    $sw   = [Diagnostics.Stopwatch]::StartNew()
                    $resp = $req.GetResponse()
                    $ms   = $sw.Elapsed.TotalMilliseconds
                    # CF-RAY ends in the answering location's airport code, e.g. "-VIE"
                    if ($isCf -and -not $colo -and ([string]$resp.Headers["CF-RAY"]) -match '-([A-Z]{3})$') { $colo = $Matches[1] }
                    $s = $resp.GetResponseStream(); $b = [byte[]]::new(4096)
                    while ($s.Read($b, 0, $b.Length) -gt 0) { }
                    $resp.Close()
                    if ($i -gt 0) { $times += $ms }
                } catch { $pingErr = & $errCode $_.Exception; break }
            }
            if ($cancel.Stop) { return @{ Cancelled = $true } }
            if ($times.Count -eq 0) { return @{ Error = $(if ($pingErr) { $pingErr } else { "unknown" }) } }
            $ping = [math]::Round(@($times | Sort-Object)[[int][math]::Floor($times.Count / 2)])
            & $emit @{ Kind = 'ping'; Value = $ping; Colo = $colo }

            # -- One measured phase: $Streams workers run $Worker; bytes count only
            # while measuring (after the warm-up). Live Mbps every half second.
            function Measure-SpeedPhase {
                param([scriptblock]$Worker, [string]$Target, [int]$Streams, [string]$Name, [int]$WarmMs, [int]$MeasureMs)
                $phase = [int[]]::new(1); $total = [long[]]::new(1); $lk = [object]::new()
                $errs  = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
                $pool  = [runspacefactory]::CreateRunspacePool($Streams, $Streams)
                $pool.Open()
                $jobs = for ($i = 0; $i -lt $Streams; $i++) {
                    $ps = [powershell]::Create()
                    $ps.RunspacePool = $pool
                    [void]$ps.AddScript($Worker)
                    foreach ($a in @($Target, $phase, $total, $lk, $errs, $cancel, $errCodeText)) { [void]$ps.AddArgument($a) }
                    @{ PS = $ps; Handle = $ps.BeginInvoke() }
                }
                $sw = [Diagnostics.Stopwatch]::StartNew()
                while ($sw.ElapsedMilliseconds -lt $WarmMs -and -not $cancel.Stop) { Start-Sleep -Milliseconds 100 }
                $phase[0] = 1
                $sw.Restart(); $nextLive = 500
                while ($sw.ElapsedMilliseconds -lt $MeasureMs -and -not $cancel.Stop) {
                    Start-Sleep -Milliseconds 100
                    # every stream already failed: nothing left to measure
                    if ($errs.Count -ge $Streams) { break }
                    if ($sw.ElapsedMilliseconds -ge $nextLive) {
                        & $emit @{ Kind = 'live'; Phase = $Name; Mbps = $total[0] * 8 / $sw.Elapsed.TotalSeconds / 1e6 }
                        $nextLive += 500
                    }
                }
                $seconds = $sw.Elapsed.TotalSeconds
                $phase[0] = 2
                foreach ($j in $jobs) { try { [void]$j.PS.EndInvoke($j.Handle) } catch { }; $j.PS.Dispose() }
                $pool.Close(); $pool.Dispose()
                return @{ Bytes = $total[0]; Seconds = $seconds; Mbps = $total[0] * 8 / [math]::Max($seconds, 0.001) / 1e6
                          Errors = @($errs); Streams = $Streams }
            }

            $downloadWorker = {
                param($u, $phase, $total, $lk, $errs, $cancel, $errCodeText)
                $errCode = [scriptblock]::Create($errCodeText)
                $buf = [byte[]]::new(262144)
                while ($phase[0] -lt 2 -and -not $cancel.Stop) {
                    $req = $null
                    try {
                        $req = [System.Net.HttpWebRequest]::Create($u)
                        $req.UserAgent = "Scy"; $req.Timeout = 15000; $req.ReadWriteTimeout = 15000
                        $str = $req.GetResponse().GetResponseStream()
                        while ($phase[0] -lt 2 -and -not $cancel.Stop) {
                            $r = $str.Read($buf, 0, $buf.Length)
                            if ($r -le 0) { break }   # file done: the outer loop asks again
                            if ($phase[0] -eq 1) { [Threading.Monitor]::Enter($lk); $total[0] += $r; [Threading.Monitor]::Exit($lk) }
                        }
                        # Abort, not Close: closing a half-read response drains the rest of the file
                        $req.Abort()
                    } catch {
                        if ($phase[0] -lt 2 -and -not $cancel.Stop) { [void]$errs.Add((& $errCode $_.Exception)) }
                        if ($req) { try { $req.Abort() } catch { } }
                        break
                    }
                }
            }

            $uploadWorker = {
                param($u, $phase, $total, $lk, $errs, $cancel, $errCodeText)
                $errCode = [scriptblock]::Create($errCodeText)
                $chunk = [byte[]]::new(65536)
                $size  = 25000000
                while ($phase[0] -lt 2 -and -not $cancel.Stop) {
                    $req = $null
                    try {
                        $req = [System.Net.HttpWebRequest]::Create($u)
                        $req.Method = "POST"; $req.ContentType = "application/octet-stream"; $req.UserAgent = "Scy"
                        $req.ContentLength = $size; $req.AllowWriteStreamBuffering = $false
                        $req.Timeout = 15000; $req.ReadWriteTimeout = 15000
                        $s = $req.GetRequestStream(); $sent = 0
                        while ($sent -lt $size -and $phase[0] -lt 2 -and -not $cancel.Stop) {
                            $n = [Math]::Min($chunk.Length, $size - $sent)
                            $s.Write($chunk, 0, $n); $sent += $n
                            if ($phase[0] -eq 1) { [Threading.Monitor]::Enter($lk); $total[0] += $n; [Threading.Monitor]::Exit($lk) }
                        }
                        if ($sent -ge $size) { $s.Close(); $req.GetResponse().Close() } else { $req.Abort() }
                    } catch {
                        if ($phase[0] -lt 2 -and -not $cancel.Stop) { [void]$errs.Add((& $errCode $_.Exception)) }
                        if ($req) { try { $req.Abort() } catch { } }
                        break
                    }
                }
            }

            & $emit @{ Kind = 'status'; Text = "Measuring download..." }
            $down = Measure-SpeedPhase -Worker $downloadWorker -Target $downUrl -Streams $streams -Name 'down' -WarmMs 1500 -MeasureMs 4000
            if ($cancel.Stop) { return @{ Cancelled = $true; Ping = $ping; Colo = $colo; Down = $down } }
            if ($down.Bytes -eq 0) {
                return @{ Error = $(if ($down.Errors.Count) { $down.Errors[0] } else { "Timeout" }); Ping = $ping; Colo = $colo }
            }
            & $emit @{ Kind = 'live'; Phase = 'down'; Mbps = $down.Mbps }

            $up = $null
            if ($isCf) {
                & $emit @{ Kind = 'status'; Text = "Measuring upload..." }
                $up = Measure-SpeedPhase -Worker $uploadWorker -Target "$cfBase/__up" -Streams 4 -Name 'up' -WarmMs 1000 -MeasureMs 4000
                if (-not $cancel.Stop) { & $emit @{ Kind = 'live'; Phase = 'up'; Mbps = $up.Mbps } }
            }
            return @{ Ping = $ping; Colo = $colo; Down = $down; Up = $up; Cancelled = [bool]$cancel.Stop }
        } `
        -OnLine {
            param($m, $ctx)
            Show-SpeedProgress $m
        } `
        -OnComplete {
            param($result, $err, $ctx)
            Complete-SpeedTest $result $err $ctx
        } | Out-Null
}

function Show-SpeedProgress {
    param($m)
    switch ($m.Kind) {
        'status' { Set-SpeedStatus $m.Text }
        'ping'   { $netSpeedPing.Text = "$($m.Value)" }
        'live'   {
            $target = if ($m.Phase -eq 'down') { $netSpeedDown } else { $netSpeedUp }
            $target.Text = Format-SpeedMbps $m.Mbps
        }
    }
}

function Complete-SpeedTest {
    param($Result, $Err, $Ctx)
    Set-SpeedRunning $false
    if ($Err) { Set-SpeedStatus "The speed test failed: $($Err.Exception.Message)" "DangerBrush"; return }
    $where = if ($Ctx.Cloudflare -and $Result.Colo) { "Cloudflare ($($Result.Colo))" } else { $Ctx.Server }

    if ($Result.Error) {
        Set-SpeedStatus "Couldn't test against ${where}: $(ConvertTo-SpeedErrorText $Result.Error). Try another server." "DangerBrush"
        if (-not $Result.Ping) { $netSpeedMetrics.Visibility = "Collapsed" }
        return
    }
    if (-not $Ctx.Cloudflare) {
        $netSpeedUp.Text = "n/a"
        $netSpeedUpUnit.Visibility = "Collapsed"
        $netSpeedUp.ToolTip = "Upload is only measured with Automatic (Cloudflare)"
    }

    # Details: what was measured, and any streams that failed along the way
    $parts = @()
    foreach ($p in @(@{ Name = "download"; R = $Result.Down }, @{ Name = "upload"; R = $Result.Up })) {
        if (-not $p.R) { continue }
        $mb = [math]::Round($p.R.Bytes / 1MB)
        $parts += "$($p.R.Streams) $($p.Name) streams, $mb MB in $([math]::Round($p.R.Seconds, 1)) s"
        $failed = @($p.R.Errors).Count
        if ($failed -gt 0) {
            $parts += "$failed of $($p.R.Streams) $($p.Name) streams failed: $(ConvertTo-SpeedErrorText @($p.R.Errors)[0])"
        }
    }
    $netSpeedDetails.Text = $parts -join "  |  "
    $netSpeedDetails.Visibility = if ($parts.Count) { "Visible" } else { "Collapsed" }

    if ($Result.Cancelled) { Set-SpeedStatus "Stopped. Partial results via $where." }
    else { Set-SpeedStatus "Tested via $where." "FgBrush" }
}

$btnNetSpeed.Add_Click({
    if ($script:speedRunning) {
        # Stop: the job notices within ~0.1 s and finishes its current phase early
        $script:speedCancel.Stop = $true
        $btnNetSpeed.IsEnabled = $false
        Set-SpeedStatus "Stopping..."
        return
    }
    Start-SpeedTest
})

# -- NSLookup -----------------------------------------------------------------
$netNSBox          = Find "NetNSBox"
$netNSPlaceholder  = Find "NetNSPlaceholder"
$netNSStatus       = Find "NetNSStatus"
$netNSHeader       = Find "NetNSHeader"
$netNSResultsPanel = Find "NetNSResultsPanel"
$netNSTypeBox      = Find "NetNSTypeBox"
$btnNetNSLookup    = Find "BtnNetNSLookup"
$btnNetNSCopy      = Find "BtnNetNSCopy"

# Record type selector; "All" queries the common types
$script:nsRecordTypes = @("All", "A", "AAAA", "MX", "NS", "CNAME", "TXT", "SOA", "SRV", "PTR")
foreach ($rt in $script:nsRecordTypes) {
    $netNSTypeBox.Items.Add($rt) | Out-Null
}
$netNSTypeBox.SelectedIndex = 0
$script:nsAllTypes = @("A", "AAAA", "MX", "NS", "CNAME", "TXT")
$script:nsColumns  = @(56, "*", 150, 70)   # type, value, details, TTL (set per lookup)
$script:nsLines    = @()                   # text form for Copy

# Placeholder behavior
$netNSBox.Add_GotFocus({  $netNSPlaceholder.Visibility = "Collapsed" })
$netNSBox.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($netNSBox.Text)) {
        $netNSPlaceholder.Visibility = "Visible"
    }
})

# One DNS record from Resolve-DnsName -> @{ Value; Detail; Ttl } (pure; also
# runs inside the lookup job, and is unit-tested)
function ConvertTo-NSRecordRow {
    param($Record, [string]$Type)
    $r = $Record
    $value, $detail = switch ($Type) {
        "A"     { $r.IPAddress, "" }
        "AAAA"  { $r.IPAddress, "" }
        "MX"    { $r.NameExchange, "Priority $($r.Preference)" }
        "NS"    { $r.NameHost, "" }
        "CNAME" { $r.NameHost, "" }
        "PTR"   { $r.NameHost, "" }
        "TXT"   { (@($r.Strings) -join ""), "" }
        "SOA"   { $r.PrimaryServer, "Admin $($r.NameAdministrator), serial $($r.SerialNumber)" }
        "SRV"   { "$($r.NameTarget):$($r.Port)", "Priority $($r.Priority), weight $($r.Weight)" }
        default { [string]$r.Name, "" }
    }
    return @{ Value = [string]$value; Detail = [string]$detail; Ttl = [int]$r.TTL }
}

function Reset-NSView {
    param([string]$Message, [string]$Brush = "MutedText")
    $netNSStatus.Text = $Message
    $netNSStatus.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $Brush)
    $netNSHeader.Child = $null
    $netNSHeader.Visibility = "Collapsed"
    $netNSResultsPanel.Children.Clear()
    $btnNetNSCopy.Visibility = "Collapsed"
}

# One group per record type: the type in the first column of its first row,
# groups separated by a hairline
function Add-NSTypeGroup {
    param([string]$Type, [object[]]$Rows)
    if (-not $netNSHeader.Child) {
        $labels = @("Type", "Value", "Details", "TTL")
        $cells = for ($i = 0; $i -lt 4; $i++) { New-NetProbeText $labels[$i] "MutedText" $(if ($i -eq 3) { "Right" } else { "Left" }) -Size 11 }
        $netNSHeader.Child = New-NetProbeRow -Cells $cells -Padding 0 -Widths $script:nsColumns
        $netNSHeader.Visibility = "Visible"
    }
    $group = New-Object System.Windows.Controls.StackPanel
    if ($netNSResultsPanel.Children.Count -gt 0) {
        $sep = New-Object System.Windows.Controls.Border
        $sep.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
        $sep.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
        $sep.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
        $group.Children.Add($sep) | Out-Null
    }
    $script:nsLines += "[$Type]"
    $rows = @($Rows)
    if ($rows.Count -eq 0) {
        $group.Children.Add((New-NetProbeRow -Widths $script:nsColumns -Cells @(
            (New-NetProbeText $Type "FgBrush" -Bold), (New-NetProbeText "No records" "MutedText")))) | Out-Null
        $script:nsLines += "  (no records)"
    }
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $row   = $rows[$i]
        $value = New-NetProbeText $row.Value
        $value.TextWrapping = "Wrap"           # long TXT records wrap instead of trimming
        $value.TextTrimming = "None"
        $label = if ($i -eq 0) { New-NetProbeText $Type "FgBrush" -Bold } else { $null }
        $group.Children.Add((New-NetProbeRow -Widths $script:nsColumns -Cells @(
            $label, $value, (New-NetProbeText $row.Detail "MutedText"), (New-NetProbeText "$($row.Ttl)s" "MutedText" -Align Right)))) | Out-Null
        $script:nsLines += "  " + ((@($row.Value, $row.Detail, "TTL $($row.Ttl)s") | Where-Object { $_ }) -join "  ")
    }
    $netNSResultsPanel.Children.Add($group) | Out-Null
}

# -- Lookup (background job) --------------------------------------------------
# Only answer records of the asked type count: for a type the domain doesn't
# have, DNS servers send the zone's SOA in the authority section instead, which
# used to be listed as if it were an MX/AAAA/... record.
function Invoke-NSLookup {
    $domain = $netNSBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($domain)) { return }
    if ($domain -notmatch '^[A-Za-z0-9_][A-Za-z0-9.\-_:]*$') {
        Reset-NSView "Enter a domain name or IP address (e.g. example.com)." "DangerBrush"
        return
    }
    $selected = [string]$netNSTypeBox.SelectedItem
    $types = if ($selected -eq "All") { $script:nsAllTypes } else { @($selected) }
    # Only MX, SOA and SRV have details; without them the column gives its room to the values
    $script:nsColumns = @(56, "*", $(if (@($types | Where-Object { $_ -in "MX", "SOA", "SRV" }).Count) { 150 } else { 0 }), 70)

    Reset-NSView "Looking up $domain..."
    $script:nsLines = @("NSLookup: $domain", "")
    $btnNetNSLookup.IsEnabled = $false

    Start-ScyJob `
        -Variables @{ domain = $domain; types = $types; rowFn = "function ConvertTo-NSRecordRow {${function:ConvertTo-NSRecordRow}}" } `
        -Context   @{ Domain = $domain; Total = [ref]0 } `
        -Work {
            param($emit)
            . ([scriptblock]::Create($rowFn))
            foreach ($type in $types) {
                try {
                    $answers = @(Resolve-DnsName -Name $domain -Type $type -DnsOnly -ErrorAction Stop |
                                 Where-Object { [string]$_.Section -eq "Answer" -and [string]$_.Type -eq $type })
                    if ($type -eq "MX") { $answers = @($answers | Sort-Object Preference) }
                    & $emit @{ Kind = 'type'; Type = $type; Rows = @($answers | ForEach-Object { ConvertTo-NSRecordRow $_ $type }) }
                } catch {
                    # Win32 error codes, the same in every Windows language
                    $code = $_.Exception.NativeErrorCode
                    if ($code -eq 9003) { & $emit @{ Kind = 'nxdomain' }; return }
                    if ($code -eq 9501) { & $emit @{ Kind = 'type'; Type = $type; Rows = @() }; continue }
                    & $emit @{ Kind = 'error'; Type = $type; Text = $_.Exception.Message }
                }
            }
        } `
        -OnLine {
            param($m, $ctx)
            switch ($m.Kind) {
                'type'     { Add-NSTypeGroup $m.Type $m.Rows; $ctx.Total.Value += @($m.Rows).Count }
                'nxdomain' { Reset-NSView "$($ctx.Domain) doesn't exist (no such domain)." "DangerBrush"; $ctx.Total.Value = -1 }
                'error'    { Add-NSTypeGroup $m.Type @(@{ Value = "Lookup failed: $($m.Text)"; Detail = ""; Ttl = 0 }) }
            }
        } `
        -OnComplete {
            param($result, $err, $ctx)
            $btnNetNSLookup.IsEnabled = $true
            if ($err) { Reset-NSView "Lookup failed: $($err.Exception.Message)" "DangerBrush"; return }
            if ($ctx.Total.Value -lt 0) { return }   # no such domain, already shown
            $n = $ctx.Total.Value
            $netNSStatus.Text = "$($ctx.Domain): " + $(if ($n -eq 1) { "1 record" } else { "$n records" })
            $netNSStatus.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
            if ($netNSResultsPanel.Children.Count -gt 0) { $btnNetNSCopy.Visibility = "Visible" }
        } | Out-Null
}

$btnNetNSLookup.Add_Click({ Invoke-NSLookup })

$netNSBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return) { Invoke-NSLookup }
})

$btnNetNSCopy.Add_Click({
    Invoke-CopyAllFlash -Button $this -Text ($script:nsLines -join "`r`n")
})

# -- Wi-Fi QR code dialog ----------------------------------------------------
function Show-WifiQRDialog([string]$ssid, [string]$NetworkKey, [string]$authType) {
    # Escape special chars for WiFi QR format
    $escSsid = $ssid -replace '([\\;,:""])', '\$1'
    $escPwd  = $NetworkKey -replace '([\\;,:""])', '\$1'

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
    $outerBorder.CornerRadius    = [System.Windows.CornerRadius]::new(16)   # cy dialog radius
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
    $qrBorder.CornerRadius = [System.Windows.CornerRadius]::new(10)
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
    $btnNetWifi.IsEnabled       = $false

    # netsh export + parsing run in a background job; rows are built on completion
    Start-ScyJob `
        -Work {
            param($emit)
            # Use XML export to avoid locale-dependent text parsing (netsh text
            # output is translated on non-English Windows, but XML element names
            # like <name>, <keyMaterial>, <authentication> are always English).
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "scy_wifi_$([guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            $profiles = @()
            try {
                try { netsh wlan export profile folder="$tempDir" key=clear 2>&1 | Out-Null } catch {}
                foreach ($xf in (Get-ChildItem -Path $tempDir -Filter "*.xml" -ErrorAction SilentlyContinue)) {
                    try {
                        $xml  = [xml](Get-Content $xf.FullName -Raw)
                        $key  = $xml.WLANProfile.MSM.security.sharedKey
                        # Without elevation netsh ignores key=clear and exports the key
                        # encrypted (<protected>true</protected>); that blob is not the password.
                        $isProtected = $key -and [string]$key.protected -eq 'true'
                        $profiles += [PSCustomObject]@{
                            Name      = $xml.WLANProfile.name
                            Protected = $isProtected
                            Password  = if ($isProtected) { "(hidden - run Scy as administrator)" }
                                        elseif ($key.keyMaterial) { $key.keyMaterial }
                                        else { "(open / no password)" }
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
            } finally {
                # The export holds cleartext keys - never leave it behind
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            return ,@($profiles)
        } `
        -OnComplete {
            param($profiles, $err, $ctx)
            $btnNetWifi.IsEnabled = $true
            Show-WifiProfiles -Profiles @($profiles) -ErrorRecord $err
        } | Out-Null
})

function Show-WifiProfiles {
    param([object[]]$Profiles, $ErrorRecord)
    $profiles = @($Profiles | Where-Object { $_ })
    try {
        if ($ErrorRecord) { throw $ErrorRecord }

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
                $border.Background   = [System.Windows.Media.Brushes]::Transparent
                $border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
                $border.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
                $border.CornerRadius = [System.Windows.CornerRadius]::new(0)
                $border.Padding      = [System.Windows.Thickness]::new(4, 9, 4, 9)
                $border.Margin       = [System.Windows.Thickness]::new(0)

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
                $pwBlock.FontFamily          = [System.Windows.Media.FontFamily]::new("IBM Plex Mono, Cascadia Mono, Consolas")
                $pwBlock.HorizontalAlignment = "Right"
                $pwBlock.VerticalAlignment   = "Center"
                $pwBlock.SetResourceReference(
                    [System.Windows.Controls.TextBlock]::ForegroundProperty,
                    $(if ($prof.Protected) { "MutedText" } else { "AccentBrush" }))
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
                if ($prof.Protected) {
                    $qrBtn.IsEnabled = $false
                    $qrBtn.ToolTip   = "Run Scy as administrator to read this password"
                }
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

    $footerStatus.Text          = "Ready"
}

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
$dnsDoHCheckbox         = Find "DnsDoHCheckbox"
$dnsDoHStatus           = Find "DnsDoHStatus"
$dnsDoHUnsupportedBanner = Find "DnsDoHUnsupportedBanner"

# Check DoH support (requires Windows 10 Build 19628+ or Windows 11).
# Deferred to first Network-tab visit (Invoke-ScyTabInit in Scy.ps1): the first
# Get-Command call triggers PowerShell module discovery (~hundreds of ms), which
# we keep off the startup critical path.
$script:dohSupported = $false
function Initialize-DnsDohStatus {
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
}

# Placeholder toggle helpers
$dnsPrimaryBox.Add_GotFocus({   $dnsPrimaryPlaceholder.Visibility   = "Collapsed" })
$dnsPrimaryBox.Add_LostFocus({  if ($dnsPrimaryBox.Text -eq "")   { $dnsPrimaryPlaceholder.Visibility   = "Visible" } })
$dnsSecondaryBox.Add_GotFocus({ $dnsSecondaryPlaceholder.Visibility = "Collapsed" })
$dnsSecondaryBox.Add_LostFocus({ if ($dnsSecondaryBox.Text -eq "") { $dnsSecondaryPlaceholder.Visibility = "Visible" } })

# DNS profiles: Name -> @{ Primary; Secondary; DohTemplate }
# IPv6 servers are set too: with only IPv4 changed, the router's IPv6 DNS
# (handed out via DHCPv6/RA) kept answering queries on dual-stack networks.
$script:dnsProfiles = @{
    "Cloudflare" = @{
        Primary     = "1.1.1.1"
        Secondary   = "1.0.0.1"
        IPv6        = @("2606:4700:4700::1111", "2606:4700:4700::1001")
        DohTemplate = "https://cloudflare-dns.com/dns-query"
    }
    "Google" = @{
        Primary     = "8.8.8.8"
        Secondary   = "8.8.4.4"
        IPv6        = @("2001:4860:4860::8888", "2001:4860:4860::8844")
        DohTemplate = "https://dns.google/dns-query"
    }
    "Quad9" = @{
        Primary     = "9.9.9.9"
        Secondary   = "149.112.112.112"
        IPv6        = @("2620:fe::fe", "2620:fe::9")
        DohTemplate = "https://dns.quad9.net/dns-query"
    }
    "OpenDNS" = @{
        Primary     = "208.67.222.222"
        Secondary   = "208.67.220.220"
        IPv6        = @("2620:119:35::35", "2620:119:53::53")
        DohTemplate = "https://doh.opendns.com/dns-query"
    }
}

# A valid IPv4 (each octet 0-255) or IPv6 address.
function Test-DnsServerAddress {
    param([string]$Value)
    if ($Value -match '^((25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(25[0-5]|2[0-4]\d|1?\d?\d)$') { return $true }
    $ip = $null
    return ($Value.Contains(':') -and [System.Net.IPAddress]::TryParse($Value, [ref]$ip))
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
        Update-DnsActiveProfile -CurrentDisplay $dns
    }
}

# Map of profile-button → primary IP; "DHCP" matches the automatic state.
$script:dnsProfileButtons = $null
function Get-DnsProfileButtonMap {
    if ($null -eq $script:dnsProfileButtons) {
        $script:dnsProfileButtons = @(
            @{ Button = $btnDnsCloudflare; Primary = "1.1.1.1"        }
            @{ Button = $btnDnsGoogle;     Primary = "8.8.8.8"        }
            @{ Button = $btnDnsQuad9;      Primary = "9.9.9.9"        }
            @{ Button = $btnDnsOpenDNS;    Primary = "208.67.222.222" }
            @{ Button = $btnDnsDHCP;       Primary = "DHCP"           }
        )
    }
    return $script:dnsProfileButtons
}

function Update-DnsActiveProfile {
    param([string]$CurrentDisplay)

    # Pull the leading IP token (strip "  [DoH]" suffix and any extra DNS server)
    $first = $CurrentDisplay
    if ($first) { $first = ($first -split ',')[0].Trim() }
    if ($first -match '\s\[DoH\]$') { $first = $first -replace '\s+\[DoH\]$', '' }
    $isDhcp = ($CurrentDisplay -like "DHCP*")

    foreach ($entry in (Get-DnsProfileButtonMap)) {
        $isActive = if ($entry.Primary -eq "DHCP") { $isDhcp } else { ($first -eq $entry.Primary) }
        if ($isActive) {
            $entry.Button.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "AccentBrush")
            $entry.Button.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty,  "AccentBrush")
        } else {
            $entry.Button.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "BorderBrush")
            $entry.Button.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty,  "SubTextBrush")
        }
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
        # Silently continue; registration may already exist via system policy
    }
}

# Shared failure handling for DNS changes: missing admin rights get the standard
# dialog; anything else is shown in the status line.
function Show-DnsError {
    param($ErrorRecord)
    $dnsStatusText.Foreground = $window.Resources["DangerBrush"]
    if (Test-ScyAccessDenied $ErrorRecord) {
        $dnsStatusText.Text = "Not changed - administrator rights required"
        Show-AdminRequiredError "Changing DNS servers"
    } else {
        $dnsStatusText.Text = "Error: $ErrorRecord"
    }
}

function Set-DnsForAdapter {
    param(
        [string]$AdapterName,
        [string]$Primary,
        [string]$Secondary,
        [string[]]$IPv6 = @(),
        [string]$DohTemplate
    )
    try {
        $useDoH = $dnsDoHCheckbox.IsChecked -and $script:dohSupported
        $statusLabel = if ($useDoH) { "Applying with DoH..." } else { "Applying..." }
        $dnsStatusText.Text       = $statusLabel
        $dnsStatusText.Foreground = $window.Resources["WarningBrush"]

        $addresses = @($Primary)
        if ($Secondary -and $Secondary.Trim() -ne "") { $addresses += $Secondary }
        $addresses += @($IPv6 | Where-Object { $_ })

        # Register DoH templates before setting DNS addresses
        if ($useDoH -and $DohTemplate) {
            foreach ($addr in $addresses) { Register-DohServer -ServerAddress $addr -DohTemplate $DohTemplate }
        }

        Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ServerAddresses $addresses -ErrorAction Stop

        # Flush DNS cache so new settings take effect immediately
        Clear-DnsClientCache -ErrorAction SilentlyContinue

        $resultLabel = if ($useDoH) { "Applied with DoH" } else { "Applied" }
        $dnsStatusText.Text       = $resultLabel
        $dnsStatusText.Foreground = $window.Resources["SuccessBrush"]
        Update-DnsCurrentDisplay
    } catch {
        Show-DnsError $_
    }
}

function Reset-DnsToDHCP {
    param([string]$AdapterName)
    try {
        $dnsStatusText.Text       = "Resetting..."
        $dnsStatusText.Foreground = $window.Resources["WarningBrush"]

        Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ResetServerAddresses -ErrorAction Stop
        Clear-DnsClientCache -ErrorAction SilentlyContinue

        $dnsStatusText.Text       = "Reset to DHCP"
        $dnsStatusText.Foreground = $window.Resources["SuccessBrush"]
        Update-DnsCurrentDisplay
    } catch {
        Show-DnsError $_
    }
}

# Load adapters on init (deferred for faster startup)
$window.Dispatcher.BeginInvoke([action]{ Update-DnsAdapterList }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null

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
        Set-DnsForAdapter -AdapterName $dnsAdapterBox.SelectedItem -Primary $p.Primary -Secondary $p.Secondary -IPv6 $p.IPv6 -DohTemplate $p.DohTemplate
    }
})
$btnDnsGoogle.Add_Click({
    if ($dnsAdapterBox.SelectedItem) {
        $p = $script:dnsProfiles["Google"]
        Set-DnsForAdapter -AdapterName $dnsAdapterBox.SelectedItem -Primary $p.Primary -Secondary $p.Secondary -IPv6 $p.IPv6 -DohTemplate $p.DohTemplate
    }
})
$btnDnsQuad9.Add_Click({
    if ($dnsAdapterBox.SelectedItem) {
        $p = $script:dnsProfiles["Quad9"]
        Set-DnsForAdapter -AdapterName $dnsAdapterBox.SelectedItem -Primary $p.Primary -Secondary $p.Secondary -IPv6 $p.IPv6 -DohTemplate $p.DohTemplate
    }
})
$btnDnsOpenDNS.Add_Click({
    if ($dnsAdapterBox.SelectedItem) {
        $p = $script:dnsProfiles["OpenDNS"]
        Set-DnsForAdapter -AdapterName $dnsAdapterBox.SelectedItem -Primary $p.Primary -Secondary $p.Secondary -IPv6 $p.IPv6 -DohTemplate $p.DohTemplate
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
    # IPv4 (octets 0-255) or IPv6
    if (-not (Test-DnsServerAddress $primary)) {
        $dnsStatusText.Text       = "Invalid primary IP"
        $dnsStatusText.Foreground = $window.Resources["DangerBrush"]
        return
    }
    $secondary = $dnsSecondaryBox.Text.Trim()
    if ($secondary -ne "" -and -not (Test-DnsServerAddress $secondary)) {
        $dnsStatusText.Text       = "Invalid secondary IP"
        $dnsStatusText.Foreground = $window.Resources["DangerBrush"]
        return
    }
    Set-DnsForAdapter -AdapterName $dnsAdapterBox.SelectedItem -Primary $primary -Secondary $secondary
})

