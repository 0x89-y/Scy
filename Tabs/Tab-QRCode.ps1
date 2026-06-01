# -- QR Code Generator Tab -----------------------------------------------------

$qrInputBox         = Find "QRInputBox"
$qrInputPlaceholder = Find "QRInputPlaceholder"
$qrOutputPanel      = Find "QROutputPanel"
$btnQRGenerate      = Find "BtnQRGenerate"
$btnQRSave          = Find "BtnQRSave"
$btnQRCopy          = Find "BtnQRCopy"

$qrTemplateBox      = Find "QRTemplateBox"
$qrLevelBox         = Find "QRLevelBox"
$qrSizeBox          = Find "QRSizeBox"
$qrQuietZone        = Find "QRQuietZone"

# Data-type panels (one visible at a time)
$qrPanels = @{
    0 = (Find "QRPanel_Text")
    1 = (Find "QRPanel_Wifi")
    2 = (Find "QRPanel_Vcard")
    3 = (Find "QRPanel_Email")
    4 = (Find "QRPanel_Sms")
    5 = (Find "QRPanel_Phone")
    6 = (Find "QRPanel_Geo")
}

# Color swatches / pickers
$qrSwatchFg = Find "QRSwatch_Fg"
$qrSwatchBg = Find "QRSwatch_Bg"

$script:qrFg = "#000000"
$script:qrBg = "#FFFFFF"

# Last generated state (for copy / re-export)
$script:lastQRBitmap  = $null
$script:lastQRPayload = $null
$script:lastQRLevel   = "M"
$script:lastQRFg      = "#000000"
$script:lastQRBg      = "#FFFFFF"
$script:lastQRQuiet   = 4

# ── Helpers ───────────────────────────────────────────────────────────────────

