# ── SFC / DISM Runner Tab ────────────────────────────────────────

$sfcDismStatus      = Find "SfcDismStatus"
$sfcDismProgress    = Find "SfcDismProgress"
$sfcDismOutput      = Find "SfcDismOutput"
$sfcDismResultCard  = Find "SfcDismResultCard"
$sfcDismResultPanel = Find "SfcDismResultPanel"
$btnSfcRun          = Find "BtnSfcRun"
$btnDismRun         = Find "BtnDismRun"
$btnSfcDismBoth     = Find "BtnSfcDismBoth"
$btnSfcDismStop     = Find "BtnSfcDismStop"
$btnToggleSfcDismLog = Find "BtnToggleSfcDismLog"

$script:sfcDismProcHolder = [System.Collections.ArrayList]::new()

# -- Toggle output log visibility -----------------------------------------------
$btnToggleSfcDismLog.Add_Click({
    if ($sfcDismOutput.Visibility -eq "Visible") {
        $sfcDismOutput.Visibility = "Collapsed"
        $btnToggleSfcDismLog.Content = "Show output"
    } else {
        $sfcDismOutput.Visibility = "Visible"
        $btnToggleSfcDismLog.Content = "Hide output"
    }
})

# -- UI state helpers --------------------------------------------------------
function Set-SfcDismBusy([string]$msg) {
    $sfcDismStatus.Text        = $msg
    $sfcDismStatus.Foreground  = $window.Resources["WarningBrush"]
    $sfcDismProgress.Value     = 0
    $statusIndicator.Text      = "* $msg"
    $statusIndicator.Foreground = $window.Resources["WarningBrush"]
    $footerStatus.Text         = "Scy - $msg"
    $btnSfcRun.IsEnabled       = $false
    $btnDismRun.IsEnabled      = $false
    $btnSfcDismBoth.IsEnabled  = $false
    $btnSfcDismStop.IsEnabled  = $true
    $btnSfcDismStop.Opacity    = 1
    $sfcDismResultCard.Visibility = "Collapsed"
    $sfcDismResultPanel.Children.Clear()
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Set-SfcDismReady {
    $statusIndicator.Text       = "* Ready"
    $statusIndicator.Foreground = $window.Resources["SuccessBrush"]
    $footerStatus.Text          = "Ready"
    $btnSfcRun.IsEnabled        = $true
    $btnDismRun.IsEnabled       = $true
    $btnSfcDismBoth.IsEnabled   = $true
    $btnSfcDismStop.IsEnabled   = $false
    $btnSfcDismStop.Opacity     = 0.4
    $script:sfcDismProcHolder.Clear()
}

# -- Result row builder ------------------------------------------------------
function New-SfcDismResultRow([string]$Label, [string]$Value, [string]$Color) {
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = "Horizontal"
    $sp.Margin = "0,2,0,2"

    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text       = $Label
    $lbl.FontSize   = 12
    $lbl.FontWeight = "SemiBold"
    $lbl.Foreground = $window.Resources["FgBrush"]
    $lbl.Margin     = "0,0,8,0"
    $sp.Children.Add($lbl) | Out-Null

    $val = New-Object System.Windows.Controls.TextBlock
    $val.Text       = $Value
    $val.FontSize   = 12
    $val.Foreground = if ($Color) { New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Color)) } else { $window.Resources["MutedText"] }
    $sp.Children.Add($val) | Out-Null

    return $sp
}

# -- Parse SFC output -------------------------------------------------------
function Parse-SfcOutput([string]$RawText) {
    $result = @{ Tool = "SFC /scannow"; Status = "Unknown"; Details = @() }

    if ($RawText -match "did not find any integrity violations") {
        $result.Status = "Healthy"
        $result.Color  = "#2ecc71"
        $result.Details += "No integrity violations found."
    }
    elseif ($RawText -match "found corrupt files and successfully repaired") {
        $result.Status = "Repaired"
        $result.Color  = "#f39c12"
        $result.Details += "Corrupt files were found and repaired."
    }
    elseif ($RawText -match "found corrupt files but was unable to fix") {
        $result.Status = "Failed"
        $result.Color  = "#e74c3c"
        $result.Details += "Corrupt files found but could not be repaired."
        $result.Details += "Try running DISM first, then SFC again."
    }
    elseif ($RawText -match "could not perform the requested operation") {
        $result.Status = "Error"
        $result.Color  = "#e74c3c"
        $result.Details += "SFC could not run. Try booting into Safe Mode."
    }
    else {
        $result.Color = "#95a5a6"
        $result.Details += "Could not determine result -- check the output log."
    }

    # Extract verification percentage if present
    if ($RawText -match "Verification\s+(\d+)%\s+complete") {
        $result.LastPercent = [int]$Matches[1]
    }

    return $result
}

