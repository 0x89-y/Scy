# ── Battery Health Report ─────────────────────────────────────────
$batteryStatusPanel   = Find "BatteryStatusPanel"
$batteryCapacityPanel = Find "BatteryCapacityPanel"
$batteryHealthPanel   = Find "BatteryHealthPanel"
$batteryHistoryPanel  = Find "BatteryHistoryPanel"

function Populate-BatteryInfo {
    Set-BusyStatus "Generating battery report..."

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()

    $rs.SessionStateProxy.SetVariable("_win",        $window)
    $rs.SessionStateProxy.SetVariable("_statusPanel", $batteryStatusPanel)
    $rs.SessionStateProxy.SetVariable("_capPanel",    $batteryCapacityPanel)
    $rs.SessionStateProxy.SetVariable("_healthPanel", $batteryHealthPanel)
    $rs.SessionStateProxy.SetVariable("_histPanel",   $batteryHistoryPanel)
    $rs.SessionStateProxy.SetVariable("_si",          (Find "StatusIndicator"))
    $rs.SessionStateProxy.SetVariable("_fs",          (Find "FooterStatus"))

    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    $ps.AddScript({
        # ── Helper: build an info row (inline, same as Tab-Info) ──
        function _MakeRow {
            param([string]$Label, [string]$Value, [string]$BrushKey = "FgBrush", [bool]$Alt = $false)
            $border = New-Object System.Windows.Controls.Border
            $border.Background  = if ($Alt) { $_win.Resources["SurfaceBrush"] } else { $_win.Resources["InputBgBrush"] }
            $border.CornerRadius = [System.Windows.CornerRadius]::new(4)
            $border.Padding      = [System.Windows.Thickness]::new(10, 6, 10, 6)
            $border.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 3)

            $grid = New-Object System.Windows.Controls.Grid
            $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::Auto
            $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
            $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1)

            $lbl = New-Object System.Windows.Controls.TextBlock
            $lbl.Text = $Label; $lbl.FontSize = 12; $lbl.MinWidth = 150
            $lbl.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
            [System.Windows.Controls.Grid]::SetColumn($lbl, 0)

            $val = New-Object System.Windows.Controls.TextBlock
            $val.Text = $Value; $val.FontSize = 12
            $val.HorizontalAlignment = "Right"; $val.TextAlignment = "Right"; $val.TextWrapping = "Wrap"
            $val.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $BrushKey)
            [System.Windows.Controls.Grid]::SetColumn($val, 1)

            $grid.Children.Add($lbl) | Out-Null; $grid.Children.Add($val) | Out-Null
            $border.Child = $grid
            return $border
        }

        # ── Check if battery exists ──────────────────────────────
        $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
        if (-not $battery) {
            $_win.Dispatcher.Invoke([action]{
                $_statusPanel.Children.Clear()
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text = "No battery detected. This feature is for laptops."
                $tb.FontSize = 12
                $tb.Margin = [System.Windows.Thickness]::new(0, 2, 0, 2)
                $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "WarningBrush")
                $_statusPanel.Children.Add($tb) | Out-Null

                foreach ($p in @($_capPanel, $_healthPanel, $_histPanel)) {
                    $p.Children.Clear()
                    $na = New-Object System.Windows.Controls.TextBlock
                    $na.Text = "N/A"; $na.FontSize = 12
                    $na.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                    $p.Children.Add($na) | Out-Null
                }

                $_si.Text = "Ready"; $_si.Foreground = $_win.Resources["SuccessBrush"]; $_fs.Text = "Ready"
            }, [System.Windows.Threading.DispatcherPriority]::Normal)
            return
        }

        # ── Gather WMI battery data ──────────────────────────────
        $bat = $battery | Select-Object -First 1
        $statusCode = $bat.BatteryStatus
        $statusText = switch ($statusCode) {
            1 { "Discharging" }
            2 { "AC Power" }
            3 { "Fully Charged" }
            4 { "Low" }
            5 { "Critical" }
            6 { "Charging" }
            7 { "Charging (High)" }
            8 { "Charging (Low)" }
            9 { "Charging (Critical)" }
            10 { "Undefined" }
            11 { "Partially Charged" }
            default { "Unknown ($statusCode)" }
        }
        $chargePercent = $bat.EstimatedChargeRemaining
        $runtime       = $bat.EstimatedRunTime
        $runtimeText   = if ($runtime -and $runtime -lt 71582788) {
            $h = [math]::Floor($runtime / 60); $m = $runtime % 60
            if ($h -gt 0) { "${h}h ${m}m" } else { "${m}m" }
        } else { "Plugged in / Calculating" }
        $chemistry = switch ($bat.Chemistry) {
            1 { "Other" } 2 { "Unknown" } 3 { "Lead Acid" } 4 { "Nickel Cadmium" }
            5 { "Nickel Metal Hydride" } 6 { "Lithium-ion" } 7 { "Zinc Air" }
            8 { "Lithium Polymer" } default { "Unknown" }
        }
        $deviceID = $bat.DeviceID

        # ── Run powercfg /batteryreport and parse the XML ────────
        $reportPath = Join-Path $env:TEMP "scy_battery_report.xml"
        $null = & powercfg /batteryreport /xml /output $reportPath 2>&1

        $designCap    = $null
        $fullChargeCap = $null
        $cycleCount   = $null
        $healthPct    = $null
        $historyData  = @()

        if (Test-Path $reportPath) {
            try {
                [xml]$report = Get-Content $reportPath -Raw -Encoding UTF8
                $ns = New-Object System.Xml.XmlNamespaceManager($report.NameTable)
                $ns.AddNamespace("br", "http://schemas.microsoft.com/battery/2012")

                $batteries = $report.SelectNodes("//br:Battery", $ns)
                if ($batteries -and $batteries.Count -gt 0) {
                    $b = $batteries[0]
                    $designCap     = [int]$b.DesignCapacity
                    $fullChargeCap = [int]$b.FullChargeCapacity
                    $cycleCount    = $b.CycleCount
                }

                if ($designCap -and $designCap -gt 0 -and $fullChargeCap) {
                    $healthPct = [math]::Round(($fullChargeCap / $designCap) * 100, 1)
                }

                # Recent usage history
                $usageEntries = $report.SelectNodes("//br:RecentUsage/br:UsageEntry", $ns)
                if ($usageEntries) {
                    $recentEntries = @($usageEntries) | Select-Object -Last 15
                    foreach ($entry in $recentEntries) {
                        $ts = $entry.Timestamp
                        $acStr  = if ($entry.Ac -eq "true") { "AC" } else { "Battery" }
                        $charge = $entry.ChargeCapacity
                        $full   = $entry.FullChargeCapacity

                        $pct = if ($full -and [int]$full -gt 0) {
                            [math]::Round(([int]$charge / [int]$full) * 100, 0)
                        } else { "?" }

                        $historyData += [PSCustomObject]@{
                            Time   = $ts
                            Source = $acStr
                            Pct    = $pct
                            Charge = $charge
                            Full   = $full
                        }
                    }
                }
            } catch { }
            Remove-Item $reportPath -Force -ErrorAction SilentlyContinue
        }

        # ── Marshal to UI thread ─────────────────────────────────
        $_win.Dispatcher.Invoke([action]{

            # ── Status panel ──
            $_statusPanel.Children.Clear()
            $alt = $false
            $statusBrush = switch ($statusCode) {
                5 { "DangerBrush" }; 4 { "WarningBrush" }
                3 { "SuccessBrush" }; 6 { "AccentBrush" }; 7 { "AccentBrush" }; 8 { "AccentBrush" }; 9 { "AccentBrush" }
                default { "FgBrush" }
            }
            $_statusPanel.Children.Add((_MakeRow "Status"              $statusText $statusBrush $alt)) | Out-Null; $alt = -not $alt
            $_statusPanel.Children.Add((_MakeRow "Charge"              "$chargePercent%" "FgBrush" $alt)) | Out-Null; $alt = -not $alt
            $_statusPanel.Children.Add((_MakeRow "Time Remaining"      $runtimeText "FgBrush" $alt)) | Out-Null; $alt = -not $alt
            $_statusPanel.Children.Add((_MakeRow "Chemistry"           $chemistry "FgBrush" $alt)) | Out-Null; $alt = -not $alt
            if ($deviceID) {
                $_statusPanel.Children.Add((_MakeRow "Device ID"       $deviceID "MutedText" $alt)) | Out-Null
            }

            # ── Capacity panel ──
            $_capPanel.Children.Clear()
            $alt = $false
            if ($designCap) {
                $designMWh     = [math]::Round($designCap / 1000, 2)
                $fullChargeMWh = [math]::Round($fullChargeCap / 1000, 2)
                $wearMWh       = [math]::Round(($designCap - $fullChargeCap) / 1000, 2)

                $_capPanel.Children.Add((_MakeRow "Design Capacity"      "${designMWh} Wh" "FgBrush" $alt)) | Out-Null; $alt = -not $alt
                $_capPanel.Children.Add((_MakeRow "Full Charge Capacity"  "${fullChargeMWh} Wh" "FgBrush" $alt)) | Out-Null; $alt = -not $alt
                $_capPanel.Children.Add((_MakeRow "Capacity Lost"         "${wearMWh} Wh" "WarningBrush" $alt)) | Out-Null; $alt = -not $alt
                if ($cycleCount) {
                    $_capPanel.Children.Add((_MakeRow "Cycle Count"      $cycleCount "FgBrush" $alt)) | Out-Null
                }
            } else {
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text = "Could not retrieve capacity data (run as Admin for full report)."
                $tb.FontSize = 12; $tb.TextWrapping = "Wrap"
                $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                $_capPanel.Children.Add($tb) | Out-Null
            }

            # ── Health panel ──
            $_healthPanel.Children.Clear()
            if ($healthPct) {
                $healthColor = if ($healthPct -ge 80) { "SuccessBrush" }
                               elseif ($healthPct -ge 50) { "WarningBrush" }
                               else { "DangerBrush" }

                # Big percentage display
                $bigPct = New-Object System.Windows.Controls.TextBlock
                $bigPct.Text = "${healthPct}%"
                $bigPct.FontSize = 36; $bigPct.FontWeight = "Bold"
                $bigPct.HorizontalAlignment = "Center"
                $bigPct.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
                $bigPct.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $healthColor)
                $_healthPanel.Children.Add($bigPct) | Out-Null

                $label = New-Object System.Windows.Controls.TextBlock
                $label.Text = "of original capacity"
                $label.FontSize = 11; $label.HorizontalAlignment = "Center"
                $label.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                $_healthPanel.Children.Add($label) | Out-Null

                # Progress bar
                $barBorder = New-Object System.Windows.Controls.Border
                $barBorder.Height = 8; $barBorder.CornerRadius = [System.Windows.CornerRadius]::new(4)
                $barBorder.Margin = [System.Windows.Thickness]::new(0, 10, 0, 4)
                $barBorder.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "InputBgBrush")

                $barGrid = New-Object System.Windows.Controls.Grid
                $fillBorder = New-Object System.Windows.Controls.Border
                $fillBorder.Height = 8; $fillBorder.CornerRadius = [System.Windows.CornerRadius]::new(4)
                $fillBorder.HorizontalAlignment = "Left"
                $fillBorder.Width = 0
                $fillBorder.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $healthColor)
                $barGrid.Children.Add($fillBorder) | Out-Null
                $barBorder.Child = $barGrid

                $_healthPanel.Children.Add($barBorder) | Out-Null

                # Update bar width after render (need actual width)
                $_win.Dispatcher.BeginInvoke([action]{
                    $parentWidth = $barBorder.ActualWidth
                    if ($parentWidth -gt 0) {
                        $fillBorder.Width = [math]::Min($parentWidth, $parentWidth * ($healthPct / 100))
                    } else {
                        $fillBorder.Width = 200 * ($healthPct / 100)
                    }
                }, [System.Windows.Threading.DispatcherPriority]::Loaded)

                # Rating text
                $ratingText = if ($healthPct -ge 90) { "Excellent" }
                              elseif ($healthPct -ge 80) { "Good" }
                              elseif ($healthPct -ge 60) { "Fair" }
                              elseif ($healthPct -ge 40) { "Poor" }
                              else { "Replace Soon" }
                $rating = New-Object System.Windows.Controls.TextBlock
                $rating.Text = $ratingText; $rating.FontSize = 11
                $rating.HorizontalAlignment = "Center"
                $rating.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
                $rating.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $healthColor)
                $_healthPanel.Children.Add($rating) | Out-Null
            } else {
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text = "Health data unavailable"; $tb.FontSize = 12
                $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                $_healthPanel.Children.Add($tb) | Out-Null
            }

            # ── History panel ──
            $_histPanel.Children.Clear()
            if ($historyData.Count -gt 0) {
                # Header row
                $hdr = New-Object System.Windows.Controls.Border
                $hdr.Padding = [System.Windows.Thickness]::new(10, 6, 10, 6)
                $hdr.Margin  = [System.Windows.Thickness]::new(0, 0, 0, 3)

                $hGrid = New-Object System.Windows.Controls.Grid
                $hc0 = New-Object System.Windows.Controls.ColumnDefinition; $hc0.Width = New-Object System.Windows.GridLength(2, [System.Windows.GridUnitType]::Star)
                $hc1 = New-Object System.Windows.Controls.ColumnDefinition; $hc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
                $hc2 = New-Object System.Windows.Controls.ColumnDefinition; $hc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
                $hGrid.ColumnDefinitions.Add($hc0); $hGrid.ColumnDefinitions.Add($hc1); $hGrid.ColumnDefinitions.Add($hc2)

                $h0 = New-Object System.Windows.Controls.TextBlock; $h0.Text = "Time"; $h0.FontSize = 11; $h0.FontWeight = "SemiBold"
                $h0.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                [System.Windows.Controls.Grid]::SetColumn($h0, 0)

                $h1 = New-Object System.Windows.Controls.TextBlock; $h1.Text = "Source"; $h1.FontSize = 11; $h1.FontWeight = "SemiBold"
                $h1.HorizontalAlignment = "Center"
                $h1.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                [System.Windows.Controls.Grid]::SetColumn($h1, 1)

                $h2 = New-Object System.Windows.Controls.TextBlock; $h2.Text = "Charge"; $h2.FontSize = 11; $h2.FontWeight = "SemiBold"
                $h2.HorizontalAlignment = "Right"
                $h2.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                [System.Windows.Controls.Grid]::SetColumn($h2, 2)

                $hGrid.Children.Add($h0) | Out-Null; $hGrid.Children.Add($h1) | Out-Null; $hGrid.Children.Add($h2) | Out-Null
                $hdr.Child = $hGrid
                $_histPanel.Children.Add($hdr) | Out-Null

                $alt = $false
                foreach ($entry in $historyData) {
                    $row = New-Object System.Windows.Controls.Border
                    $row.Background  = if ($alt) { $_win.Resources["SurfaceBrush"] } else { $_win.Resources["InputBgBrush"] }
                    $row.CornerRadius = [System.Windows.CornerRadius]::new(4)
                    $row.Padding      = [System.Windows.Thickness]::new(10, 6, 10, 6)
                    $row.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 2)

                    $rGrid = New-Object System.Windows.Controls.Grid
                    $rc0 = New-Object System.Windows.Controls.ColumnDefinition; $rc0.Width = New-Object System.Windows.GridLength(2, [System.Windows.GridUnitType]::Star)
                    $rc1 = New-Object System.Windows.Controls.ColumnDefinition; $rc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
                    $rc2 = New-Object System.Windows.Controls.ColumnDefinition; $rc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
                    $rGrid.ColumnDefinitions.Add($rc0); $rGrid.ColumnDefinitions.Add($rc1); $rGrid.ColumnDefinitions.Add($rc2)

                    # Format timestamp
                    $timeStr = $entry.Time
                    try {
                        $dt = [datetime]::Parse($entry.Time)
                        $timeStr = $dt.ToString("yyyy-MM-dd HH:mm")
                    } catch { }

                    $t0 = New-Object System.Windows.Controls.TextBlock; $t0.Text = $timeStr; $t0.FontSize = 11
                    $t0.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
                    [System.Windows.Controls.Grid]::SetColumn($t0, 0)

                    $srcBrush = if ($entry.Source -eq "AC") { "SuccessBrush" } else { "WarningBrush" }
                    $t1 = New-Object System.Windows.Controls.TextBlock; $t1.Text = $entry.Source; $t1.FontSize = 11
                    $t1.HorizontalAlignment = "Center"
                    $t1.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $srcBrush)
                    [System.Windows.Controls.Grid]::SetColumn($t1, 1)

                    $t2 = New-Object System.Windows.Controls.TextBlock; $t2.Text = "$($entry.Pct)%"; $t2.FontSize = 11
                    $t2.HorizontalAlignment = "Right"
                    $t2.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
                    [System.Windows.Controls.Grid]::SetColumn($t2, 2)

                    $rGrid.Children.Add($t0) | Out-Null; $rGrid.Children.Add($t1) | Out-Null; $rGrid.Children.Add($t2) | Out-Null
                    $row.Child = $rGrid
                    $_histPanel.Children.Add($row) | Out-Null
                    $alt = -not $alt
                }
            } else {
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text = "No usage history available (run as Admin for full report)."
                $tb.FontSize = 12; $tb.TextWrapping = "Wrap"
                $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                $_histPanel.Children.Add($tb) | Out-Null
            }

            # Done
            $_si.Text = "Ready"; $_si.Foreground = $_win.Resources["SuccessBrush"]; $_fs.Text = "Ready"
        }, [System.Windows.Threading.DispatcherPriority]::Normal)
    }) | Out-Null

    $ps.BeginInvoke() | Out-Null
}

(Find "BtnBatteryRefresh").Add_Click({ Populate-BatteryInfo })
