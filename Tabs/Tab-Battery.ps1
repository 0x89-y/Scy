# ── Battery Health Report ─────────────────────────────────────────
$batteryStatusPanel   = Find "BatteryStatusPanel"
$batteryCapacityPanel = Find "BatteryCapacityPanel"
$batteryHealthPanel   = Find "BatteryHealthPanel"
$batteryHistoryPanel  = Find "BatteryHistoryPanel"

function Populate-BatteryInfo {
    Set-BusyStatus "Generating battery report..."

    Start-ScyJob `
        -Work {
            param($emit)

            $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
            if (-not $battery) {
                return @{ HasBattery = $false }
            }

            $bat        = $battery | Select-Object -First 1
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

            $reportPath = Join-Path $env:TEMP "scy_battery_report.xml"
            $null = & powercfg /batteryreport /xml /output $reportPath 2>&1

            $designCap     = $null
            $fullChargeCap = $null
            $cycleCount    = $null
            $healthPct     = $null
            $historyData   = @()

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

                    $usageEntries = $report.SelectNodes("//br:RecentUsage/br:UsageEntry", $ns)
                    if ($usageEntries) {
                        $recentEntries = @($usageEntries) | Select-Object -Last 15
                        foreach ($entry in $recentEntries) {
                            $ts     = $entry.Timestamp
                            $acStr  = if ($entry.Ac -eq "true") { "AC" } else { "Battery" }
                            $charge = $entry.ChargeCapacity
                            $full   = $entry.FullChargeCapacity
                            $pct    = if ($full -and [int]$full -gt 0) {
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

            return @{
                HasBattery     = $true
                StatusCode     = $statusCode
                StatusText     = $statusText
                ChargePercent  = $chargePercent
                RuntimeText    = $runtimeText
                Chemistry      = $chemistry
                DeviceID       = $deviceID
                DesignCap      = $designCap
                FullChargeCap  = $fullChargeCap
                CycleCount     = $cycleCount
                HealthPct      = $healthPct
                HistoryData    = $historyData
            }
        } `
        -OnComplete {
            param($d, $err, $ctx)
            if ($err) {
                Set-ReadyStatus
                return
            }

            function _MakeRow {
                param([string]$Label, [string]$Value, [string]$BrushKey = "FgBrush", [bool]$Alt = $false)
                $border = New-Object System.Windows.Controls.Border
                $bgKey = if ($Alt) { "SurfaceBrush" } else { "InputBgBrush" }
                $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $bgKey)
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

            if (-not $d.HasBattery) {
                $batteryStatusPanel.Children.Clear()
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text     = "No battery detected. This feature is for laptops."
                $tb.FontSize = 12
                $tb.Margin   = [System.Windows.Thickness]::new(0, 2, 0, 2)
                $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "WarningBrush")
                $batteryStatusPanel.Children.Add($tb) | Out-Null

                foreach ($p in @($batteryCapacityPanel, $batteryHealthPanel, $batteryHistoryPanel)) {
                    $p.Children.Clear()
                    $na = New-Object System.Windows.Controls.TextBlock
                    $na.Text = "N/A"; $na.FontSize = 12
                    $na.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                    $p.Children.Add($na) | Out-Null
                }

                Set-ReadyStatus
                return
            }

            # ── Status panel ──
            $batteryStatusPanel.Children.Clear()
            $alt = $false
            $statusBrush = switch ($d.StatusCode) {
                5 { "DangerBrush" }; 4 { "WarningBrush" }
                3 { "SuccessBrush" }; 6 { "AccentBrush" }; 7 { "AccentBrush" }; 8 { "AccentBrush" }; 9 { "AccentBrush" }
                default { "FgBrush" }
            }
            $batteryStatusPanel.Children.Add((_MakeRow "Status"         $d.StatusText       $statusBrush $alt)) | Out-Null; $alt = -not $alt
            $batteryStatusPanel.Children.Add((_MakeRow "Charge"         "$($d.ChargePercent)%" "FgBrush" $alt)) | Out-Null; $alt = -not $alt
            $batteryStatusPanel.Children.Add((_MakeRow "Time Remaining" $d.RuntimeText      "FgBrush"    $alt)) | Out-Null; $alt = -not $alt
            $batteryStatusPanel.Children.Add((_MakeRow "Chemistry"      $d.Chemistry        "FgBrush"    $alt)) | Out-Null; $alt = -not $alt
            if ($d.DeviceID) {
                $batteryStatusPanel.Children.Add((_MakeRow "Device ID"  $d.DeviceID         "MutedText"  $alt)) | Out-Null
            }

            # ── Capacity panel ──
            $batteryCapacityPanel.Children.Clear()
            $alt = $false
            if ($d.DesignCap) {
                $designMWh     = [math]::Round($d.DesignCap / 1000, 2)
                $fullChargeMWh = [math]::Round($d.FullChargeCap / 1000, 2)
                $wearMWh       = [math]::Round(($d.DesignCap - $d.FullChargeCap) / 1000, 2)

                $batteryCapacityPanel.Children.Add((_MakeRow "Design Capacity"      "${designMWh} Wh"     "FgBrush"      $alt)) | Out-Null; $alt = -not $alt
                $batteryCapacityPanel.Children.Add((_MakeRow "Full Charge Capacity" "${fullChargeMWh} Wh" "FgBrush"      $alt)) | Out-Null; $alt = -not $alt
                $batteryCapacityPanel.Children.Add((_MakeRow "Capacity Lost"        "${wearMWh} Wh"       "WarningBrush" $alt)) | Out-Null; $alt = -not $alt
                if ($d.CycleCount) {
                    $batteryCapacityPanel.Children.Add((_MakeRow "Cycle Count" $d.CycleCount "FgBrush" $alt)) | Out-Null
                }
            } else {
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text     = "Could not retrieve capacity data (run as Admin for full report)."
                $tb.FontSize = 12; $tb.TextWrapping = "Wrap"
                $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                $batteryCapacityPanel.Children.Add($tb) | Out-Null
            }

            # ── Health panel ──
            $batteryHealthPanel.Children.Clear()
            if ($d.HealthPct) {
                $healthColor = if ($d.HealthPct -ge 80) { "SuccessBrush" }
                               elseif ($d.HealthPct -ge 50) { "WarningBrush" }
                               else { "DangerBrush" }

                $bigPct = New-Object System.Windows.Controls.TextBlock
                $bigPct.Text     = "$($d.HealthPct)%"
                $bigPct.FontSize = 36; $bigPct.FontWeight = "Bold"
                $bigPct.HorizontalAlignment = "Center"
                $bigPct.Margin   = [System.Windows.Thickness]::new(0, 4, 0, 4)
                $bigPct.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $healthColor)
                $batteryHealthPanel.Children.Add($bigPct) | Out-Null

                $label = New-Object System.Windows.Controls.TextBlock
                $label.Text     = "of original capacity"
                $label.FontSize = 11; $label.HorizontalAlignment = "Center"
                $label.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                $batteryHealthPanel.Children.Add($label) | Out-Null

                $barOuter = New-Object System.Windows.Controls.Border
                $barOuter.Height = 8; $barOuter.CornerRadius = [System.Windows.CornerRadius]::new(4)
                $barOuter.Margin = [System.Windows.Thickness]::new(0, 10, 0, 4)
                $barOuter.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "InputBgBrush")

                $barGrid = New-Object System.Windows.Controls.Grid
                $filled  = [math]::Max(0, [math]::Min(100, $d.HealthPct))
                $cFill   = New-Object System.Windows.Controls.ColumnDefinition
                $cFill.Width  = New-Object System.Windows.GridLength($filled, [System.Windows.GridUnitType]::Star)
                $cEmpty = New-Object System.Windows.Controls.ColumnDefinition
                $cEmpty.Width = New-Object System.Windows.GridLength((100 - $filled), [System.Windows.GridUnitType]::Star)
                $barGrid.ColumnDefinitions.Add($cFill)
                $barGrid.ColumnDefinitions.Add($cEmpty)

                $fillBorder = New-Object System.Windows.Controls.Border
                $fillBorder.Height = 8; $fillBorder.CornerRadius = [System.Windows.CornerRadius]::new(4)
                $fillBorder.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $healthColor)
                [System.Windows.Controls.Grid]::SetColumn($fillBorder, 0)
                $barGrid.Children.Add($fillBorder) | Out-Null
                $barOuter.Child = $barGrid

                $batteryHealthPanel.Children.Add($barOuter) | Out-Null

                $ratingText = if ($d.HealthPct -ge 90) { "Excellent" }
                              elseif ($d.HealthPct -ge 80) { "Good" }
                              elseif ($d.HealthPct -ge 60) { "Fair" }
                              elseif ($d.HealthPct -ge 40) { "Poor" }
                              else { "Replace Soon" }
                $rating = New-Object System.Windows.Controls.TextBlock
                $rating.Text     = $ratingText; $rating.FontSize = 11
                $rating.HorizontalAlignment = "Center"
                $rating.Margin   = [System.Windows.Thickness]::new(0, 4, 0, 0)
                $rating.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $healthColor)
                $batteryHealthPanel.Children.Add($rating) | Out-Null
            } else {
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text     = "Health data unavailable"; $tb.FontSize = 12
                $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                $batteryHealthPanel.Children.Add($tb) | Out-Null
            }

            # ── History panel ──
            $batteryHistoryPanel.Children.Clear()
            if ($d.HistoryData.Count -gt 0) {
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
                $batteryHistoryPanel.Children.Add($hdr) | Out-Null

                $alt = $false
                foreach ($entry in $d.HistoryData) {
                    $row = New-Object System.Windows.Controls.Border
                    $rowBgKey = if ($alt) { "SurfaceBrush" } else { "InputBgBrush" }
                    $row.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $rowBgKey)
                    $row.CornerRadius = [System.Windows.CornerRadius]::new(4)
                    $row.Padding      = [System.Windows.Thickness]::new(10, 6, 10, 6)
                    $row.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 2)

                    $rGrid = New-Object System.Windows.Controls.Grid
                    $rc0 = New-Object System.Windows.Controls.ColumnDefinition; $rc0.Width = New-Object System.Windows.GridLength(2, [System.Windows.GridUnitType]::Star)
                    $rc1 = New-Object System.Windows.Controls.ColumnDefinition; $rc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
                    $rc2 = New-Object System.Windows.Controls.ColumnDefinition; $rc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
                    $rGrid.ColumnDefinitions.Add($rc0); $rGrid.ColumnDefinitions.Add($rc1); $rGrid.ColumnDefinitions.Add($rc2)

                    $timeStr = $entry.Time
                    try {
                        $dt      = [datetime]::Parse($entry.Time)
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
                    $batteryHistoryPanel.Children.Add($row) | Out-Null
                    $alt = -not $alt
                }
            } else {
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text     = "No usage history available (run as Admin for full report)."
                $tb.FontSize = 12; $tb.TextWrapping = "Wrap"
                $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                $batteryHistoryPanel.Children.Add($tb) | Out-Null
            }

            Set-ReadyStatus
        } | Out-Null
}

(Find "BtnBatteryRefresh").Add_Click({ Populate-BatteryInfo })
