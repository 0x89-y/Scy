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
    $footerStatus.Text         = "Scy - $msg"
    $btnSfcRun.IsEnabled       = $false
    $btnDismRun.IsEnabled      = $false
    $btnSfcDismBoth.IsEnabled  = $false
    $btnSfcDismStop.IsEnabled  = $true
    $sfcDismResultCard.Visibility = "Collapsed"
    $sfcDismResultPanel.Children.Clear()
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

# -- Core runner (background runspace) ---------------------------------------
function Start-SfcDismRunner {
    param(
        [string[]]$Commands,   # e.g. @("sfc","dism") or @("sfc") or @("dism")
        [string]$StatusLabel
    )

    Set-SfcDismBusy $StatusLabel
    $sfcDismOutput.Text = ""

    Start-ScyJob `
        -Variables @{ _commands = $Commands; _procHolder = $script:sfcDismProcHolder } `
        -Work {
        param($emit)
        # UI updates travel back as messages, applied by the OnLine handler below.
        function AppendLine([string]$t) { & $emit @{ Kind = 'line';     Text  = $t } }
        function SetStatus([string]$t)  { & $emit @{ Kind = 'status';   Text  = $t } }
        function SetProgress([int]$v)   { & $emit @{ Kind = 'progress'; Value = $v } }

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
                $exe     = "sfc.exe"
                $exeArgs = "/scannow"
                $label   = "SFC /scannow"
            } else {
                $exe     = "DISM.exe"
                $exeArgs = "/Online /Cleanup-Image /RestoreHealth"
                $label   = "DISM /RestoreHealth"
            }

            AppendLine "> $label"
            AppendLine ("-" * 60)
            SetStatus "Running $label..."
            SetProgress 0

            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName               = $exe
            $psi.Arguments              = $exeArgs
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
                return $null
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
            $sawProgress = $false   # no progress at all = the tool refused to start

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
                        $sawProgress = $true
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

            return @{ Output = $output.ToString(); ExitCode = $p.ExitCode; SawProgress = $sawProgress }
        }

        # == Run the requested commands ==========================================
        $allResults = @()

        foreach ($cmd in $_commands) {
            $run = RunTool $cmd

            if ($null -eq $run -or [string]::IsNullOrWhiteSpace($run.Output)) {
                $allResults += @{ Tool = $cmd.ToUpper(); Status = "Error"; Color = "DangerBrush"; Details = @("Failed to start. Run as Administrator.") }
                continue
            }
            $raw  = $run.Output
            $code = $run.ExitCode
            # The text matches below are English-only. On other UI languages fall
            # back to the exit code so the card still says something useful.
            $codeNote = "Exit code $code. The result text wasn't recognised (non-English Windows?) - see the output log."
            $adminNote = "Requires administrator rights - start Scy with 'Run as administrator'."

            # Parse results
            if ($cmd -eq "sfc") {
                $parsed = @{ Tool = "SFC /scannow"; Status = "Unknown"; Color = "MutedText"; Details = @() }
                if ($code -ne 0 -and -not $run.SawProgress) {
                    # SFC refuses to start without elevation (exit 1, no scan progress)
                    $parsed.Status = "Error"; $parsed.Color = "DangerBrush"; $parsed.NeedsAdmin = $true
                    $parsed.Details += "SFC did not start (exit code $code)."
                    $parsed.Details += $adminNote
                }
                elseif ($raw -match "did not find any integrity violations") {
                    $parsed.Status = "Healthy"; $parsed.Color = "SuccessBrush"
                    $parsed.Details += "No integrity violations found."
                }
                elseif ($raw -match "found corrupt files and successfully repaired") {
                    $parsed.Status = "Repaired"; $parsed.Color = "WarningBrush"
                    $parsed.Details += "Corrupt files were found and repaired."
                }
                elseif ($raw -match "found corrupt files but was unable to fix") {
                    $parsed.Status = "Failed"; $parsed.Color = "DangerBrush"
                    $parsed.Details += "Corrupt files found but could not be repaired."
                    $parsed.Details += "Try running DISM first, then SFC again."
                }
                elseif ($raw -match "could not perform the requested operation") {
                    $parsed.Status = "Error"; $parsed.Color = "DangerBrush"
                    $parsed.Details += "SFC could not run. Try booting into Safe Mode."
                }
                elseif ($code -ne 0) {
                    $parsed.Status = "Error"; $parsed.Color = "DangerBrush"
                    $parsed.Details += $codeNote
                }
                else {
                    $parsed.Status = "Finished"
                    $parsed.Details += $codeNote
                }
            } else {
                $parsed = @{ Tool = "DISM RestoreHealth"; Status = "Unknown"; Color = "MutedText"; Details = @() }
                if ($code -eq 740) {
                    # ERROR_ELEVATION_REQUIRED
                    $parsed.Status = "Error"; $parsed.Color = "DangerBrush"; $parsed.NeedsAdmin = $true
                    $parsed.Details += $adminNote
                }
                elseif ($raw -match "The restore operation completed successfully") {
                    $parsed.Status = "Healthy"; $parsed.Color = "SuccessBrush"
                    $parsed.Details += "Component store is healthy."
                }
                elseif ($raw -match "The component store corruption was repaired") {
                    $parsed.Status = "Repaired"; $parsed.Color = "WarningBrush"
                    $parsed.Details += "Corruption was found and repaired."
                }
                elseif ($code -ne 0) {
                    # DISM returns 0 on success and a non-zero code on failure in every language
                    $parsed.Status = "Failed"; $parsed.Color = "DangerBrush"
                    $parsed.Details += "DISM exited with code $code. Check the output log."
                }
                else {
                    $parsed.Status = "Healthy"; $parsed.Color = "SuccessBrush"
                    $parsed.Details += "DISM completed successfully (exit code 0)."
                }
            }
            $allResults += $parsed
        }

        return $allResults
    } `
    -OnLine {
        param($m, $ctx)
        switch ($m.Kind) {
            'line'     { $sfcDismOutput.AppendText($m.Text + "`r`n"); $sfcDismOutput.ScrollToEnd() }
            'status'   { $sfcDismStatus.Text = $m.Text; $footerStatus.Text = "Scy - " + $m.Text }
            'progress' { $sfcDismProgress.Value = $m.Value }
        }
    } `
    -OnComplete {
        param($results, $err, $ctx)
        $script:sfcDismProcHolder.Clear()
        $footerStatus.Text          = "Ready"
        $btnSfcRun.IsEnabled        = $true
        $btnDismRun.IsEnabled       = $true
        $btnSfcDismBoth.IsEnabled   = $true
        $btnSfcDismStop.IsEnabled   = $false
        $sfcDismProgress.Value      = 100

        if ($err) {
            $sfcDismStatus.Text       = "Failed: " + $err.Exception.Message
            $sfcDismStatus.Foreground = $window.Resources["DangerBrush"]
            return
        }

        $results = @($results)
        $sfcDismResultPanel.Children.Clear()
        $sfcDismResultCard.Visibility = "Visible"
        foreach ($r in $results) { Add-SfcDismResultRow $r }

        if ($results | Where-Object { $_.Status -in "Failed", "Error" }) {
            $sfcDismStatus.Text = "Completed with issues"; $finalColor = "DangerBrush"
        } elseif ($results | Where-Object { $_.Status -eq "Repaired" }) {
            $sfcDismStatus.Text = "Completed -- repairs were made"; $finalColor = "WarningBrush"
        } elseif ($results | Where-Object { $_.Status -eq "Finished" }) {
            $sfcDismStatus.Text = "Completed -- see the result below"; $finalColor = "MutedText"
        } else {
            $sfcDismStatus.Text = "Completed -- system is healthy"; $finalColor = "SuccessBrush"
        }
        $sfcDismStatus.Foreground = $window.Resources[$finalColor]

        if ($results | Where-Object { $_.NeedsAdmin }) { Show-AdminRequiredError "Running SFC and DISM" }
    } | Out-Null
}

