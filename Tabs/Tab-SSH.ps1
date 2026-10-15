# ── SSH Key Manager Tab ───────────────────────────────────────────

$sshKeyPanel       = Find "SSHKeyPanel"
$sshGenerateStatus = Find "SSHGenerateStatus"

$sshDir = Join-Path $env:USERPROFILE ".ssh"
$script:sshPreviewBlocks = @{}   # pub key path -> its preview TextBlock

# ── Build a row for one key pair ─────────────────────────────────
function New-SSHKeyRow {
    param([string]$PubKeyPath, [bool]$Alternate = $false)

    $keyName = [System.IO.Path]::GetFileNameWithoutExtension($PubKeyPath)
    $pubText = ""
    try { $pubText = (Get-Content $PubKeyPath -Raw -ErrorAction Stop).Trim() } catch {}

    $border            = New-Object System.Windows.Controls.Border
    $border.Background  = [System.Windows.Media.Brushes]::Transparent
    $border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
    $border.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
    $border.CornerRadius = [System.Windows.CornerRadius]::new(0)
    $border.Padding    = [System.Windows.Thickness]::new(4, 9, 4, 9)
    $border.Margin     = [System.Windows.Thickness]::new(0)

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

    # Truncated pub key for now; Populate-SSHKeys swaps in the fingerprint once
    # its background ssh-keygen job finishes.
    $previewTb.Text = if ($pubText) { $pubText.Substring(0, [Math]::Min(80, $pubText.Length)) + "..." } else { "(could not read key)" }
    $script:sshPreviewBlocks[$PubKeyPath] = $previewTb

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

    $script:sshPreviewBlocks = @{}
    $alt = $false
    foreach ($pub in $pubKeys) {
        $row = New-SSHKeyRow $pub.FullName $alt
        $sshKeyPanel.Children.Add($row) | Out-Null
        $alt = -not $alt
    }

    # Fingerprints: one ssh-keygen per key, all in a single background job
    $keygen = Get-Command ssh-keygen -ErrorAction SilentlyContinue
    if (-not $keygen) { return }
    Start-ScyJob `
        -Variables @{ paths = @($pubKeys | ForEach-Object { $_.FullName }); exe = $keygen.Source } `
        -Work {
            param($emit)
            $out = @{}
            foreach ($p in $paths) {
                $fp = & $exe -lf $p 2>$null
                if ($LASTEXITCODE -eq 0 -and $fp) { $out[$p] = [string]$fp }
            }
            return $out
        } `
        -OnComplete {
            param($fingerprints, $err, $ctx)
            if ($err -or -not $fingerprints) { return }
            foreach ($p in $fingerprints.Keys) {
                if ($script:sshPreviewBlocks.ContainsKey($p)) { $script:sshPreviewBlocks[$p].Text = $fingerprints[$p] }
            }
        } | Out-Null
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
        # Windows PowerShell 5.1 silently drops empty-string arguments to native
        # commands, so `-N ""` reached ssh-keygen as a bare -N and it bailed out.
        # Build the command line ourselves (MSVCRT quoting) so it works on 5.1 and 7.
        $quote = {
            param([string]$s)
            if ($s -eq '') { return '""' }
            if ($s -notmatch '[\s"]') { return $s }
            '"' + (($s -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
        }
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName  = (Get-Command ssh-keygen).Source
        $psi.Arguments = (@("-t", $keyType, "-C", $comment, "-f", $outPath, "-N", "") |
                          ForEach-Object { & $quote $_ }) -join ' '
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $psi.RedirectStandardInput  = $true   # never block on an interactive prompt
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardInput.Close()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $result = $proc.StandardOutput.ReadToEnd() + $stderrTask.Result
        $proc.WaitForExit()

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
# Deferred to first Network-tab visit (Invoke-ScyTabInit in Scy.ps1); key
# enumeration + fingerprinting is slow and not needed until the tab is shown.
