# Scy Bootstrap Installer
# Usage: irm https://raw.githubusercontent.com/0x89-y/Scy/main/install.ps1 | iex

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$installDir = Join-Path $env:LOCALAPPDATA "Scy"
$zipUrl     = "https://github.com/0x89-y/Scy/archive/refs/heads/main.zip"
$zipPath    = Join-Path $env:TEMP "Scy-install.zip"
$extPath    = Join-Path $env:TEMP "Scy-install"

Write-Host ""
Write-Host "  Scy Installer" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────" -ForegroundColor DarkGray
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

Write-Host ""
Write-Host "  Installed to: $installDir" -ForegroundColor Green
Write-Host "  Launching Scy..." -ForegroundColor Cyan
Write-Host ""

# Launch Scy
Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$(Join-Path $installDir 'Scy.ps1')`""