# -- Result card row (UI thread) ---------------------------------------------
# $Result.Color is a theme resource key (SuccessBrush, ...), not a hex value.
function Add-SfcDismResultRow {
    param([hashtable]$Result)

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = "Horizontal"
    $sp.Margin = "0,3,0,3"

    $icon = New-Object System.Windows.Controls.TextBlock
    $icon.FontSize = 13
    $icon.Margin   = "0,0,8,0"
    $icon.Text = switch ($Result.Status) {
        "Healthy"  { [string][char]0x2714 }
        "Repaired" { [string][char]0x26A0 }
        "Finished" { [string][char]0x2139 }
        default    { [string][char]0x2716 }
    }
    $icon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $Result.Color)
    $sp.Children.Add($icon) | Out-Null

    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text       = "$($Result.Tool)  --  $($Result.Status)"
    $lbl.FontSize   = 12
    $lbl.FontWeight = "SemiBold"
    $lbl.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
    $sp.Children.Add($lbl) | Out-Null
    $sfcDismResultPanel.Children.Add($sp) | Out-Null

    foreach ($d in $Result.Details) {
        $dt = New-Object System.Windows.Controls.TextBlock
        $dt.Text         = "   $d"
        $dt.FontSize     = 11
        $dt.Margin       = "20,1,0,1"
        $dt.TextWrapping = "Wrap"
        $dt.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
        $sfcDismResultPanel.Children.Add($dt) | Out-Null
    }
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
