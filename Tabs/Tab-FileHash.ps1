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
function Invoke-FileHash {
    param([string]$FilePath)

    if (-not (Test-Path $FilePath -PathType Leaf)) {
        $hashStatus.Text = "File not found: $FilePath"
        $hashResultsPanel.Visibility = "Collapsed"
        $btnHashCopy.IsEnabled = $false
        $btnHashCopy.Opacity = 0.4
        return
    }

    $hashStatus.Text = "Computing hashes..."
    $hashResultsPanel.Visibility = "Collapsed"
    $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)

    try {
        $md5    = (Get-FileHash -Path $FilePath -Algorithm MD5).Hash
        $sha1   = (Get-FileHash -Path $FilePath -Algorithm SHA1).Hash
        $sha256 = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash

        $hashMD5.Text    = $md5
        $hashSHA1.Text   = $sha1
        $hashSHA256.Text = $sha256

        $file = Get-Item $FilePath
        $sizeKB = [math]::Round($file.Length / 1KB, 1)
        $sizeMB = [math]::Round($file.Length / 1MB, 2)
        $sizeDisplay = if ($file.Length -ge 1MB) { "${sizeMB} MB" } else { "${sizeKB} KB" }
        $hashFileInfo.Text = "$($file.Name)  |  $sizeDisplay  |  Modified: $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"

        $hashResultsPanel.Visibility = "Visible"
        $hashStatus.Text = ""
        $btnHashCopy.IsEnabled = $true
        $btnHashCopy.Opacity = 1.0
    } catch {
        $hashStatus.Text = "Error: $($_.Exception.Message)"
        $hashResultsPanel.Visibility = "Collapsed"
        $btnHashCopy.IsEnabled = $false
        $btnHashCopy.Opacity = 0.4
    }
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
$btnHashVerify.Add_Click({
    $expected = $hashExpectedBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($expected)) {
        $hashVerifyResult.Visibility = "Collapsed"
        return
    }

    # Make sure we have hashes computed
    if ($hashResultsPanel.Visibility -ne "Visible") {
        $path = $hashFileBox.Text.Trim().Trim('"')
        if ($path) { Invoke-FileHash $path }
        if ($hashResultsPanel.Visibility -ne "Visible") { return }
    }

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
})

# ── Compare two files ────────────────────────────────────────────
$btnHashCompare.Add_Click({
    # First file should already be loaded
    if ($hashResultsPanel.Visibility -ne "Visible") {
        $path = $hashFileBox.Text.Trim().Trim('"')
        if ($path) { Invoke-FileHash $path }
        if ($hashResultsPanel.Visibility -ne "Visible") {
            $hashCompareResult.Visibility = "Collapsed"
            return
        }
    }

    $firstSHA256 = $hashSHA256.Text

    # Pick second file
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title = "Select second file to compare"
    $dialog.Filter = "All files (*.*)|*.*"
    if (-not $dialog.ShowDialog()) { return }

    $hashStatus.Text = "Computing hash for second file..."
    $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)

    try {
        $secondSHA256 = (Get-FileHash -Path $dialog.FileName -Algorithm SHA256).Hash

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
})
