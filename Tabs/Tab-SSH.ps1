# ── SSH Key Manager Tab ───────────────────────────────────────────

$sshKeyPanel       = Find "SSHKeyPanel"
$sshGenerateStatus = Find "SSHGenerateStatus"

$sshDir = Join-Path $env:USERPROFILE ".ssh"

# ── Build a row for one key pair ─────────────────────────────────
function New-SSHKeyRow {
    param([string]$PubKeyPath, [bool]$Alternate = $false)

    $keyName = [System.IO.Path]::GetFileNameWithoutExtension($PubKeyPath)
    $pubText = ""
    try { $pubText = (Get-Content $PubKeyPath -Raw -ErrorAction Stop).Trim() } catch {}

    $border            = New-Object System.Windows.Controls.Border
    $bgKey = if ($Alternate) { "SurfaceBrush" } else { "InputBgBrush" }
    $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $bgKey)
    $border.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $border.Padding    = [System.Windows.Thickness]::new(10, 8, 10, 8)
    $border.Margin     = [System.Windows.Thickness]::new(0, 0, 0, 3)

    $grid = New-Object System.Windows.Controls.Grid
    $c0   = New-Object System.Windows.Controls.ColumnDefinition
    $c0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $c1   = New-Object System.Windows.Controls.ColumnDefinition
    $c1.Width = [System.Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($c0)
    $grid.ColumnDefinitions.Add($c1)

    # Left: key name + fingerprint preview
    $left = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($left, 0)

    $nameTb          = New-Object System.Windows.Controls.TextBlock
    $nameTb.Text     = $keyName
    $nameTb.FontSize = 13
    $nameTb.FontWeight = "SemiBold"
    $nameTb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")

    $previewTb           = New-Object System.Windows.Controls.TextBlock
    $previewTb.FontSize  = 10
    $previewTb.TextTrimming = "CharacterEllipsis"
    $previewTb.Margin    = [System.Windows.Thickness]::new(0, 2, 0, 0)
    $previewTb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")

    # Try to get fingerprint; fall back to truncated pub key
    try {
        if (Get-Command ssh-keygen -ErrorAction SilentlyContinue) {
            $fp = & ssh-keygen -lf $PubKeyPath 2>$null
            $previewTb.Text = if ($fp) { $fp } else { $pubText.Substring(0, [Math]::Min(80, $pubText.Length)) + "..." }
        } else {
            $previewTb.Text = $pubText.Substring(0, [Math]::Min(80, $pubText.Length)) + "..."
        }
    } catch {
        $previewTb.Text = "(could not read key)"
    }

    $left.Children.Add($nameTb)    | Out-Null
    $left.Children.Add($previewTb) | Out-Null

    # Right: copy button
    $copyBtn         = New-Object System.Windows.Controls.Button
    $copyBtn.Content = "copy pubkey"
    $copyBtn.Style   = $window.Resources["CopyButton"]
    $copyBtn.VerticalAlignment = "Center"
    $copyBtn.Margin  = [System.Windows.Thickness]::new(10, 0, 0, 0)
    $capturedPub = $pubText
    $capturedBtn = $copyBtn
    $copyBtn.Add_Click({
        if ($capturedPub) {
            [System.Windows.Clipboard]::SetText($capturedPub)
            $capturedBtn.Content = ([char]0x2713) + " copied"
            $t = New-Object System.Windows.Threading.DispatcherTimer
            $t.Interval = [TimeSpan]::FromSeconds(1.5)
            $t.Tag = $capturedBtn
            $t.Add_Tick({
                $args[0].Tag.Content = "copy pubkey"
                $args[0].Stop()
            })
            $t.Start()
        }
    }.GetNewClosure())
    [System.Windows.Controls.Grid]::SetColumn($copyBtn, 1)

    $grid.Children.Add($left)    | Out-Null
    $grid.Children.Add($copyBtn) | Out-Null
    $border.Child = $grid
    return $border
}

# ── Populate key list ─────────────────────────────────────────────
function Populate-SSHKeys {
    $sshKeyPanel.Children.Clear()

    if (-not (Test-Path $sshDir)) {
        $tb          = New-Object System.Windows.Controls.TextBlock
        $tb.Text     = "~/.ssh/ directory not found."
        $tb.FontSize = 12
        $tb.Margin   = [System.Windows.Thickness]::new(2, 2, 0, 2)
        $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
        $sshKeyPanel.Children.Add($tb) | Out-Null
        return
    }

    $pubKeys = @(Get-ChildItem -Path $sshDir -Filter "*.pub" -ErrorAction SilentlyContinue)

    if ($pubKeys.Count -eq 0) {
        $tb          = New-Object System.Windows.Controls.TextBlock
        $tb.Text     = "No public keys found in ~/.ssh/"
        $tb.FontSize = 12
        $tb.Margin   = [System.Windows.Thickness]::new(2, 2, 0, 2)
        $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
        $sshKeyPanel.Children.Add($tb) | Out-Null
        return
    }

    $alt = $false
    foreach ($pub in $pubKeys) {
        $row = New-SSHKeyRow $pub.FullName $alt
        $sshKeyPanel.Children.Add($row) | Out-Null
        $alt = -not $alt
    }
}

# ── Generate panel defaults ───────────────────────────────────────
# Panel is always visible in two-column layout; set default values
(Find "SSHKeyComment").Text  = $env:USERNAME + "@" + $env:COMPUTERNAME
(Find "SSHKeyFilename").Text = "id_ed25519"

# ── Create key ────────────────────────────────────────────────────
(Find "BtnSSHCreate").Add_Click({
    $keyType  = ((Find "SSHKeyType").SelectedItem).Content
    $comment  = (Find "SSHKeyComment").Text.Trim()
    $filename = (Find "SSHKeyFilename").Text.Trim()

    if (-not $filename) {
        $sshGenerateStatus.Text = "Please enter a filename."
        $sshGenerateStatus.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "DangerBrush")
        return
    }

    if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
        $sshGenerateStatus.Text = "ssh-keygen not found. Install OpenSSH (Settings > Optional features)."
        $sshGenerateStatus.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "DangerBrush")
        return
    }

    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir | Out-Null
    }

    $outPath = Join-Path $sshDir $filename

    if (Test-Path $outPath) {
        $sshGenerateStatus.Text = "File already exists: $outPath"
        $sshGenerateStatus.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "DangerBrush")
        return
    }

    $sshGenerateStatus.Text = "Generating..."
    $sshGenerateStatus.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

    try {
        $sshArgs = @("-t", $keyType, "-C", $comment, "-f", $outPath, "-N", "")
        $result = & ssh-keygen @sshArgs 2>&1 | Out-String

        if (Test-Path "$outPath.pub") {
            $sshGenerateStatus.Text = "Key created: $outPath"
            $sshGenerateStatus.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "SuccessBrush")
            Populate-SSHKeys
        } else {
            $sshGenerateStatus.Text = "Generation failed: $result"
            $sshGenerateStatus.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "DangerBrush")
        }
    } catch {
        $sshGenerateStatus.Text = "Error: $_"
        $sshGenerateStatus.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "DangerBrush")
    }
})

# ── Refresh button ────────────────────────────────────────────────
(Find "BtnSSHRefresh").Add_Click({ Populate-SSHKeys })

# ── Load on startup ───────────────────────────────────────────────
Populate-SSHKeys
