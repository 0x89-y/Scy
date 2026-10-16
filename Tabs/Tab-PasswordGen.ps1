# ── Password Generator ────────────────────────────────────────────

$btnPwdGenerate   = Find "BtnPwdGenerate"
$btnPwdCopy       = Find "BtnPwdCopy"
$btnPwdLenMinus   = Find "BtnPwdLenMinus"
$btnPwdLenPlus    = Find "BtnPwdLenPlus"
$btnPwdCntMinus   = Find "BtnPwdCntMinus"
$btnPwdCntPlus    = Find "BtnPwdCntPlus"
$btnPwdModeChars  = Find "BtnPwdModeChars"
$btnPwdModePhrase = Find "BtnPwdModePhrase"
$pwdLengthBox     = Find "PwdLengthBox"
$pwdLengthLabel   = Find "PwdLengthLabel"
$pwdLengthHint    = Find "PwdLengthHint"
$pwdCountBox      = Find "PwdCountBox"
$pwdCharOptions   = Find "PwdCharOptions"
$pwdPhraseOptions = Find "PwdPhraseOptions"
$pwdPhraseSep     = Find "PwdPhraseSeparator"
$pwdPhraseCaps    = Find "PwdPhraseCapitalize"
$pwdPhraseNumber  = Find "PwdPhraseNumber"
$pwdUpper         = Find "PwdUpper"
$pwdLower         = Find "PwdLower"
$pwdDigits        = Find "PwdDigits"
$pwdSymbols       = Find "PwdSymbols"
$pwdAmbiguous     = Find "PwdAmbiguous"
$pwdOutputBox     = Find "PwdOutputBox"
$pwdStrengthLabel = Find "PwdStrengthLabel"
$pwdStatus        = Find "PwdStatus"

# ── Mode: random characters or a passphrase of random words ──────
# Each mode keeps its own length (characters vs words).
$script:pwdMode   = "Chars"
$script:pwdLength = @{ Chars = 16; Phrase = 5 }
$script:pwdRange  = @{ Chars = @(4, 128); Phrase = @(3, 12) }

# EFF large word list (7776 words, ~12.9 bits each) - see Assets\NOTICE.txt
$script:pwdWordListPath = Join-Path $PSScriptRoot "..\Assets\eff_large_wordlist.txt"
$script:pwdWordList     = $null

function Get-PwdWordList {
    if ($null -eq $script:pwdWordList) {
        $script:pwdWordList = @(Get-Content -LiteralPath $script:pwdWordListPath -Encoding UTF8 |
            ForEach-Object { ($_ -split "`t")[1] } | Where-Object { $_ })
    }
    return ,$script:pwdWordList
}

function Get-PwdLength {
    $v = 0
    $r = $script:pwdRange[$script:pwdMode]
    if ([int]::TryParse($pwdLengthBox.Text, [ref]$v)) { return [Math]::Max($r[0], [Math]::Min($r[1], $v)) }
    return $script:pwdLength[$script:pwdMode]
}

function Get-PwdCount {
    $v = 0
    if ([int]::TryParse($pwdCountBox.Text, [ref]$v)) { return [Math]::Max(1, [Math]::Min(20, $v)) }
    return 1
}

function Set-PwdMode {
    param([ValidateSet("Chars", "Phrase")][string]$Mode)
    $script:pwdLength[$script:pwdMode] = Get-PwdLength      # remember the length of the mode we leave
    $script:pwdMode = $Mode
    $isPhrase = ($Mode -eq "Phrase")

    $pwdLengthBox.Text           = $script:pwdLength[$Mode]
    $pwdLengthLabel.Text         = if ($isPhrase) { "Words" } else { "Length" }
    $pwdLengthHint.Text          = if ($isPhrase) { "words  (3 - 12)" } else { "characters  (4 - 128)" }
    $pwdCharOptions.Visibility   = if ($isPhrase) { "Collapsed" } else { "Visible" }
    $pwdPhraseOptions.Visibility = if ($isPhrase) { "Visible" } else { "Collapsed" }

    foreach ($pair in @(@($btnPwdModeChars, (-not $isPhrase)), @($btnPwdModePhrase, $isPhrase))) {
        $key = if ($pair[1]) { "AccentBrush" } else { "BorderBrush" }
        $pair[0].SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, $key)
        $pair[0].SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, $(if ($pair[1]) { "AccentBrush" } else { "SubTextBrush" }))
    }
}

$btnPwdModeChars.Add_Click({  Set-PwdMode "Chars" })
$btnPwdModePhrase.Add_Click({ Set-PwdMode "Phrase" })
Set-PwdMode "Chars"

