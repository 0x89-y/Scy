# ── File Hashing Tool ────────────────────────────────────────────
$hashFileBox          = Find "HashFileBox"
$hashFilePlaceholder  = Find "HashFilePlaceholder"
$hashResultsPanel     = Find "HashResultsPanel"
$hashMD5              = Find "HashMD5"
$hashSHA1             = Find "HashSHA1"
$hashSHA256           = Find "HashSHA256"
$hashFileInfo         = Find "HashFileInfo"
$hashStatus           = Find "HashStatus"
$btnHashBrowse        = Find "BtnHashBrowse"
$btnHashCopy          = Find "BtnHashCopy"
$btnHashCompare       = Find "BtnHashCompare"
$btnHashVerify        = Find "BtnHashVerify"
$hashExpectedBox      = Find "HashExpectedBox"
$hashExpectedPlaceholder = Find "HashExpectedPlaceholder"
$hashVerifyResult     = Find "HashVerifyResult"
$hashVerifyText       = Find "HashVerifyText"
$hashCompareResult    = Find "HashCompareResult"
$hashCompareText      = Find "HashCompareText"

# ── Placeholder behavior ────────────────────────────────────────
$hashFileBox.Add_GotFocus({  $hashFilePlaceholder.Visibility = "Collapsed" })
$hashFileBox.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($hashFileBox.Text)) {
        $hashFilePlaceholder.Visibility = "Visible"
    }
})

$hashExpectedBox.Add_GotFocus({  $hashExpectedPlaceholder.Visibility = "Collapsed" })
$hashExpectedBox.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($hashExpectedBox.Text)) {
        $hashExpectedPlaceholder.Visibility = "Visible"
    }
})

# ── Drag-and-drop support ───────────────────────────────────────
$hashFileBox.Add_PreviewDragOver({
    param($s, $e)
    if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $e.Effects = [System.Windows.DragDropEffects]::Copy
        $e.Handled = $true
    }
})

$hashFileBox.Add_Drop({
    param($s, $e)
    if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $files = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
        if ($files.Count -gt 0) {
            $hashFileBox.Text = $files[0]
            $hashFilePlaceholder.Visibility = "Collapsed"
            Invoke-FileHash $files[0]
        }
        $e.Handled = $true
    }
})

# ── Compute hashes ──────────────────────────────────────────────
# Runs in a background job and reads the file once, feeding MD5/SHA1/SHA256 in
# the same pass (it used to read it three times on the UI thread, freezing the
# window on large files). $Then runs on the UI thread after a successful hash.
$script:hashBusy = $false

