# ── Cleanup Tab ──────────────────────────────────────────────────

$cleanTempRows    = Find "CleanTempRows"
$cleanTempStatus  = Find "CleanTempStatus"
$cleanTempTotal   = Find "CleanTempTotal"
$recycleBinStatus = Find "RecycleBinStatus"
$recycleBinResult = Find "RecycleBinResult"
$recycleBinSize   = Find "RecycleBinSize"
$btnClean         = Find "BtnClean"

$script:cleanScanData    = $null
$script:cleanCheckboxes  = @{}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N0} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Get-RecycleBinSize {
    $size = 0L
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $path = Join-Path $drive.Root '$Recycle.Bin'
        if (Test-Path $path) {
            $sum = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            if ($null -ne $sum) { $size += [long]$sum }
        }
    }
    return $size
}

function Update-RecycleBinSize {
    $size = Get-RecycleBinSize
    if ($size -gt 0) {
        $recycleBinSize.Text       = Format-Size $size
        $recycleBinSize.Visibility = "Visible"
    } else {
        $recycleBinSize.Text       = "Empty"
        $recycleBinSize.Visibility = "Visible"
    }
}

function Get-DirSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0L }
    $sum = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    if ($null -eq $sum) { return 0L }
    return [long]$sum
}

function Get-CleanTargets {
    $ffPaths = @()
    $ffBase  = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $ffBase) {
        $ffPaths = @(Get-ChildItem $ffBase -Directory -ErrorAction SilentlyContinue |
                     ForEach-Object { Join-Path $_.FullName "cache2" } |
                     Where-Object { Test-Path $_ })
    }
    [ordered]@{
        "%TEMP%"              = @{ Paths = @($env:TEMP);                                                   DeleteSelf = $false }
        "%LOCALAPPDATA%\Temp" = @{ Paths = @("$env:LOCALAPPDATA\Temp");                                    DeleteSelf = $false }
        "%WINDIR%\Temp"       = @{ Paths = @("$env:WINDIR\Temp");                                          DeleteSelf = $false }
        "Windows Update"      = @{ Paths = @("$env:WINDIR\SoftwareDistribution\Download");                 DeleteSelf = $false }
        "Prefetch"            = @{ Paths = @("$env:WINDIR\Prefetch");                                      DeleteSelf = $false }
        "Chrome Cache"        = @{ Paths = @("$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache");   DeleteSelf = $false }
        "Edge Cache"          = @{ Paths = @("$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache");  DeleteSelf = $false }
        "Firefox Cache"       = @{ Paths = $ffPaths;                                                       DeleteSelf = $true  }
        "Windows.old"         = @{ Paths = @("C:\Windows.old");                                            DeleteSelf = $true  }
    }
}

function Update-CleanTotal {
    if ($null -eq $script:cleanScanData) { return }
    $total = 0L
    foreach ($label in $script:cleanScanData.Keys) {
        $cb = $script:cleanCheckboxes[$label]
        if ($null -eq $cb -or $cb.IsChecked) {
            $total += $script:cleanScanData[$label].SizeBytes
        }
    }
    $cleanTempTotal.Text      = if ($total -gt 0) { Format-Size $total } else { "0 B" }
    $cleanTempStatus.Text     = "Found $(Format-Size $total) to free"
}