$btnPwdLenMinus.Add_Click({ $pwdLengthBox.Text = [Math]::Max($script:pwdRange[$script:pwdMode][0], (Get-PwdLength) - 1) })
$btnPwdLenPlus.Add_Click({  $pwdLengthBox.Text = [Math]::Min($script:pwdRange[$script:pwdMode][1], (Get-PwdLength) + 1) })
$btnPwdCntMinus.Add_Click({ $pwdCountBox.Text = [Math]::Max(1,  (Get-PwdCount) - 1) })
$btnPwdCntPlus.Add_Click({  $pwdCountBox.Text = [Math]::Min(20, (Get-PwdCount) + 1) })

# ── Randomness ───────────────────────────────────────────────────
# Uniform integer in [0, Max) from the OS CSPRNG. Rejection sampling: values in
# the incomplete top slice of the 32-bit range are redrawn, so no index is
# favoured (plain modulo would bias toward small indices).
function Get-PwdRandomIndex {
    param([System.Security.Cryptography.RandomNumberGenerator]$Rng, [int]$Max)
    $range = [uint64]4294967296
    $limit = $range - ($range % [uint64]$Max)
    $buf   = New-Object byte[] 4
    do {
        $Rng.GetBytes($buf)
        $v = [uint64][BitConverter]::ToUInt32($buf, 0)
    } while ($v -ge $limit)
    return [int]($v % [uint64]$Max)
}

# Strength from entropy (bits), not from which character classes appear.
function Get-PasswordStrength {
    param([double]$Bits)
    if ($Bits -lt 40) { return @{ Label = "Weak";        Color = "DangerBrush"  } }
    if ($Bits -lt 60) { return @{ Label = "Fair";        Color = "WarningBrush" } }
    if ($Bits -lt 80) { return @{ Label = "Strong";      Color = "SuccessBrush" } }
    return                    @{ Label = "Very strong"; Color = "SuccessBrush" }
}

function New-RandomCharPassword {
    param($Rng, [int]$Length, [string]$Charset, [string[]]$RequiredSets)
    # Redraw until every selected character type appears at least once. Redrawing
    # (rather than patching characters in) keeps the result uniform among valid passwords.
    do {
        $sb = [System.Text.StringBuilder]::new($Length)
        for ($i = 0; $i -lt $Length; $i++) { [void]$sb.Append($Charset[(Get-PwdRandomIndex $Rng $Charset.Length)]) }
        $pw = $sb.ToString()
        $ok = $true
        if ($Length -ge $RequiredSets.Count) {
            foreach ($set in $RequiredSets) {
                if ($pw.IndexOfAny($set.ToCharArray()) -lt 0) { $ok = $false; break }
            }
        }
    } while (-not $ok)
    return $pw
}

function New-Passphrase {
    param($Rng, [int]$Words, [string[]]$WordList, [string]$Separator, [bool]$Capitalize, [bool]$AddNumber)
    $parts = for ($i = 0; $i -lt $Words; $i++) {
        $w = $WordList[(Get-PwdRandomIndex $Rng $WordList.Count)]
        if ($Capitalize) { $w = $w.Substring(0, 1).ToUpperInvariant() + $w.Substring(1) }
        $w
    }
    $parts = @($parts)
    if ($AddNumber) {
        # one random digit on the end of one random word
        $at = Get-PwdRandomIndex $Rng $parts.Count
        $parts[$at] = $parts[$at] + [string](Get-PwdRandomIndex $Rng 10)
    }
    return ($parts -join $Separator)
}

