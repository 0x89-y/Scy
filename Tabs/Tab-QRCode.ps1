# -- QR Code Generator Tab -----------------------------------------------------

$qrInputBox         = Find "QRInputBox"
$qrInputPlaceholder = Find "QRInputPlaceholder"
$qrOutputPanel      = Find "QROutputPanel"
$btnQRGenerate      = Find "BtnQRGenerate"
$btnQRSave          = Find "BtnQRSave"

$script:lastQRBitmap = $null
$script:lastQRText   = $null

$qrInputBox.Add_GotFocus({  $qrInputPlaceholder.Visibility = "Collapsed" })
$qrInputBox.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($qrInputBox.Text)) {
        $qrInputPlaceholder.Visibility = "Visible"
    }
})

# Generate on Ctrl+Enter
$qrInputBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return -and
        [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        Invoke-QRGenerate
    }
})

function Invoke-QRGenerate {
    $text = $qrInputBox.Text.Trim()
    $qrOutputPanel.Children.Clear()

    if ([string]::IsNullOrWhiteSpace($text)) {
        $tb          = [System.Windows.Controls.TextBlock]::new()
        $tb.Text     = "Enter some text above first."
        $tb.FontSize = 11
        $tb.Foreground = $window.Resources["MutedText"]
        $tb.HorizontalAlignment = "Center"
        $qrOutputPanel.Children.Add($tb) | Out-Null
        return
    }

    try {
        $qrImage = New-QRCodeImage -Text $text -ModuleSize 6 `
            -Dark ([System.Windows.Media.Colors]::Black) `
            -Light ([System.Windows.Media.Colors]::White)

        # White background border for contrast in dark theme
        $qrBorder = New-Object System.Windows.Controls.Border
        $qrBorder.Background   = [System.Windows.Media.Brushes]::White
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

        $script:lastQRBitmap = $qrImage
        $script:lastQRText   = $text
        $btnQRSave.IsEnabled = $true
        $btnQRSave.Opacity   = 1

        # Byte count info
        $byteLen = [System.Text.Encoding]::UTF8.GetByteCount($text)
        $hint          = New-Object System.Windows.Controls.TextBlock
        $hint.Text     = "$byteLen bytes encoded"
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

$btnQRSave.Add_Click({
    if (-not $script:lastQRText) { return }

    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter   = "PNG Image (*.png)|*.png"
    $dlg.FileName = "qrcode.png"
    if ($dlg.ShowDialog($window)) {
        # Re-generate at high resolution for a crisp export
        $hiRes = New-QRCodeImage -Text $script:lastQRText -ModuleSize 20 `
            -Dark ([System.Windows.Media.Colors]::Black) `
            -Light ([System.Windows.Media.Colors]::White)

        $encoder = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($hiRes))
        $stream = [System.IO.File]::Create($dlg.FileName)
        try {
            $encoder.Save($stream)
        } finally {
            $stream.Close()
        }
    }
})