function New-PathRow {
    param([string]$Label, [long]$SizeBytes, [bool]$Alternate, [bool]$IsPreview, [bool]$ShowCheckbox = $false)

    $bgKey = if ($Alternate) { "Surface2Brush" } else { "SurfaceBrush" }

    $border              = New-Object System.Windows.Controls.Border
    $border.Background   = $window.Resources[$bgKey]
    $border.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $border.Padding      = [System.Windows.Thickness]::new(10, 7, 10, 7)
    $border.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 3)

    $grid = New-Object System.Windows.Controls.Grid

    $pathBlock              = New-Object System.Windows.Controls.TextBlock
    $pathBlock.Text         = $Label
    $pathBlock.FontSize     = 12
    $pathBlock.Foreground   = $window.Resources["MutedText"]
    $pathBlock.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $pathBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $sizeText  = if ($SizeBytes -gt 0) { Format-Size $SizeBytes } else { "—" }
    $sizeColorKey = if ($SizeBytes -gt 0) {
        if ($IsPreview) { "AccentBrush" } else { "FgBrush" }
    } else { "MutedText" }

    $sizeBlock            = New-Object System.Windows.Controls.TextBlock
    $sizeBlock.Text       = $sizeText
    $sizeBlock.FontSize   = 12
    $sizeBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
    $sizeBlock.Foreground = $window.Resources[$sizeColorKey]
    $sizeBlock.Margin     = [System.Windows.Thickness]::new(16, 0, 0, 0)
    $sizeBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    if ($ShowCheckbox) {
        $col0 = New-Object System.Windows.Controls.ColumnDefinition; $col0.Width = [System.Windows.GridLength]::Auto
        $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = [System.Windows.GridLength]::Auto
        $grid.ColumnDefinitions.Add($col0)
        $grid.ColumnDefinitions.Add($col1)
        $grid.ColumnDefinitions.Add($col2)

        $cb               = New-Object System.Windows.Controls.CheckBox
        $cb.IsChecked     = $true
        $cb.Style         = $window.Resources["CleanCheckBox"]
        $cb.Margin        = [System.Windows.Thickness]::new(0, 0, 10, 0)
        $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $cb.Add_Click({ Update-CleanTotal; Save-CleanTargetSelection })
        [System.Windows.Controls.Grid]::SetColumn($cb,        0)
        [System.Windows.Controls.Grid]::SetColumn($pathBlock, 1)
        [System.Windows.Controls.Grid]::SetColumn($sizeBlock, 2)
        $script:cleanCheckboxes[$Label] = $cb
        $grid.Children.Add($cb) | Out-Null
    } else {
        $col0 = New-Object System.Windows.Controls.ColumnDefinition; $col0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = [System.Windows.GridLength]::Auto
        $grid.ColumnDefinitions.Add($col0)
        $grid.ColumnDefinitions.Add($col1)
        [System.Windows.Controls.Grid]::SetColumn($pathBlock, 0)
        [System.Windows.Controls.Grid]::SetColumn($sizeBlock, 1)
    }

    $grid.Children.Add($pathBlock) | Out-Null
    $grid.Children.Add($sizeBlock) | Out-Null
    $border.Child = $grid
    return $border
}

function Save-CleanTargetSelection {
    if (-not $script:rememberCleanTargets) { return }
    $sel = @{}
    foreach ($label in $script:cleanCheckboxes.Keys) {
        $sel[$label] = [bool]$script:cleanCheckboxes[$label].IsChecked
    }
    $script:cleanTargetSelection = $sel
    Save-Settings
}

Update-RecycleBinSize

(Find "BtnScan").Add_Click({
    $statusIndicator.Text = "● Scanning..."
    $statusIndicator.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#fdcb6e")
    $cleanTempStatus.Text       = "Scanning..."
    $cleanTempStatus.Foreground = $window.Resources["MutedText"]
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

    $targets  = Get-CleanTargets
    $scanData = [ordered]@{}
    foreach ($label in $targets.Keys) {
        $t    = $targets[$label]
        $size = 0L
        foreach ($p in $t.Paths) { $size += Get-DirSize $p }
        $scanData[$label] = @{ Paths = $t.Paths; SizeBytes = $size; DeleteSelf = $t.DeleteSelf }
    }

    $script:cleanScanData   = $scanData
    $script:cleanCheckboxes = @{}

    $cleanTempRows.Children.Clear()
    $i = 0
    foreach ($label in $scanData.Keys) {
        $cleanTempRows.Children.Add((New-PathRow $label $scanData[$label].SizeBytes ($i % 2 -eq 0) $true $true)) | Out-Null
        $i++
    }

    # Restore saved checkbox states if remember is enabled
    if ($script:rememberCleanTargets -and $script:cleanTargetSelection.Count -gt 0) {
        foreach ($label in $script:cleanCheckboxes.Keys) {
            if ($script:cleanTargetSelection.ContainsKey($label)) {
                $script:cleanCheckboxes[$label].IsChecked = $script:cleanTargetSelection[$label]
            }
        }
    }

    $cleanTempTotal.Visibility = "Visible"
    Update-CleanTotal

    $btnClean.IsEnabled = $true
    $btnClean.Opacity   = 1.0

    $statusIndicator.Text = "● Ready"
    $statusIndicator.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#00b894")
})