function script:ConvertTo-QRColor([string]$hex) {
    return [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString($hex)
}

function script:Get-QRLevel {
    switch ([int]$qrLevelBox.SelectedIndex) {
        0 { return "L" }
        2 { return "Q" }
        3 { return "H" }
        default { return "M" }
    }
}

# Module pixel size for preview and for the exported file, per size selection.
function script:Get-QRScale {
    switch ([int]$qrSizeBox.SelectedIndex) {
        0 { return @{ Preview = 5; Export = 10 } }
        2 { return @{ Preview = 8; Export = 30 } }
        default { return @{ Preview = 6; Export = 20 } }
    }
}

# Escape a value for inclusion in a WIFI: payload (\ ; , : " are special).
function script:Format-WifiValue([string]$v) {
    if ($null -eq $v) { return "" }
    $v = $v -replace '\\', '\\'
    $v = $v -replace ';',  '\;'
    $v = $v -replace ',',  '\,'
    $v = $v -replace ':',  '\:'
    $v = $v -replace '"',  '\"'
    return $v
}

# Build the encoded payload string from the currently selected data type.
function script:Build-QRPayload {
    switch ([int]$qrTemplateBox.SelectedIndex) {
        1 {  # Wi-Fi
            $ssid = $script:qrc["QRWifiSsid"].Text
            if ([string]::IsNullOrWhiteSpace($ssid)) { return "" }
            $pwd  = $script:qrc["QRWifiPassword"].Text
            $auth = switch ([int]$script:qrc["QRWifiAuth"].SelectedIndex) {
                1 { "WEP" }
                2 { "nopass" }
                default { "WPA" }
            }
            $hidden = if ($script:qrc["QRWifiHidden"].IsChecked) { "true" } else { "false" }
            $sEsc = script:Format-WifiValue $ssid
            $pEsc = script:Format-WifiValue $pwd
            if ($auth -eq "nopass") { $pEsc = "" }
            return "WIFI:T:$auth;S:$sEsc;P:$pEsc;H:$hidden;;"
        }
        2 {  # Contact (vCard)
            $name = $script:qrc["QRVcardName"].Text
            $org  = $script:qrc["QRVcardOrg"].Text
            $tel  = $script:qrc["QRVcardPhone"].Text
            $mail = $script:qrc["QRVcardEmail"].Text
            $url  = $script:qrc["QRVcardUrl"].Text
            if ([string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace($tel) -and
                [string]::IsNullOrWhiteSpace($mail)) { return "" }
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("BEGIN:VCARD")
            $lines.Add("VERSION:3.0")
            if (-not [string]::IsNullOrWhiteSpace($name)) { $lines.Add("N:$name"); $lines.Add("FN:$name") }
            if (-not [string]::IsNullOrWhiteSpace($org))  { $lines.Add("ORG:$org") }
            if (-not [string]::IsNullOrWhiteSpace($tel))  { $lines.Add("TEL:$tel") }
            if (-not [string]::IsNullOrWhiteSpace($mail)) { $lines.Add("EMAIL:$mail") }
            if (-not [string]::IsNullOrWhiteSpace($url))  { $lines.Add("URL:$url") }
            $lines.Add("END:VCARD")
            return ($lines -join "`n")
        }
        3 {  # Email
            $to = $script:qrc["QREmailTo"].Text
            if ([string]::IsNullOrWhiteSpace($to)) { return "" }
            $subject = $script:qrc["QREmailSubject"].Text
            $body    = $script:qrc["QREmailBody"].Text
            $query = [System.Collections.Generic.List[string]]::new()
            if (-not [string]::IsNullOrWhiteSpace($subject)) { $query.Add("subject=" + [Uri]::EscapeDataString($subject)) }
            if (-not [string]::IsNullOrWhiteSpace($body))    { $query.Add("body=" + [Uri]::EscapeDataString($body)) }
            $q = if ($query.Count -gt 0) { "?" + ($query -join "&") } else { "" }
            return "mailto:$to$q"
        }
        4 {  # SMS
            $num = $script:qrc["QRSmsNumber"].Text
            if ([string]::IsNullOrWhiteSpace($num)) { return "" }
            $msg = $script:qrc["QRSmsMessage"].Text
            if (-not [string]::IsNullOrWhiteSpace($msg)) { return "SMSTO:$num:$msg" }
            return "SMSTO:$num"
        }
        5 {  # Phone
            $num = $script:qrc["QRPhoneNumber"].Text
            if ([string]::IsNullOrWhiteSpace($num)) { return "" }
            return "tel:$num"
        }
        6 {  # Geo location
            $lat = $script:qrc["QRGeoLat"].Text
            $lon = $script:qrc["QRGeoLon"].Text
            if ([string]::IsNullOrWhiteSpace($lat) -or [string]::IsNullOrWhiteSpace($lon)) { return "" }
            return "geo:$($lat.Trim()),$($lon.Trim())"
        }
        default {  # Text / URL
            return $qrInputBox.Text.Trim()
        }
    }
}

# Resolve and cache the data-entry controls referenced by Build-QRPayload.
$script:qrc = @{}
foreach ($n in @("QRWifiSsid","QRWifiPassword","QRWifiAuth","QRWifiHidden",
                 "QRVcardName","QRVcardOrg","QRVcardPhone","QRVcardEmail","QRVcardUrl",
                 "QREmailTo","QREmailSubject","QREmailBody",
                 "QRSmsNumber","QRSmsMessage","QRPhoneNumber",
                 "QRGeoLat","QRGeoLon")) {
    $script:qrc[$n] = Find $n
}

function script:Set-QRSwatch($swatch, [string]$hex) {
    $swatch.Background = ([System.Windows.Media.SolidColorBrush]::new((script:ConvertTo-QRColor $hex))).psobject.BaseObject
}

# ── Placeholder + template switching ──────────────────────────────────────────

$qrInputBox.Add_GotFocus({  $qrInputPlaceholder.Visibility = "Collapsed" })
$qrInputBox.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($qrInputBox.Text)) {
        $qrInputPlaceholder.Visibility = "Visible"
    }
})