function Invoke-FileHash {
    param([string]$FilePath, [scriptblock]$Then)
    if ($script:hashBusy) { return }

    if (-not (Test-Path $FilePath -PathType Leaf)) {
        $hashStatus.Text = "File not found: $FilePath"
        $hashResultsPanel.Visibility = "Collapsed"
        $btnHashCopy.IsEnabled = $false
        return
    }

    $script:hashBusy = $true
    $hashStatus.Text = "Computing hashes..."
    $hashResultsPanel.Visibility = "Collapsed"
    $hashVerifyResult.Visibility = "Collapsed"
    $hashCompareResult.Visibility = "Collapsed"

    Start-ScyJob `
        -Variables @{ path = $FilePath } `
        -Context   @{ Then = $Then } `
        -Work {
            param($emit)
            $algos = [ordered]@{
                MD5    = [System.Security.Cryptography.MD5]::Create()
                SHA1   = [System.Security.Cryptography.SHA1]::Create()
                SHA256 = [System.Security.Cryptography.SHA256]::Create()
            }
            $fs = [System.IO.File]::OpenRead($path)
            try {
                $buf = New-Object byte[] (1MB)
                $total = $fs.Length; $done = 0L; $lastPct = -1
                while (($n = $fs.Read($buf, 0, $buf.Length)) -gt 0) {
                    foreach ($h in $algos.Values) { [void]$h.TransformBlock($buf, 0, $n, $null, 0) }
                    $done += $n
                    $pct = [int](100 * $done / [Math]::Max(1, $total))
                    if ($pct -ne $lastPct) { $lastPct = $pct; & $emit $pct }
                }
                foreach ($h in $algos.Values) { [void]$h.TransformFinalBlock($buf, 0, 0) }
            } finally { $fs.Dispose() }

            $file = Get-Item -LiteralPath $path
            $out = @{ Name = $file.Name; Length = $file.Length; Modified = $file.LastWriteTime }
            foreach ($k in $algos.Keys) {
                $out[$k] = [System.BitConverter]::ToString($algos[$k].Hash).Replace('-', '')
                $algos[$k].Dispose()
            }
            return $out
        } `
        -OnLine {
            param($pct, $ctx)
            $hashStatus.Text = "Computing hashes... $pct%"
        } `
        -OnComplete {
            param($r, $err, $ctx)
            $script:hashBusy = $false
            if ($err) {
                $hashStatus.Text = "Error: $($err.Exception.Message)"
                $hashResultsPanel.Visibility = "Collapsed"
                $btnHashCopy.IsEnabled = $false
                return
            }

            $hashMD5.Text    = $r.MD5
            $hashSHA1.Text   = $r.SHA1
            $hashSHA256.Text = $r.SHA256

            $sizeDisplay = if ($r.Length -ge 1MB) { "$([math]::Round($r.Length / 1MB, 2)) MB" } else { "$([math]::Round($r.Length / 1KB, 1)) KB" }
            $hashFileInfo.Text = "$($r.Name)  |  $sizeDisplay  |  Modified: $($r.Modified.ToString('yyyy-MM-dd HH:mm'))"

            $hashResultsPanel.Visibility = "Visible"
            $hashStatus.Text = ""
            $btnHashCopy.IsEnabled = $true
            if ($ctx.Then) { & $ctx.Then }
        } | Out-Null
}

# ── Browse button ────────────────────────────────────────────────
$btnHashBrowse.Add_Click({
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title = "Select a file to hash"
    $dialog.Filter = "All files (*.*)|*.*"
    if ($dialog.ShowDialog()) {
        $hashFileBox.Text = $dialog.FileName
        $hashFilePlaceholder.Visibility = "Collapsed"
        Invoke-FileHash $dialog.FileName
    }
})

# ── Hash on Enter key ───────────────────────────────────────────
$hashFileBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return) {
        $path = $hashFileBox.Text.Trim().Trim('"')
        if ($path) { Invoke-FileHash $path }
        $e.Handled = $true
    }
})

# ── Copy all hashes ─────────────────────────────────────────────
$btnHashCopy.Add_Click({
    $text = @(
        "MD5:    $($hashMD5.Text)"
        "SHA1:   $($hashSHA1.Text)"
        "SHA256: $($hashSHA256.Text)"
    ) -join "`r`n"
    [System.Windows.Clipboard]::SetText($text)
    $hashStatus.Text = "Copied to clipboard"
    $fadeTimer = New-Object System.Windows.Threading.DispatcherTimer
    $fadeTimer.Interval = [TimeSpan]::FromSeconds(2)
    $fadeTimer.Add_Tick({
        $args[0].Stop()
        if ($hashStatus.Text -eq "Copied to clipboard") { $hashStatus.Text = "" }
    })
    $fadeTimer.Start()
})

# ── Verify hash ──────────────────────────────────────────────────
function Test-ExpectedHash {
    $expected = $hashExpectedBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($expected)) {
        $hashVerifyResult.Visibility = "Collapsed"
        return
    }

    # Accept pasted forms like "sha256: ABC..." / "SHA-256=abc..." - drop the
    # label first, otherwise its letters (the A in SHA) leak into the hex.
    $expected = $expected -replace '^\s*(md5|sha-?1|sha-?256)\s*[:=]?\s*', ''
    $expected = $expected.ToUpperInvariant() -replace '[^A-F0-9]', ''
    $match = $false
    $matchAlgo = ""

    foreach ($algo in @(@("MD5", $hashMD5.Text), @("SHA1", $hashSHA1.Text), @("SHA256", $hashSHA256.Text))) {
        if ($algo[1] -eq $expected) {
            $match = $true
            $matchAlgo = $algo[0]
            break
        }
    }

    if ($match) {
        $hashVerifyText.Text = "Match  -  $matchAlgo hash matches the expected value"
        $hashVerifyText.Foreground = $window.Resources["SuccessBrush"]
        $hashVerifyResult.Background = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromArgb(30, 0, 184, 148))
    } else {
        $hashVerifyText.Text = "Mismatch  -  No computed hash matches the expected value"
        $hashVerifyText.Foreground = $window.Resources["DangerBrush"]
        $hashVerifyResult.Background = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromArgb(30, 225, 112, 85))
    }
    $hashVerifyResult.Visibility = "Visible"
}

$btnHashVerify.Add_Click({
    if ([string]::IsNullOrWhiteSpace($hashExpectedBox.Text)) {
        $hashVerifyResult.Visibility = "Collapsed"
        return
    }
    if ($hashResultsPanel.Visibility -eq "Visible") { Test-ExpectedHash; return }

    # Nothing hashed yet: hash the file first, then verify once it's done
    $path = $hashFileBox.Text.Trim().Trim('"')
    if ($path) { Invoke-FileHash $path -Then { Test-ExpectedHash } }
})

# ── Compare two files ────────────────────────────────────────────
# Pick a second file and compare its SHA256 with the loaded one (hashed in a background job).
function Compare-WithSecondFile {
    $firstSHA256 = $hashSHA256.Text

    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title = "Select second file to compare"
    $dialog.Filter = "All files (*.*)|*.*"
    if (-not $dialog.ShowDialog()) { return }

    $script:hashBusy = $true
    $hashStatus.Text = "Computing hash for second file..."
    Start-ScyJob `
        -Variables @{ path = $dialog.FileName } `
        -Context   @{ First = $firstSHA256 } `
        -Work {
            param($emit)
            return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        } `
        -OnComplete {
            param($secondSHA256, $err, $ctx)
            $script:hashBusy = $false
            Show-HashComparison -First $ctx.First -Second $secondSHA256 -ErrorRecord $err
        } | Out-Null
}

function Show-HashComparison {
    param([string]$First, [string]$Second, $ErrorRecord)
    $firstSHA256 = $First; $secondSHA256 = $Second
    try {
        if ($ErrorRecord) { throw $ErrorRecord }

        if ($firstSHA256 -eq $secondSHA256) {
            $hashCompareText.Text = "Identical  -  Both files have the same SHA256 hash"
            $hashCompareText.Foreground = $window.Resources["SuccessBrush"]
            $hashCompareResult.Background = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.Color]::FromArgb(30, 0, 184, 148))
        } else {
            $hashCompareText.Text = "Different  -  Files have different SHA256 hashes"
            $hashCompareText.Foreground = $window.Resources["DangerBrush"]
            $hashCompareResult.Background = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.Color]::FromArgb(30, 225, 112, 85))
        }
        $hashCompareResult.Visibility = "Visible"
        $hashStatus.Text = ""
    } catch {
        $hashStatus.Text = "Error: $($_.Exception.Message)"
        $hashCompareResult.Visibility = "Collapsed"
    }
}

$btnHashCompare.Add_Click({
    if ($script:hashBusy) { return }
    if ($hashResultsPanel.Visibility -eq "Visible") { Compare-WithSecondFile; return }

    # First file not hashed yet: hash it, then ask for the second one
    $path = $hashFileBox.Text.Trim().Trim('"')
    if ($path) { Invoke-FileHash $path -Then { Compare-WithSecondFile } }
    else { $hashCompareResult.Visibility = "Collapsed" }
})
