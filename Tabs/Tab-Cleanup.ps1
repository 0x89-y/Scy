# ── Cleanup Tab ──────────────────────────────────────────────────

$cleanTempRows    = Find "CleanTempRows"
$cleanTempStatus  = Find "CleanTempStatus"
$cleanTempTotal   = Find "CleanTempTotal"
$recycleBinStatus = Find "RecycleBinStatus"
$recycleBinResult = Find "RecycleBinResult"
$recycleBinSize   = Find "RecycleBinSize"
$btnClean         = Find "BtnClean"
$cleanupProgressBorder = Find "CleanupProgressBorder"
$cleanupProgressBar    = Find "CleanupProgressBar"
$cleanupProgressLabel  = Find "CleanupProgressLabel"

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

$btnScan = Find "BtnScan"
$btnScan.Add_Click({
    $statusIndicator.Text       = "● Scanning..."
    $statusIndicator.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#fdcb6e")
    $cleanTempStatus.Text       = "Scanning..."
    $cleanTempStatus.Foreground = $window.Resources["MutedText"]
    $btnScan.IsEnabled = $false

    $targets = Get-CleanTargets
    $totalTargets = $targets.Keys.Count
    Show-ScyProgress -Border $cleanupProgressBorder -Bar $cleanupProgressBar -Label $cleanupProgressLabel `
                     -Text "Starting scan..." -Value 0 -Max $totalTargets

    $onDone = {
        param($scanData, $err)
        $btnScan.IsEnabled = $true
        Hide-ScyProgress $cleanupProgressBorder $cleanupProgressBar

        if ($err) {
            $cleanTempStatus.Text       = "Scan failed: $err"
            $cleanTempStatus.Foreground = $window.Resources["DangerBrush"]
            $statusIndicator.Text       = "● Ready"
            $statusIndicator.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#00b894")
            return
        }

        $script:cleanScanData   = $scanData
        $script:cleanCheckboxes = @{}

        $cleanTempRows.Children.Clear()
        $i = 0
        foreach ($label in $scanData.Keys) {
            $cleanTempRows.Children.Add((New-PathRow $label $scanData[$label].SizeBytes ($i % 2 -eq 0) $true $true)) | Out-Null
            $i++
        }

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

        $statusIndicator.Text       = "● Ready"
        $statusIndicator.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#00b894")
    }

    $onLineCtx = {
        param($line, $ctx)
        if ($line -is [hashtable]) {
            $cleanupProgressBar.Value  = [double]$line.Index
            $cleanupProgressLabel.Text = "Scanning " + [string]$line.Index + " of " + [string]$ctx.Total + " - " + [string]$line.Label
            $cleanTempStatus.Text      = "Scanning " + [string]$line.Label + "..."
        } else {
            $cleanTempStatus.Text = [string]$line
        }
    }

    Start-ScyJob `
        -Variables @{ targets = $targets } `
        -Context   @{ Total = $totalTargets } `
        -Work {
            param($emit)
            function Get-DirSize {
                param([string]$Path)
                if (-not (Test-Path $Path)) { return 0L }
                $sum = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
                         Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($null -eq $sum) { return 0L }
                return [long]$sum
            }
            $scanData = [ordered]@{}
            $i = 0
            foreach ($label in $targets.Keys) {
                $i++
                & $emit @{ Index = $i; Label = $label }
                $t    = $targets[$label]
                $size = 0L
                foreach ($p in $t.Paths) { $size += Get-DirSize $p }
                $scanData[$label] = @{ Paths = $t.Paths; SizeBytes = $size; DeleteSelf = $t.DeleteSelf }
            }
            return $scanData
        } `
        -OnLine     $onLineCtx `
        -OnComplete $onDone | Out-Null
})