(Find "BtnClean").Add_Click({
    if ($null -eq $script:cleanScanData) { return }

    $selectedBytes = 0L
    foreach ($label in $script:cleanScanData.Keys) {
        $cb = $script:cleanCheckboxes[$label]
        if ($null -eq $cb -or $cb.IsChecked) { $selectedBytes += $script:cleanScanData[$label].SizeBytes }
    }

    $confirm = Show-ThemedDialog "This will free approximately $(Format-Size $selectedBytes). Proceed?" "Confirm cleanup" "YesNo" "Question"
    if ($confirm -ne "Yes") { return }

    $statusIndicator.Text = "● Cleaning..."
    $statusIndicator.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#fdcb6e")
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

    $cleanTempRows.Children.Clear()
    $totalFreed = 0L
    $i = 0

    foreach ($label in $script:cleanScanData.Keys) {
        $cb    = $script:cleanCheckboxes[$label]
        $entry = $script:cleanScanData[$label]

        if ($cb -and -not $cb.IsChecked) {
            # Skipped — show row as skipped (muted, no size)
            $cleanTempRows.Children.Add((New-PathRow $label 0L ($i % 2 -eq 0) $false $false)) | Out-Null
            $i++
            continue
        }

        foreach ($p in $entry.Paths) {
            if (Test-Path $p) {
                if ($entry.DeleteSelf) {
                    Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
                } else {
                    Remove-Item "$p\*" -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        $totalFreed += $entry.SizeBytes
        $cleanTempRows.Children.Add((New-PathRow $label $entry.SizeBytes ($i % 2 -eq 0) $false $false)) | Out-Null
        $i++
    }

    $cleanTempTotal.Text        = Format-Size $totalFreed
    $cleanTempTotal.Visibility  = "Visible"
    $cleanTempStatus.Text       = "Freed $(Format-Size $totalFreed)"
    $cleanTempStatus.Foreground = $window.Resources["SuccessBrush"]

    $btnClean.IsEnabled = $false
    $btnClean.Opacity   = 0.4
    $script:cleanScanData   = $null
    $script:cleanCheckboxes = @{}

    $statusIndicator.Text = "● Ready"
    $statusIndicator.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#00b894")
})

(Find "BtnEmptyRecycleBin").Add_Click({
    $confirm = Show-ThemedDialog "Empty the Recycle Bin?" "Confirm" "YesNo" "Question"
    if ($confirm -ne "Yes") { return }

    $statusIndicator.Text = "● Emptying..."
    $statusIndicator.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#fdcb6e")
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        $recycleBinStatus.Text       = "Emptied successfully"
        $recycleBinStatus.Foreground = $window.Resources["SuccessBrush"]
        $recycleBinResult.Text       = [char]0x2714
        $recycleBinResult.Foreground = $window.Resources["SuccessBrush"]
        $recycleBinSize.Text         = "0 B"
    } catch {
        if ($_.Exception.Message -like "*cannot find the path*") {
            $recycleBinStatus.Text       = "Already empty"
            $recycleBinStatus.Foreground = $window.Resources["SuccessBrush"]
            $recycleBinResult.Text       = [char]0x2714
            $recycleBinResult.Foreground = $window.Resources["SuccessBrush"]
            $recycleBinSize.Text         = "0 B"
        } else {
            $recycleBinStatus.Text       = "Failed: $_"
            $recycleBinStatus.Foreground = $window.Resources["DangerBrush"]
            $recycleBinResult.Text       = [char]0x2716
            $recycleBinResult.Foreground = $window.Resources["DangerBrush"]
        }
    }
    $recycleBinResult.Visibility = "Visible"

    $statusIndicator.Text = "● Ready"
    $statusIndicator.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#00b894")
})
