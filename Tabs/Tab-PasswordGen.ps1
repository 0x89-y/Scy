# ── Password Generator ────────────────────────────────────────────

$btnPwdGenerate   = Find "BtnPwdGenerate"
$btnPwdCopy       = Find "BtnPwdCopy"
$btnPwdLenMinus   = Find "BtnPwdLenMinus"
$btnPwdLenPlus    = Find "BtnPwdLenPlus"
$btnPwdCntMinus   = Find "BtnPwdCntMinus"
$btnPwdCntPlus    = Find "BtnPwdCntPlus"
$pwdLengthBox     = Find "PwdLengthBox"
$pwdCountBox      = Find "PwdCountBox"
$pwdUpper         = Find "PwdUpper"
$pwdLower         = Find "PwdLower"
$pwdDigits        = Find "PwdDigits"
$pwdSymbols       = Find "PwdSymbols"
$pwdAmbiguous     = Find "PwdAmbiguous"
$pwdOutputBox     = Find "PwdOutputBox"
$pwdStrengthLabel = Find "PwdStrengthLabel"
$pwdStatus        = Find "PwdStatus"

function Get-PwdLength {
    $v = 0
    if ([int]::TryParse($pwdLengthBox.Text, [ref]$v)) { return [Math]::Max(4, [Math]::Min(128, $v)) }
    return 16
}

function Get-PwdCount {
    $v = 0
    if ([int]::TryParse($pwdCountBox.Text, [ref]$v)) { return [Math]::Max(1, [Math]::Min(20, $v)) }
    return 1
}

$btnPwdLenMinus.Add_Click({
    $pwdLengthBox.Text = [Math]::Max(4,   (Get-PwdLength) - 1)
})
$btnPwdLenPlus.Add_Click({
    $pwdLengthBox.Text = [Math]::Min(128, (Get-PwdLength) + 1)
})
$btnPwdCntMinus.Add_Click({
    $pwdCountBox.Text = [Math]::Max(1,  (Get-PwdCount) - 1)
})
$btnPwdCntPlus.Add_Click({
    $pwdCountBox.Text = [Math]::Min(20, (Get-PwdCount) + 1)
})

function Get-PasswordStrength {
    param([string]$Value)
    $len       = $Value.Length
    $hasUpper  = $Value -cmatch '[A-Z]'
    $hasLower  = $Value -cmatch '[a-z]'
    $hasDigit  = $Value -match  '[0-9]'
    $hasSymbol = $Value -match  '[^A-Za-z0-9]'
    $types     = (@($hasUpper, $hasLower, $hasDigit, $hasSymbol) | Where-Object { $_ }).Count

    $score = ($types - 1)
    if ($len -ge 8)  { $score++ }
    if ($len -ge 12) { $score++ }
    if ($len -ge 16) { $score++ }
    if ($len -ge 24) { $score++ }

    if ($score -le 2) { return @{ Label = "Weak";        Color = "#e17055" } }
    if ($score -le 4) { return @{ Label = "Fair";        Color = "#fdcb6e" } }
    if ($score -le 5) { return @{ Label = "Strong";      Color = "#00b894" } }
    return                    @{ Label = "Very Strong";  Color = "#00cec9" }
}

function Invoke-GeneratePasswords {
    $length = Get-PwdLength
    $count  = Get-PwdCount

    $charset = ""
    if ($pwdUpper.IsChecked)     { $charset += "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
    if ($pwdLower.IsChecked)     { $charset += "abcdefghijklmnopqrstuvwxyz" }
    if ($pwdDigits.IsChecked)    { $charset += "0123456789" }
    if ($pwdSymbols.IsChecked)   { $charset += "!@#$%^&*()_+-=[]{}|;:,.<>?" }

    if ($pwdAmbiguous.IsChecked) { $charset = $charset -replace '[0OlI1]', '' }

    if ($charset.Length -eq 0) {
        $pwdStatus.Text       = "Select at least one character type."
        $pwdStatus.Foreground = $window.Resources["DangerBrush"]
        return
    }

    $rng       = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $passwords = @()
    $csLen     = $charset.Length

    for ($p = 0; $p -lt $count; $p++) {
        $bytes = New-Object byte[] $length
        $rng.GetBytes($bytes)
        $password = -join ($bytes | ForEach-Object { $charset[$_ % $csLen] })
        $passwords += $password
    }
    $rng.Dispose()

    $pwdOutputBox.Text = $passwords -join "`n"

    $strength = Get-PasswordStrength -Value $passwords[0]
    $pwdStrengthLabel.Text       = $strength.Label
    $pwdStrengthLabel.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString($strength.Color)

    $countText = if ($count -eq 1) { "1 password" } else { "$count passwords" }
    $pwdStatus.Text       = "Generated $countText - $length characters each"
    $pwdStatus.Foreground = $window.Resources["SuccessBrush"]

    $btnPwdCopy.IsEnabled = $true
    $btnPwdCopy.Opacity   = 1.0
}

$btnPwdGenerate.Add_Click({ Invoke-GeneratePasswords })

$btnPwdCopy.Add_Click({
    if ([string]::IsNullOrEmpty($pwdOutputBox.Text)) { return }
    [System.Windows.Clipboard]::SetText($pwdOutputBox.Text)
    $btnPwdCopy.Content = "Copied!"
    $copyTimer = New-Object System.Windows.Threading.DispatcherTimer
    $copyTimer.Interval = [TimeSpan]::FromSeconds(2)
    $copyTimer.Add_Tick({
        $args[0].Stop()
        $btnPwdCopy.Content = "Copy"
    })
    $copyTimer.Start()
})