# -- Parse DISM output -------------------------------------------------------
function Parse-DismOutput([string]$RawText) {
    $result = @{ Tool = "DISM RestoreHealth"; Status = "Unknown"; Details = @() }

    if ($RawText -match "The restore operation completed successfully") {
        $result.Status = "Healthy"
        $result.Color  = "#2ecc71"
        $result.Details += "Component store is healthy. No repairs needed."
    }
    elseif ($RawText -match "The component store corruption was repaired") {
        $result.Status = "Repaired"
        $result.Color  = "#f39c12"
        $result.Details += "Corruption was found and successfully repaired."
    }
    elseif ($RawText -match "Error:") {
        $result.Status = "Failed"
        $result.Color  = "#e74c3c"
        $errs = [regex]::Matches($RawText, "Error:\s*(.+)")
        foreach ($m in $errs) { $result.Details += $m.Groups[1].Value.Trim() }
        if ($result.Details.Count -eq 0) { $result.Details += "DISM encountered an error." }
    }
    else {
        $result.Color = "#95a5a6"
        $result.Details += "Could not determine result -- check the output log."
    }

    return $result
}

# -- Core runner (background runspace) ---------------------------------------
function Start-SfcDismRunner {
    param(
        [string[]]$Commands,   # e.g. @("sfc","dism") or @("sfc") or @("dism")
        [string]$StatusLabel
    )

    Set-SfcDismBusy $StatusLabel
    $sfcDismOutput.Text = ""

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()

    $rs.SessionStateProxy.SetVariable("_commands",    $Commands)
    $rs.SessionStateProxy.SetVariable("_box",         $sfcDismOutput)
    $rs.SessionStateProxy.SetVariable("_statusTxt",   $sfcDismStatus)
    $rs.SessionStateProxy.SetVariable("_progressBar", $sfcDismProgress)
    $rs.SessionStateProxy.SetVariable("_resultCard",  $sfcDismResultCard)
    $rs.SessionStateProxy.SetVariable("_resultPanel", $sfcDismResultPanel)
    $rs.SessionStateProxy.SetVariable("_win",         $window)
    $rs.SessionStateProxy.SetVariable("_si",          $statusIndicator)
    $rs.SessionStateProxy.SetVariable("_fs",          $footerStatus)
    $rs.SessionStateProxy.SetVariable("_btnSfc",      $btnSfcRun)
    $rs.SessionStateProxy.SetVariable("_btnDism",     $btnDismRun)
    $rs.SessionStateProxy.SetVariable("_btnBoth",     $btnSfcDismBoth)
    $rs.SessionStateProxy.SetVariable("_btnStop",     $btnSfcDismStop)
    $rs.SessionStateProxy.SetVariable("_procHolder",  $script:sfcDismProcHolder)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    $ps.AddScript({
        function Ui([scriptblock]$sb) {
            $_win.Dispatcher.Invoke($sb, [System.Windows.Threading.DispatcherPriority]::Normal)
        }
        function AppendLine([string]$t) {
            Ui { $_box.AppendText("$t`r`n"); $_box.ScrollToEnd() }
        }
        function SetStatus([string]$t) {
            Ui {
                $_statusTxt.Text = $t
                $_si.Text        = "* $t"
            }
        }
        function SetProgress([int]$v) {
            Ui { $_progressBar.Value = $v }
        }

        # -- Helpers for parsing inside the runspace --
        function ParsePercent([string]$line) {
            # Strip null bytes (leftover from UTF-16 if encoding wasn't set)
            $line = $line -replace "`0", ''
            # DISM outputs normal text like "[====  29.3%  ]"
            if ($line -match '(\d+\.\d+)\s*%') {
                return [int][double]$Matches[1]
            }
            if ($line -match '(\d+)\s*%') {
                return [int]$Matches[1]
            }
            # SFC may still output wide-spaced: "1 0 0 %", "4 9 %", "5 %"
            # 3-digit spaced must come before 2-digit
            if ($line -match '(\d)\s+(\d)\s+(\d)\s+%') {
                return [int]("$($Matches[1])$($Matches[2])$($Matches[3])")
            }
            if ($line -match '(\d)\s+(\d)\s+%') {
                return [int]("$($Matches[1])$($Matches[2])")
            }
            if ($line -match '(\d)\s+%') {
                return [int]$Matches[1]
            }
            return -1
        }

        function RunTool([string]$tool) {
            $isSfc = ($tool -eq "sfc")
            if ($isSfc) {
                $exe  = "sfc.exe"
                $args = "/scannow"
                $label = "SFC /scannow"
            } else {
                $exe  = "DISM.exe"
                $args = "/Online /Cleanup-Image /RestoreHealth"
                $label = "DISM /RestoreHealth"
            }

            AppendLine "> $label"
            AppendLine ("-" * 60)
            SetStatus "Running $label..."
            SetProgress 0

            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName               = $exe
            $psi.Arguments              = $args
            $psi.UseShellExecute        = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.CreateNoWindow         = $true
            # SFC outputs UTF-16 LE; set encoding so we get clean text
            if ($isSfc) {
                $psi.StandardOutputEncoding = [System.Text.Encoding]::Unicode
                $psi.StandardErrorEncoding  = [System.Text.Encoding]::Unicode
            }

            $p = [System.Diagnostics.Process]::new()
            $p.StartInfo = $psi

            try {
                $p.Start() | Out-Null
            } catch {
                AppendLine "ERROR: Failed to start $exe -- $_"
                AppendLine "Make sure you are running Scy as Administrator."
                return ""
            }

            $_procHolder.Clear()
            $_procHolder.Add($p) | Out-Null

            $output = [System.Text.StringBuilder]::new()

            # SFC uses carriage returns (\r) to overwrite progress on the same
            # line instead of printing newlines.  ReadLine() would block until
            # the process finishes.  Read char-by-char and split on \r or \n.
            $reader   = $p.StandardOutput
            $lineBuf  = [System.Text.StringBuilder]::new()
            $lastPct  = -1

            while (-not $reader.EndOfStream) {
                $ch = [char]$reader.Read()

                if ($ch -eq "`r" -or $ch -eq "`n") {
                    $raw = $lineBuf.ToString()
                    $lineBuf.Clear() | Out-Null

                    if ([string]::IsNullOrWhiteSpace($raw)) { continue }
                    # Strip null bytes and ANSI escape sequences
                    $clean = ($raw -replace "`0", '' -replace '\x1b\[[0-9;]*[A-Za-z]', '').Trim()
                    if ([string]::IsNullOrWhiteSpace($clean)) { continue }

                    [void]$output.AppendLine($clean)

                    $pct = ParsePercent $clean
                    if ($pct -ge 0 -and $pct -ne $lastPct) {
                        $lastPct = $pct
                        SetProgress $pct
                        SetStatus "$label -- $pct% complete"
                        # Only append distinct progress lines to the log
                        AppendLine "$label -- $pct% complete"
                    } elseif ($pct -lt 0) {
                        # Non-progress line: always show
                        AppendLine $clean
                    }
                } else {
                    $lineBuf.Append($ch) | Out-Null
                }
            }

            # Flush any remaining text in buffer
            $remaining = $lineBuf.ToString().Trim()
            if ($remaining) {
                $clean = ($remaining -replace '\x1b\[[0-9;]*[A-Za-z]', '').Trim()
                if ($clean) {
                    [void]$output.AppendLine($clean)
                    AppendLine $clean
                }
            }

            # Read any remaining stderr
            $stderr = $p.StandardError.ReadToEnd()
            if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                $stderr.Split("`n") | ForEach-Object {
                    $l = $_.Trim()
                    if ($l) {
                        [void]$output.AppendLine($l)
                        AppendLine $l
                    }
                }
            }

            $p.WaitForExit()
            SetProgress 100
            AppendLine ""

            return $output.ToString()
        }

        # -- Build result card helper --
        function ShowResult([string]$tool, [string]$status, [string]$color, [string[]]$details) {
            Ui {
                $sp = New-Object System.Windows.Controls.StackPanel
                $sp.Orientation = "Horizontal"
                $sp.Margin = "0,3,0,3"

                $icon = New-Object System.Windows.Controls.TextBlock
                $icon.FontSize = 13
                $icon.Margin   = "0,0,8,0"
                if ($status -eq "Healthy") {
                    $icon.Text = [string][char]0x2714
                } elseif ($status -eq "Repaired") {
                    $icon.Text = [string][char]0x26A0
                } else {
                    $icon.Text = [string][char]0x2716
                }
                $icon.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($color))
                $sp.Children.Add($icon) | Out-Null

                $lbl = New-Object System.Windows.Controls.TextBlock
                $lbl.Text       = "$tool  --  $status"
                $lbl.FontSize   = 12
                $lbl.FontWeight = "SemiBold"
                $lbl.Foreground = $_win.Resources["FgBrush"]
                $sp.Children.Add($lbl) | Out-Null

                $_resultPanel.Children.Add($sp) | Out-Null

                foreach ($d in $details) {
                    $dt = New-Object System.Windows.Controls.TextBlock
                    $dt.Text       = "   $d"
                    $dt.FontSize   = 11
                    $dt.Foreground = $_win.Resources["MutedText"]
                    $dt.Margin     = "20,1,0,1"
                    $dt.TextWrapping = "Wrap"
                    $_resultPanel.Children.Add($dt) | Out-Null
                }
            }
        }

        # == Run the requested commands ==========================================
        $allResults = @()

        foreach ($cmd in $_commands) {
            $raw = RunTool $cmd

            if ([string]::IsNullOrWhiteSpace($raw)) {
                $allResults += @{ Tool = $cmd.ToUpper(); Status = "Error"; Color = "#e74c3c"; Details = @("Failed to start. Run as Administrator.") }
                continue
            }

            # Parse results
            if ($cmd -eq "sfc") {
                $parsed = @{ Tool = "SFC /scannow"; Status = "Unknown"; Color = "#95a5a6"; Details = @() }
                if ($raw -match "did not find any integrity violations") {
                    $parsed.Status = "Healthy"; $parsed.Color = "#2ecc71"
                    $parsed.Details += "No integrity violations found."
                }
                elseif ($raw -match "found corrupt files and successfully repaired") {
                    $parsed.Status = "Repaired"; $parsed.Color = "#f39c12"
                    $parsed.Details += "Corrupt files were found and repaired."
                }
                elseif ($raw -match "found corrupt files but was unable to fix") {
                    $parsed.Status = "Failed"; $parsed.Color = "#e74c3c"
                    $parsed.Details += "Corrupt files found but could not be repaired."
                    $parsed.Details += "Try running DISM first, then SFC again."
                }
                elseif ($raw -match "could not perform the requested operation") {
                    $parsed.Status = "Error"; $parsed.Color = "#e74c3c"
                    $parsed.Details += "SFC could not run. Try booting into Safe Mode."
                }
                else {
                    $parsed.Details += "Could not determine result -- check the output log."
                }
            } else {
                $parsed = @{ Tool = "DISM RestoreHealth"; Status = "Unknown"; Color = "#95a5a6"; Details = @() }
                if ($raw -match "The restore operation completed successfully") {
                    $parsed.Status = "Healthy"; $parsed.Color = "#2ecc71"
                    $parsed.Details += "Component store is healthy."
                }
                elseif ($raw -match "The component store corruption was repaired") {
                    $parsed.Status = "Repaired"; $parsed.Color = "#f39c12"
                    $parsed.Details += "Corruption was found and repaired."
                }
                elseif ($raw -match "Error:") {
                    $parsed.Status = "Failed"; $parsed.Color = "#e74c3c"
                    $parsed.Details += "DISM encountered an error. Check the output log."
                }
                else {
                    $parsed.Details += "Could not determine result -- check the output log."
                }
            }
            $allResults += $parsed
        }

        # -- Show results card --
        Ui {
            $_resultPanel.Children.Clear()
            $_resultCard.Visibility = "Visible"
        }

        foreach ($r in $allResults) {
            ShowResult $r.Tool $r.Status $r.Color $r.Details
        }

        # -- Determine final status line --
        $anyFailed = $allResults | Where-Object { $_.Status -eq "Failed" -or $_.Status -eq "Error" }
        $anyRepaired = $allResults | Where-Object { $_.Status -eq "Repaired" }

        if ($anyFailed) {
            $finalMsg   = "Completed with issues"
            $finalColor = "ErrorBrush"
        } elseif ($anyRepaired) {
            $finalMsg   = "Completed -- repairs were made"
            $finalColor = "WarningBrush"
        } else {
            $finalMsg   = "Completed -- system is healthy"
            $finalColor = "SuccessBrush"
        }

        Ui {
            $_statusTxt.Text       = $finalMsg
            $_statusTxt.Foreground = $_win.Resources[$finalColor]
            $_progressBar.Value    = 100
        }

        # -- Restore ready state --
        Ui {
            $_si.Text            = "* Ready"
            $_si.Foreground      = $_win.Resources["SuccessBrush"]
            $_fs.Text            = "Ready"
            $_btnSfc.IsEnabled   = $true
            $_btnDism.IsEnabled  = $true
            $_btnBoth.IsEnabled  = $true
            $_btnStop.IsEnabled  = $false
            $_btnStop.Opacity    = 0.4
            $_procHolder.Clear()
        }
    }) | Out-Null

    $ps.BeginInvoke() | Out-Null
}

# -- Button handlers ---------------------------------------------------------
$btnSfcRun.Add_Click({
    Start-SfcDismRunner -Commands @("sfc") -StatusLabel "Running SFC /scannow..."
})

$btnDismRun.Add_Click({
    Start-SfcDismRunner -Commands @("dism") -StatusLabel "Running DISM RestoreHealth..."
})

$btnSfcDismBoth.Add_Click({
    Start-SfcDismRunner -Commands @("dism","sfc") -StatusLabel "Running DISM + SFC..."
})

$btnSfcDismStop.Add_Click({
    if ($script:sfcDismProcHolder.Count -gt 0) {
        $p = $script:sfcDismProcHolder[0]
        if ($p -and -not $p.HasExited) {
            try { $p.Kill() } catch {}
        }
    }
})