$qrTemplateBox.Add_SelectionChanged({
    [int]$idx = $qrTemplateBox.SelectedIndex
    foreach ($k in $qrPanels.Keys) {
        $qrPanels[$k].Visibility = if ($k -eq $idx) { "Visible" } else { "Collapsed" }
    }
})

# Generate on Ctrl+Enter from the text box
$qrInputBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return -and
        [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        Invoke-QRGenerate
    }
})

# ── Generation ────────────────────────────────────────────────────────────────

function Invoke-QRGenerate {
    $payload = script:Build-QRPayload
    $qrOutputPanel.Children.Clear()

    if ([string]::IsNullOrWhiteSpace($payload)) {
        $tb          = [System.Windows.Controls.TextBlock]::new()
        $tb.Text     = "Fill in the fields above first."
        $tb.FontSize = 11
        $tb.Foreground = $window.Resources["MutedText"]
        $tb.HorizontalAlignment = "Center"
        $qrOutputPanel.Children.Add($tb) | Out-Null
        return
    }

    try {
        $level = script:Get-QRLevel
        $scale = script:Get-QRScale
        $quiet = if ($qrQuietZone.IsChecked) { 4 } else { 0 }
        $dark  = script:ConvertTo-QRColor $script:qrFg
        $light = script:ConvertTo-QRColor $script:qrBg

        $qrImage = New-QRCodeImage -Text $payload -ModuleSize $scale.Preview `
            -Dark $dark -Light $light -Level $level -QuietZone $quiet

        # Background border for contrast in dark theme (uses chosen bg color)
        $qrBorder = New-Object System.Windows.Controls.Border
        $qrBorder.Background   = ([System.Windows.Media.SolidColorBrush]::new($light)).psobject.BaseObject
        $qrBorder.CornerRadius = [System.Windows.CornerRadius]::new(6)
        $qrBorder.Padding      = [System.Windows.Thickness]::new(8)
        $qrBorder.HorizontalAlignment = "Center"
        $qrBorder.Margin       = [System.Windows.Thickness]::new(0, 4, 0, 8)

        $img = New-Object System.Windows.Controls.Image
        $img.Source = $qrImage
        $img.Width  = $qrImage.PixelWidth
        $img.Height = $qrImage.PixelHeight
        $img.SetValue([System.Windows.Media.RenderOptions]::BitmapScalingModeProperty,
            [System.Windows.Media.BitmapScalingMode]::NearestNeighbor)
        $qrBorder.Child = $img
        $qrOutputPanel.Children.Add($qrBorder) | Out-Null

        $script:lastQRBitmap  = $qrImage
        $script:lastQRPayload = $payload
        $script:lastQRLevel   = $level
        $script:lastQRFg      = $script:qrFg
        $script:lastQRBg      = $script:qrBg
        $script:lastQRQuiet   = $quiet

        $btnQRSave.IsEnabled = $true; $btnQRSave.Opacity = 1
        $btnQRCopy.IsEnabled = $true; $btnQRCopy.Opacity = 1

        $byteLen = [System.Text.Encoding]::UTF8.GetByteCount($payload)
        $hint          = New-Object System.Windows.Controls.TextBlock
        $hint.Text     = "$byteLen bytes • level $level"
        $hint.FontSize = 11
        $hint.Foreground = $window.Resources["MutedText"]
        $hint.HorizontalAlignment = "Center"
        $qrOutputPanel.Children.Add($hint) | Out-Null
    } catch {
        $tb          = [System.Windows.Controls.TextBlock]::new()
        $tb.Text     = "Error: $_"
        $tb.FontSize = 11
        $tb.Foreground = $window.Resources["DangerBrush"]
        $tb.HorizontalAlignment = "Center"
        $tb.TextWrapping = "Wrap"
        $qrOutputPanel.Children.Add($tb) | Out-Null
    }
}

$btnQRGenerate.Add_Click({ Invoke-QRGenerate })

# ── Color pickers ─────────────────────────────────────────────────────────────

function script:Invoke-QRColorPick([string]$which) {
    $cur = if ($which -eq "Fg") { $script:qrFg } else { $script:qrBg }
    $r = [Convert]::ToInt32($cur.Substring(1,2), 16)
    $g = [Convert]::ToInt32($cur.Substring(3,2), 16)
    $b = [Convert]::ToInt32($cur.Substring(5,2), 16)
    $dlg          = New-Object System.Windows.Forms.ColorDialog
    $dlg.FullOpen = $true
    $dlg.Color    = [System.Drawing.Color]::FromArgb($r, $g, $b)
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $c   = $dlg.Color
        $hex = "#{0:X2}{1:X2}{2:X2}" -f $c.R, $c.G, $c.B
        if ($which -eq "Fg") { $script:qrFg = $hex; script:Set-QRSwatch $qrSwatchFg $hex }
        else                 { $script:qrBg = $hex; script:Set-QRSwatch $qrSwatchBg $hex }
    }
}

(Find "QRPick_Fg").Add_Click({  script:Invoke-QRColorPick "Fg" })
(Find "QRPick_Bg").Add_Click({  script:Invoke-QRColorPick "Bg" })
(Find "QRReset_Fg").Add_Click({ $script:qrFg = "#000000"; script:Set-QRSwatch $qrSwatchFg "#000000" })
(Find "QRReset_Bg").Add_Click({ $script:qrBg = "#FFFFFF"; script:Set-QRSwatch $qrSwatchBg "#FFFFFF" })

# ── Copy to clipboard ─────────────────────────────────────────────────────────

$btnQRCopy.Add_Click({
    if (-not $script:lastQRBitmap) { return }
    try {
        [System.Windows.Clipboard]::SetImage($script:lastQRBitmap)
        $orig = $btnQRCopy.Content
        $btnQRCopy.Content = "Copied!"
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds(2)
        $timer.Add_Tick({ $btnQRCopy.Content = $orig; $timer.Stop() }.GetNewClosure())
        $timer.Start()
    } catch {
        Show-ScyToast "QR code" "Could not copy image: $_"
    }
})

# ── Save (PNG / SVG / JPEG) ───────────────────────────────────────────────────

$btnQRSave.Add_Click({
    if (-not $script:lastQRPayload) { return }

    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter   = "PNG image (*.png)|*.png|SVG vector (*.svg)|*.svg|JPEG image (*.jpg)|*.jpg"
    $dlg.FileName = "qrcode.png"
    if (-not $dlg.ShowDialog($window)) { return }

    $path = $dlg.FileName
    $ext  = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    $scale = script:Get-QRScale
    $dark  = script:ConvertTo-QRColor $script:lastQRFg
    $light = script:ConvertTo-QRColor $script:lastQRBg

    try {
        if ($ext -eq ".svg") {
            $svg = New-QRCodeSvg -Text $script:lastQRPayload -Level $script:lastQRLevel `
                -Dark $dark -Light $light -ModuleSize $scale.Export -QuietZone $script:lastQRQuiet
            [System.IO.File]::WriteAllText($path, $svg, [System.Text.Encoding]::UTF8)
        } else {
            $hiRes = New-QRCodeImage -Text $script:lastQRPayload -ModuleSize $scale.Export `
                -Dark $dark -Light $light -Level $script:lastQRLevel -QuietZone $script:lastQRQuiet

            if ($ext -eq ".jpg" -or $ext -eq ".jpeg") {
                $encoder = [System.Windows.Media.Imaging.JpegBitmapEncoder]::new()
                $encoder.QualityLevel = 95
            } else {
                $encoder = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
            }
            $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($hiRes))
            $stream = [System.IO.File]::Create($path)
            try { $encoder.Save($stream) } finally { $stream.Close() }
        }
        Show-ScyToast "QR code" "Saved to $([System.IO.Path]::GetFileName($path))"
    } catch {
        Show-ScyToast "QR code" "Save failed: $_"
    }
})