function Invoke-GeneratePasswords {
    $length = Get-PwdLength
    $count  = Get-PwdCount
    $pwdLengthBox.Text = $length

    $rng       = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $passwords = @()
    try {
        if ($script:pwdMode -eq "Phrase") {
            $words = Get-PwdWordList
            if ($words.Count -lt 1000) {
                $pwdStatus.Text       = "Word list missing or damaged: $($script:pwdWordListPath)"
                $pwdStatus.Foreground = $window.Resources["DangerBrush"]
                return
            }
            $addNumber = [bool]$pwdPhraseNumber.IsChecked
            for ($p = 0; $p -lt $count; $p++) {
                $passwords += New-Passphrase -Rng $rng -Words $length -WordList $words -Separator $pwdPhraseSep.Text `
                                             -Capitalize ([bool]$pwdPhraseCaps.IsChecked) -AddNumber $addNumber
            }
            $bits = $length * [Math]::Log($words.Count, 2)
            if ($addNumber) { $bits += [Math]::Log(10, 2) + [Math]::Log($length, 2) }
            $unit = "words"
        } else {
            $sets = @()
            if ($pwdUpper.IsChecked)   { $sets += "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
            if ($pwdLower.IsChecked)   { $sets += "abcdefghijklmnopqrstuvwxyz" }
            if ($pwdDigits.IsChecked)  { $sets += "0123456789" }
            if ($pwdSymbols.IsChecked) { $sets += "!@#$%^&*()_+-=[]{}|;:,.<>?" }
            # -creplace: plain -replace is case-insensitive and would also strip o, i and L
            if ($pwdAmbiguous.IsChecked) { $sets = @($sets | ForEach-Object { $_ -creplace '[0OlI1]', '' }) }
            $charset = -join $sets

            if ($charset.Length -eq 0) {
                $pwdStatus.Text       = "Select at least one character type."
                $pwdStatus.Foreground = $window.Resources["DangerBrush"]
                return
            }
            for ($p = 0; $p -lt $count; $p++) {
                $passwords += New-RandomCharPassword -Rng $rng -Length $length -Charset $charset -RequiredSets $sets
            }
            $bits = $length * [Math]::Log($charset.Length, 2)
            $unit = "characters"
        }
    } finally {
        $rng.Dispose()
    }

    $pwdOutputBox.Text = $passwords -join "`n"

    $strength = Get-PasswordStrength -Bits $bits
    $pwdStrengthLabel.Text       = "$($strength.Label)  -  $([Math]::Round($bits)) bits"
    $pwdStrengthLabel.Foreground = $window.Resources[$strength.Color]

    $what = if ($script:pwdMode -eq "Phrase") { "passphrase" } else { "password" }
    $countText = if ($count -eq 1) { "1 $what" } else { "$count $($what)s" }
    $pwdStatus.Text       = "Generated $countText - $length $unit each"
    $pwdStatus.Foreground = $window.Resources["SuccessBrush"]

    $btnPwdCopy.IsEnabled = $true
    $btnPwdCopy.Opacity   = 1.0
}

$btnPwdGenerate.Add_Click({ Invoke-GeneratePasswords })

# ── Copy ─────────────────────────────────────────────────────────
# Copied secrets are marked so Windows keeps them out of clipboard history
# (Win+V) and doesn't sync them to other devices, and are cleared again after
# 30 seconds unless something else has been copied since.
function Set-SecretClipboard {
    param([string]$Text)
    $data = New-Object System.Windows.DataObject
    $data.SetData([System.Windows.DataFormats]::UnicodeText, $Text)
    $data.SetData("ExcludeClipboardContentFromMonitorProcessing", (New-Object System.IO.MemoryStream (, [byte[]](0))))
    $data.SetData("CanIncludeInClipboardHistory", (New-Object System.IO.MemoryStream (, [byte[]](0, 0, 0, 0))))
    $data.SetData("CanUploadToCloudClipboard",    (New-Object System.IO.MemoryStream (, [byte[]](0, 0, 0, 0))))
    [System.Windows.Clipboard]::SetDataObject($data, $true)
}

$script:pwdCopiedText  = $null
$script:pwdClearTimer  = New-Object System.Windows.Threading.DispatcherTimer
$script:pwdClearTimer.Interval = [TimeSpan]::FromSeconds(30)
$script:pwdClearTimer.Add_Tick({
    $script:pwdClearTimer.Stop()
    try {
        if ([System.Windows.Clipboard]::ContainsText() -and [System.Windows.Clipboard]::GetText() -eq $script:pwdCopiedText) {
            [System.Windows.Clipboard]::Clear()
            if ($pwdStatus.Text -like "Copied*") { $pwdStatus.Text = "Clipboard cleared." }
        }
    } catch {}
    $script:pwdCopiedText = $null
})

$btnPwdCopy.Add_Click({
    if ([string]::IsNullOrEmpty($pwdOutputBox.Text)) { return }
    try {
        Set-SecretClipboard $pwdOutputBox.Text
    } catch {
        $pwdStatus.Text       = "Could not copy: $($_.Exception.Message)"
        $pwdStatus.Foreground = $window.Resources["DangerBrush"]
        return
    }
    $script:pwdCopiedText = $pwdOutputBox.Text
    $script:pwdClearTimer.Stop(); $script:pwdClearTimer.Start()
    $pwdStatus.Text       = "Copied - kept out of clipboard history, and cleared from the clipboard in 30 seconds."
    $pwdStatus.Foreground = $window.Resources["SuccessBrush"]
    $btnPwdCopy.Content = "Copied!"
    $copyTimer = New-Object System.Windows.Threading.DispatcherTimer
    $copyTimer.Interval = [TimeSpan]::FromSeconds(2)
    $copyTimer.Add_Tick({
        $args[0].Stop()
        $btnPwdCopy.Content = "Copy"
    })
    $copyTimer.Start()
})