$btnClean.Add_Click({
    if ($null -eq $script:cleanScanData) { return }

    $selectedBytes = 0L
    foreach ($label in $script:cleanScanData.Keys) {
        $cb = $script:cleanCheckboxes[$label]
        if ($null -eq $cb -or $cb.IsChecked) { $selectedBytes += $script:cleanScanData[$label].SizeBytes }
    }

    $confirm = Show-ThemedDialog "This will free approximately $(Format-Size $selectedBytes). Proceed?" "Confirm cleanup" "YesNo" "Question"
    if ($confirm -ne "Yes") { return }

    # Warn if Windows.old is selected — deletion is irreversible
    $winOldCb = $script:cleanCheckboxes["Windows.old"]
    if (($null -eq $winOldCb -or $winOldCb.IsChecked) -and (Test-Path "C:\Windows.old")) {
        $warnOld = Show-ThemedDialog "Deleting Windows.old is permanent — you will no longer be able to roll back to your previous Windows installation. Are you sure?" "Warning: Irreversible" "YesNo" "Warning"
        if ($warnOld -ne "Yes") { return }
    }

    # Warn if Windows Update cache is selected and an update is in progress
    $wuCb = $script:cleanCheckboxes["Windows Update"]
    if ($null -eq $wuCb -or $wuCb.IsChecked) {
        $wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
        if ($wuService -and $wuService.Status -eq 'Running') {
            $warnWu = Show-ThemedDialog "Windows Update is currently running. Deleting its cache now may corrupt the active download. Proceed anyway?" "Warning" "YesNo" "Warning"
            if ($warnWu -ne "Yes") { return }
        }
    }

    $statusIndicator.Text       = "● Cleaning..."
    $statusIndicator.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#fdcb6e")
    $cleanTempStatus.Text       = "Cleaning..."
    $cleanTempStatus.Foreground = $window.Resources["MutedText"]
    $btnClean.IsEnabled = $false
    $btnScan.IsEnabled  = $false

    # Build worklist on UI thread (reads checkbox state, which is UI-bound)
    $worklist = @()
    $i = 0
    foreach ($label in $script:cleanScanData.Keys) {
        $cb    = $script:cleanCheckboxes[$label]
        $entry = $script:cleanScanData[$label]
        $worklist += @{
            Label      = $label
            Paths      = $entry.Paths
            DeleteSelf = $entry.DeleteSelf
            SizeBytes  = $entry.SizeBytes
            Alternate  = ($i % 2 -eq 0)
            Skip       = ($cb -and -not $cb.IsChecked)
        }
        $i++
    }

    $cleanTempRows.Children.Clear()

    $toCleanCount = @($worklist | Where-Object { -not $_.Skip }).Count
    Show-ScyProgress -Border $cleanupProgressBorder -Bar $cleanupProgressBar -Label $cleanupProgressLabel `
                     -Text "Starting cleanup..." -Value 0 -Max ([Math]::Max($toCleanCount, 1))

    $onLine = {
        param($line, $ctx)
        if ($line -is [hashtable]) {
            $cleanupProgressBar.Value  = [double]$line.Index
            $cleanupProgressLabel.Text = "Cleaning " + [string]$line.Index + " of " + [string]$ctx.Total + " - " + [string]$line.Label
            $cleanTempStatus.Text      = "Cleaning " + [string]$line.Label + "..."
        } else {
            $cleanTempStatus.Text = [string]$line
        }
    }

    $onDone = {
        param($result, $err)
        $btnScan.IsEnabled = $true
        Hide-ScyProgress $cleanupProgressBorder $cleanupProgressBar

        if ($err) {
            $cleanTempStatus.Text       = "Cleanup failed: $err"
            $cleanTempStatus.Foreground = $window.Resources["DangerBrush"]
            $statusIndicator.Text       = "● Ready"
            $statusIndicator.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#00b894")
            return
        }

        $totalFreed = 0L
        foreach ($item in $result) {
            if ($item.Skip) {
                $cleanTempRows.Children.Add((New-PathRow $item.Label 0L $item.Alternate $false $false)) | Out-Null
            } else {
                $totalFreed += $item.SizeBytes
                $cleanTempRows.Children.Add((New-PathRow $item.Label $item.SizeBytes $item.Alternate $false $false)) | Out-Null
            }
        }

        $cleanTempTotal.Text        = Format-Size $totalFreed
        $cleanTempTotal.Visibility  = "Visible"
        $cleanTempStatus.Text       = "Freed $(Format-Size $totalFreed)"
        $cleanTempStatus.Foreground = $window.Resources["SuccessBrush"]

        $btnClean.IsEnabled     = $false
        $btnClean.Opacity       = 0.4
        $script:cleanScanData   = $null
        $script:cleanCheckboxes = @{}

        $statusIndicator.Text       = "● Ready"
        $statusIndicator.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#00b894")
    }

    Start-ScyJob `
        -Variables @{ worklist = $worklist } `
        -Context   @{ Total = $toCleanCount } `
        -Work {
            param($emit)
            $i = 0
            foreach ($item in $worklist) {
                if ($item.Skip) { continue }
                $i++
                & $emit @{ Index = $i; Label = $item.Label }
                foreach ($p in $item.Paths) {
                    if (Test-Path $p) {
                        if ($item.DeleteSelf) {
                            Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
                        } else {
                            Remove-Item "$p\*" -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
            return $worklist
        } `
        -OnLine     $onLine `
        -OnComplete $onDone | Out-Null
})

$btnEmptyRecycleBin = Find "BtnEmptyRecycleBin"
$btnEmptyRecycleBin.Add_Click({
    $confirm = Show-ThemedDialog "Empty the Recycle Bin?" "Confirm" "YesNo" "Question"
    if ($confirm -ne "Yes") { return }

    $statusIndicator.Text       = "● Emptying..."
    $statusIndicator.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#fdcb6e")
    $recycleBinStatus.Text      = "Emptying..."
    $recycleBinStatus.Foreground = $window.Resources["MutedText"]
    $btnEmptyRecycleBin.IsEnabled = $false

    $onDone = {
        param($result, $err)
        $btnEmptyRecycleBin.IsEnabled = $true

        if ($err) {
            if ($err.Exception.Message -like "*cannot find the path*") {
                $recycleBinStatus.Text       = "Already empty"
                $recycleBinStatus.Foreground = $window.Resources["SuccessBrush"]
                $recycleBinResult.Text       = [char]0x2714
                $recycleBinResult.Foreground = $window.Resources["SuccessBrush"]
                $recycleBinSize.Text         = "0 B"
            } else {
                $recycleBinStatus.Text       = "Failed: $err"
                $recycleBinStatus.Foreground = $window.Resources["DangerBrush"]
                $recycleBinResult.Text       = [char]0x2716
                $recycleBinResult.Foreground = $window.Resources["DangerBrush"]
            }
        } else {
            $recycleBinStatus.Text       = "Emptied successfully"
            $recycleBinStatus.Foreground = $window.Resources["SuccessBrush"]
            $recycleBinResult.Text       = [char]0x2714
            $recycleBinResult.Foreground = $window.Resources["SuccessBrush"]
            $recycleBinSize.Text         = "0 B"
        }
        $recycleBinResult.Visibility = "Visible"

        $statusIndicator.Text       = "● Ready"
        $statusIndicator.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#00b894")
    }

    Start-ScyJob `
        -Work {
            param($emit)
            Clear-RecycleBin -Force -ErrorAction Stop
        } `
        -OnComplete $onDone | Out-Null
})
