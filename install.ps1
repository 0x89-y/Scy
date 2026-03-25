# Scy Bootstrap Installer
# Usage: irm https://raw.githubusercontent.com/0x89-y/Scy/main/install.ps1 | iex

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$installDir = Join-Path $env:LOCALAPPDATA "Scy"
$zipUrl     = "https://github.com/0x89-y/Scy/archive/refs/heads/main.zip"
$zipPath    = Join-Path $env:TEMP "Scy-install.zip"
$extPath    = Join-Path $env:TEMP "Scy-install"

Write-Host ""
Write-Host "  Scy Installer" -ForegroundColor Cyan
Write-Host "  -----------------------------------" -ForegroundColor DarkGray
Write-Host ""

# Clean up any previous install artifacts
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
if (Test-Path $extPath) { Remove-Item $extPath -Recurse -Force }

# Download
Write-Host "  Downloading Scy..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 60
} catch {
    Write-Host "  Failed to download: $_" -ForegroundColor Red
    return
}

# Extract
Write-Host "  Extracting..." -ForegroundColor Yellow
Expand-Archive -Path $zipPath -DestinationPath $extPath -Force
$sourceDir = Join-Path $extPath "Scy-main"

# Create install directory if needed
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

# Copy files, preserving existing settings.json
Get-ChildItem -Path $sourceDir -Recurse -File | ForEach-Object {
    $relativePath = $_.FullName.Substring($sourceDir.Length + 1)
    if ($relativePath -eq "settings.json" -and (Test-Path (Join-Path $installDir "settings.json"))) { return }
    $destFile = Join-Path $installDir $relativePath
    $destDir  = Split-Path $destFile -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Copy-Item $_.FullName -Destination $destFile -Force
}

# Remove unnecessary files
Get-ChildItem -Path $installDir -File | Where-Object { $_.Name -match '^(LICENSE|README)' } | ForEach-Object {
    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
}

# Clean up temp files
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Remove-Item $extPath -Recurse -Force -ErrorAction SilentlyContinue

# Generate Scy.ico
Write-Host "  Creating icon..." -ForegroundColor Yellow
$icoPath = Join-Path $installDir "Scy.ico"
try {
    Add-Type -AssemblyName System.Drawing
    $sizes = @(32, 16)
    $streams = @()
    foreach ($sz in $sizes) {
        $bmp = New-Object System.Drawing.Bitmap $sz, $sz
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.Clear([System.Drawing.ColorTranslator]::FromHtml("#0a0a0f"))
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml("#004080"))
        $fontSize = [math]::Floor($sz * 0.65)
        $font = New-Object System.Drawing.Font("Segoe UI", $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        $rect = New-Object System.Drawing.RectangleF(0, 0, $sz, $sz)
        $g.DrawString("S", $font, $brush, $rect, $sf)
        $g.Dispose()
        $font.Dispose()
        $brush.Dispose()
        $sf.Dispose()
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $streams += @{ Size = $sz; Data = $ms.ToArray() }
        $ms.Dispose()
        $bmp.Dispose()
    }
    # Build .ico file (ICONDIR + ICONDIRENTRY[] + PNG data)
    $fs = [System.IO.File]::Create($icoPath)
    $bw = New-Object System.IO.BinaryWriter($fs)
    $bw.Write([UInt16]0)
    $bw.Write([UInt16]1)
    $bw.Write([UInt16]$streams.Count)
    $offset = 6 + ($streams.Count * 16)
    foreach ($entry in $streams) {
        $bw.Write([byte]$entry.Size)
        $bw.Write([byte]$entry.Size)
        $bw.Write([byte]0)
        $bw.Write([byte]0)
        $bw.Write([UInt16]1)
        $bw.Write([UInt16]32)
        $bw.Write([UInt32]$entry.Data.Length)
        $bw.Write([UInt32]$offset)
        $offset += $entry.Data.Length
    }
    foreach ($entry in $streams) {
        $bw.Write($entry.Data)
    }
    $bw.Close()
    $fs.Close()
} catch {
    Write-Host "  Icon creation failed (non-critical): $_" -ForegroundColor DarkGray
}

# Create Desktop shortcut
Write-Host "  Creating desktop shortcut..." -ForegroundColor Yellow
try {
    $wsh = New-Object -ComObject WScript.Shell
    $lnkPath = Join-Path $env:USERPROFILE "Desktop\Scy.lnk"
    $shortcut = $wsh.CreateShortcut($lnkPath)
    $shortcut.TargetPath = Join-Path $installDir "Scy.vbs"
    $shortcut.WorkingDirectory = $installDir
    if (Test-Path $icoPath) {
        $shortcut.IconLocation = "$icoPath,0"
    }
    $shortcut.Description = "Scy"
    $shortcut.Save()
    Write-Host "  Shortcut created on Desktop" -ForegroundColor Green
} catch {
    Write-Host "  Shortcut creation failed: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "  Installed to: $installDir" -ForegroundColor Green
Write-Host "  Launching Scy..." -ForegroundColor Cyan
Write-Host ""

# Launch Scy
$scyScript = Join-Path $installDir "Scy.ps1"
Start-Process powershell -ArgumentList @("-ExecutionPolicy", "Bypass", "-File", $scyScript)
