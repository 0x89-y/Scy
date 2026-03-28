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
    $sizes = @(256, 48, 32, 16)
    $streams = @()
    foreach ($sz in $sizes) {
        $bmp = New-Object System.Drawing.Bitmap $sz, $sz
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode        = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint    = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.InterpolationMode    = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.CompositingQuality   = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.Clear([System.Drawing.Color]::Transparent)

        # Rounded-rectangle background path
        $radius = [math]::Max(2, [math]::Floor($sz * 0.20))
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc(0,           0,           $radius*2, $radius*2, 180, 90)
        $path.AddArc($sz-$radius*2, 0,           $radius*2, $radius*2, 270, 90)
        $path.AddArc($sz-$radius*2, $sz-$radius*2, $radius*2, $radius*2, 0,   90)
        $path.AddArc(0,           $sz-$radius*2, $radius*2, $radius*2, 90,  90)
        $path.CloseFigure()

        # Diagonal gradient: deep purple -> light purple (matches app AccentBrush #6c5ce7)
        # Use PointF overload to avoid ambiguity between (Rectangle,Color,Color,float) and (Rectangle,Color,Color,LinearGradientMode)
        $pt1 = New-Object System.Drawing.PointF([float]0, [float]0)
        $pt2 = New-Object System.Drawing.PointF([float]$sz, [float]$sz)
        $gradBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $pt1,
            $pt2,
            [System.Drawing.ColorTranslator]::FromHtml("#4834d4"),
            [System.Drawing.ColorTranslator]::FromHtml("#a29bfe")
        )
        $g.FillPath($gradBrush, $path)
        $gradBrush.Dispose()
        $path.Dispose()

        # White "S" centered
        $fontSize = [math]::Floor($sz * 0.60)
        $font   = New-Object System.Drawing.Font("Segoe UI", $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $sf     = New-Object System.Drawing.StringFormat
        $sf.Alignment     = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        $brush  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $rect   = New-Object System.Drawing.RectangleF(0, 0, $sz, $sz)
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
    # Per ICO spec: width/height byte of 0 means 256
    $fs = [System.IO.File]::Create($icoPath)
    $bw = New-Object System.IO.BinaryWriter($fs)
    $bw.Write([UInt16]0)
    $bw.Write([UInt16]1)
    $bw.Write([UInt16]$streams.Count)
    $offset = 6 + ($streams.Count * 16)
    foreach ($entry in $streams) {
        $bw.Write([byte]($entry.Size -band 0xFF))
        $bw.Write([byte]($entry.Size -band 0xFF))
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
    # Notify the shell to refresh the icon cache so the new icon shows immediately
    $shellCode = '[DllImport("Shell32.dll")] public static extern void SHChangeNotify(int e, int f, IntPtr a, IntPtr b);'
    Add-Type -MemberDefinition $shellCode -Name Shell32 -Namespace Win32 -ErrorAction SilentlyContinue
    [Win32.Shell32]::SHChangeNotify(0x8000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
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
