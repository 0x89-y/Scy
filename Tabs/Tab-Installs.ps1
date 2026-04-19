# -- Installs Tab -------------------------------------------------------------

$installSearchBox          = Find "InstallSearchBox"
$searchPlaceholder         = Find "SearchPlaceholder"
$searchResultsBorder       = Find "SearchResultsBorder"
$searchResultsPanel        = Find "SearchResultsPanel"
$searchResultsLabel        = Find "SearchResultsLabel"
$btnInstallSelected        = Find "BtnInstallSelected"
$btnAddToQuickInstalls     = Find "BtnAddToQuickInstalls"
$quickInstallCategoryBox   = Find "QuickInstallCategoryBox"
$btnAddToBundle            = Find "BtnAddToBundle"
$btnImportBundles          = Find "BtnImportBundles"
$btnExportBundles          = Find "BtnExportBundles"
$searchStatus              = Find "SearchStatus"
$installedCard             = Find "InstalledCard"
$installedPanel            = Find "InstalledPanel"
$installedCountLabel       = Find "InstalledCountLabel"
$installedFilterBox        = Find "InstalledFilterBox"
$installedFilterPlaceholder = Find "InstalledFilterPlaceholder"
$installedFilterClear      = Find "InstalledFilterClear"
$installsProgressBorder    = Find "InstallsProgressBorder"
$installsProgressBar       = Find "InstallsProgressBar"
$installsProgressLabel     = Find "InstallsProgressLabel"

# Tracks search result rows for checkbox harvesting
$script:searchItems    = [System.Collections.Generic.List[hashtable]]::new()
# Tracks installed rows for live filter
$script:installedItems = [System.Collections.Generic.List[hashtable]]::new()
# Re-entry guards for async winget operations
$script:searchInProgress  = $false
$script:installInProgress = $false

# -- Search box placeholder behaviour -----------------------------------------
$installSearchClear = Find "InstallSearchClear"
$installSearchBox.Add_GotFocus({  $searchPlaceholder.Visibility = "Collapsed" })
$installSearchBox.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($installSearchBox.Text)) {
        $searchPlaceholder.Visibility = "Visible"
    }
})
$installSearchBox.Add_TextChanged({
    $installSearchClear.Visibility = if ($installSearchBox.Text.Length -gt 0) { "Visible" } else { "Collapsed" }
})
$installSearchClear.Add_Click({
    $installSearchBox.Text = ""
    $searchPlaceholder.Visibility = "Visible"
    $installSearchClear.Visibility = "Collapsed"
})
$installSearchBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return) { Search-WingetPackages }
})

# -- Filter box placeholder behaviour -----------------------------------------
$installedFilterBox.Add_GotFocus({  $installedFilterPlaceholder.Visibility = "Collapsed" })
$installedFilterBox.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($installedFilterBox.Text)) {
        $installedFilterPlaceholder.Visibility = "Visible"
    }
})
$installedFilterBox.Add_TextChanged({
    $q = $installedFilterBox.Text.ToLower()
    $installedFilterClear.Visibility = if ($q) { "Visible" } else { "Collapsed" }
    foreach ($item in $script:installedItems) {
        $item.Border.Visibility = if ($q -eq '' -or $item.Tag.Contains($q)) { "Visible" } else { "Collapsed" }
    }
})
$installedFilterClear.Add_Click({
    $installedFilterBox.Text = ""
    $installedFilterBox.Focus()
})

# -- Package sub-navigation ---------------------------------------------------
$pkgNavUpdates   = Find "PkgNav_Updates"
$pkgNavSearch    = Find "PkgNav_Search"
$pkgNavQuick     = Find "PkgNav_Quick"
$pkgNavLocal     = Find "PkgNav_Local"
$pkgNavUninstall = Find "PkgNav_Uninstall"

$pkgSectionUpdates   = Find "PkgSection_Updates"
$pkgSectionSearch    = Find "PkgSection_Search"
$pkgSectionQuick     = Find "PkgSection_Quick"
$pkgSectionLocal     = Find "PkgSection_Local"
$pkgSectionUninstall = Find "PkgSection_Uninstall"

$script:pkgNavButtons  = @($pkgNavUpdates, $pkgNavSearch, $pkgNavQuick, $pkgNavLocal, $pkgNavUninstall)
$script:pkgSections    = @($pkgSectionUpdates, $pkgSectionSearch, $pkgSectionQuick, $pkgSectionLocal, $pkgSectionUninstall)

function Set-PkgSubNav {
    param([int]$Index)
    $script:pkgSubNavIndex = $Index
    for ($i = 0; $i -lt $script:pkgSections.Count; $i++) {
        $script:pkgSections[$i].Visibility = if ($i -eq $Index) { "Visible" } else { "Collapsed" }
        $btn = $script:pkgNavButtons[$i]
        if ($i -eq $Index) {
            $btn.Foreground = $window.Resources["FgBrush"]
            $btn.BorderBrush = $window.Resources["AccentBrush"]
        } else {
            $btn.Foreground = $window.Resources["MutedText"]
            $btn.BorderBrush = $window.Resources["BorderBrush"]
        }
    }
}

# Set default to Updates
Set-PkgSubNav 0

$pkgNavUpdates.Add_Click({   Set-PkgSubNav 0 })
$pkgNavSearch.Add_Click({    Set-PkgSubNav 1 })
$pkgNavQuick.Add_Click({     Set-PkgSubNav 2 })
$pkgNavLocal.Add_Click({     Set-PkgSubNav 3 })
$pkgNavUninstall.Add_Click({ Set-PkgSubNav 4 })

# -- Helper: parse winget tabular output --------------------------------------
# Outputs one string[] per data row to the pipeline; callers use @(Get-WingetRows ...)
function Get-WingetRows {
    param([string[]]$Lines)

    # Strip ANSI escape codes and carriage returns that winget may emit
    $clean = @($Lines | ForEach-Object { ($_ -replace '\x1B\[[0-9;]*[mK]', '') -replace '\r', '' })

    # Find the separator line (one continuous block of dashes, at least 10 wide)
    $sepIdx = -1
    for ($i = 0; $i -lt $clean.Count; $i++) {
        if ($clean[$i] -match '^-{10,}\s*$') { $sepIdx = $i; break }
    }
    if ($sepIdx -lt 1) { return }

    # Derive column start positions from the HEADER line (line before the separator)
    $header    = $clean[$sepIdx - 1]
    $colStarts = @(0)
    for ($i = 1; $i -lt $header.Length; $i++) {
        if ($header[$i] -ne ' ' -and $header[$i - 1] -eq ' ') { $colStarts += $i }
    }

    # Slice each data row at the column positions and output to pipeline
    for ($r = $sepIdx + 1; $r -lt $clean.Count; $r++) {
        $line = $clean[$r]
        if ($line.Trim().Length -lt 2) { continue }
        $vals = @()
        for ($ci = 0; $ci -lt $colStarts.Count; $ci++) {
            $cs = $colStarts[$ci]
            if ($cs -ge $line.Length) { $vals += ''; continue }
            $ce = if ($ci + 1 -lt $colStarts.Count) { $colStarts[$ci + 1] } else { $line.Length }
            $ce = [Math]::Min($ce, $line.Length)
            $vals += $line.Substring($cs, $ce - $cs).TrimEnd()
        }
        ,$vals  # output this row's string[] to the pipeline
    }
}

# -- Helper: status helpers ---------------------------------------------------
function Set-BusyStatus {
    param([string]$Text)
    $statusIndicator.Text       = $Text
    $statusIndicator.Foreground = $window.Resources["WarningBrush"]
    $footerStatus.Text          = "Scy - " + $Text
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Set-ReadyStatus {
    $statusIndicator.Text       = "Ready"
    $statusIndicator.Foreground = $window.Resources["SuccessBrush"]
    $footerStatus.Text          = "Ready"
}

# -- Helper: update Install Selected button state -----------------------------
function Update-InstallSelectedState {
    $any = $false
    foreach ($item in $script:searchItems) {
        if ($item.CheckBox.IsChecked) { $any = $true; break }
    }
    $btnInstallSelected.IsEnabled      = $any
    $btnAddToQuickInstalls.IsEnabled   = $any
    $btnAddToBundle.IsEnabled          = $any
}

# -- Helper: create a search result row (with checkbox) -----------------------
function New-SearchRow {
    param([string]$Name, [string]$Id, [string]$Version, [bool]$Alternate)

    $border  = New-Object System.Windows.Controls.Border
    $border.Background   = if ($Alternate) { $window.Resources["SurfaceBrush"] } else { $window.Resources["InputBgBrush"] }
    $border.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $border.Padding      = [System.Windows.Thickness]::new(10, 6, 10, 6)
    $border.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 2)
    $border.Cursor       = [System.Windows.Input.Cursors]::Hand

    $grid = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::Auto
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::Auto
    $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = [System.Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1)
    $grid.ColumnDefinitions.Add($c2); $grid.ColumnDefinitions.Add($c3)

    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Margin            = [System.Windows.Thickness]::new(0, 0, 12, 0)
    $cb.VerticalAlignment = "Center"
    $cb.Add_Checked({   Update-InstallSelectedState })
    $cb.Add_Unchecked({ Update-InstallSelectedState })
    [System.Windows.Controls.Grid]::SetColumn($cb, 0)

    $nameBlock = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text              = $Name
    $nameBlock.Foreground        = $window.Resources["FgBrush"]
    $nameBlock.FontSize          = 12
    $nameBlock.VerticalAlignment = "Center"
    $nameBlock.TextWrapping      = "NoWrap"
    $nameBlock.TextTrimming      = "CharacterEllipsis"
    [System.Windows.Controls.Grid]::SetColumn($nameBlock, 1)

    $idBlock = New-Object System.Windows.Controls.TextBlock
    $idBlock.Text              = $Id
    $idBlock.Foreground        = $window.Resources["MutedText"]
    $idBlock.FontSize          = 11
    $idBlock.Margin            = [System.Windows.Thickness]::new(12, 0, 16, 0)
    $idBlock.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($idBlock, 2)

    $verBlock = New-Object System.Windows.Controls.TextBlock
    $verBlock.Text              = $Version
    $verBlock.Foreground        = $window.Resources["SubTextBrush"]
    $verBlock.FontSize          = 11
    $verBlock.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($verBlock, 3)

    $grid.Children.Add($cb)        | Out-Null
    $grid.Children.Add($nameBlock) | Out-Null
    $grid.Children.Add($idBlock)   | Out-Null
    $grid.Children.Add($verBlock)  | Out-Null
    $border.Child = $grid

    # Click border to toggle checkbox
    $border.Add_MouseLeftButtonUp(({ $cb.IsChecked = -not $cb.IsChecked }.GetNewClosure()))

    return @{ Border = $border; CheckBox = $cb; Name = $Name; Id = $Id }
}

# -- Helper: create an installed package row (read-only) ----------------------
function New-InstalledRow {
    param([string]$Name, [string]$Id, [string]$Version, [bool]$Alternate)

    $border = New-Object System.Windows.Controls.Border
    $border.Background   = if ($Alternate) { $window.Resources["SurfaceBrush"] } else { $window.Resources["InputBgBrush"] }
    $border.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $border.Padding      = [System.Windows.Thickness]::new(10, 6, 10, 6)
    $border.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 2)

    $grid = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::Auto
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1); $grid.ColumnDefinitions.Add($c2)

    $nameBlock = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text              = $Name
    $nameBlock.Foreground        = $window.Resources["FgBrush"]
    $nameBlock.FontSize          = 12
    $nameBlock.VerticalAlignment = "Center"
    $nameBlock.TextWrapping      = "NoWrap"
    $nameBlock.TextTrimming      = "CharacterEllipsis"
    [System.Windows.Controls.Grid]::SetColumn($nameBlock, 0)

    $idBlock = New-Object System.Windows.Controls.TextBlock
    $idBlock.Text              = $Id
    $idBlock.Foreground        = $window.Resources["MutedText"]
    $idBlock.FontSize          = 11
    $idBlock.Margin            = [System.Windows.Thickness]::new(12, 0, 20, 0)
    $idBlock.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($idBlock, 1)

    $verBlock = New-Object System.Windows.Controls.TextBlock
    $verBlock.Text              = $Version
    $verBlock.Foreground        = $window.Resources["SuccessBrush"]
    $verBlock.FontSize          = 11
    $verBlock.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($verBlock, 2)

    $grid.Children.Add($nameBlock) | Out-Null
    $grid.Children.Add($idBlock)   | Out-Null
    $grid.Children.Add($verBlock)  | Out-Null
    $border.Child = $grid

    $tag = ($Name + " " + $Id).ToLower()
    return @{ Border = $border; Tag = $tag }
}

# -- Search winget packages ---------------------------------------------------
function Search-WingetPackages {
    if ($script:searchInProgress) { return }
    $query = $installSearchBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($query)) { return }

    $script:searchInProgress         = $true
    $searchStatus.Text               = "Searching for '" + $query + "'..."
    $searchResultsBorder.Visibility  = "Collapsed"
    $searchResultsPanel.Children.Clear()
    $script:searchItems.Clear()
    $btnInstallSelected.IsEnabled    = $false
    $btnAddToQuickInstalls.IsEnabled = $false
    $btnAddToBundle.IsEnabled        = $false

    Start-ScyJob `
        -Variables @{ q = $query } `
        -Context   @{ Query = $query } `
        -Work {
            param($emit)
            $raw = & winget search $q --accept-source-agreements 2>&1
            return @{ Lines = @($raw | ForEach-Object { [string]$_ }) }
        } `
        -OnComplete {
            param($result, $err, $ctx)
            $script:searchInProgress = $false
            if ($err) {
                $searchStatus.Text = "Search failed: " + $err.Exception.Message
                return
            }
            $rows = @(Get-WingetRows $result.Lines)
            if ($rows.Count -eq 0) {
                $searchStatus.Text = "No results found for '" + $ctx.Query + "'."
                return
            }
            $alt = $false
            foreach ($row in $rows) {
                $name    = if ($row.Count -gt 0) { $row[0] } else { "" }
                $id      = if ($row.Count -gt 1) { $row[1] } else { "" }
                $version = if ($row.Count -gt 2) { $row[2] } else { "" }
                if ([string]::IsNullOrWhiteSpace($id)) { continue }

                $item = New-SearchRow $name $id $version $alt
                $searchResultsPanel.Children.Add($item.Border) | Out-Null
                $script:searchItems.Add($item)
                $alt = -not $alt
            }
            $count = $script:searchItems.Count
            $searchResultsLabel.Text        = [string]$count + " packages found"
            $searchResultsBorder.Visibility = "Visible"
            $searchStatus.Text              = ""
        } | Out-Null
}

# -- Install selected from search results -------------------------------------
(Find "BtnInstallSelected").Add_Click({
    if ($script:installInProgress) { return }
    $toInstall = @($script:searchItems | Where-Object { $_.CheckBox.IsChecked } | ForEach-Object { $_.Id })
    if ($toInstall.Count -eq 0) { return }

    $script:installInProgress     = $true
    $btnInstallSelected.IsEnabled = $false
    $total = $toInstall.Count
    Set-BusyStatus ("Installing " + [string]$total + " package(s)...")
    Show-ScyProgress -Border $installsProgressBorder -Bar $installsProgressBar -Label $installsProgressLabel `
                     -Text ("Starting install of " + [string]$total + " package(s)...") -Value 0 -Max $total

    Start-ScyJob `
        -Variables @{ pkgs = $toInstall } `
        -Context   @{ Total = $total } `
        -Work {
            param($emit)
            $failed = @()
            $i = 0
            foreach ($pkg in $pkgs) {
                $i++
                & $emit @{ Index = $i; Name = $pkg }
                & winget install --id $pkg --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { $failed += $pkg }
            }
            return @{ Failed = $failed; Total = $pkgs.Count }
        } `
        -OnLine {
            param($line, $ctx)
            if ($line -is [hashtable]) {
                $installsProgressBar.Value   = [double]$line.Index
                $installsProgressLabel.Text  = "Installing " + [string]$line.Index + " of " + [string]$ctx.Total + " - " + [string]$line.Name
                $footerStatus.Text           = "Scy - Installing: " + [string]$line.Name
            } else {
                $footerStatus.Text = "Scy - Installing: " + [string]$line
            }
        } `
        -OnComplete {
            param($result, $err, $ctx)
            $script:installInProgress     = $false
            $btnInstallSelected.IsEnabled = $true
            Hide-ScyProgress $installsProgressBorder $installsProgressBar
            Set-ReadyStatus
            if ($err) {
                Show-ThemedDialog ("Install error: " + $err.Exception.Message) "Error" "OK" "Error"
                return
            }
            if ($result.Failed.Count -gt 0) {
                Show-ThemedDialog ("Done. Failed packages:`n" + ($result.Failed -join "`n")) "Result" "OK" "Warning"
            } else {
                Show-ThemedDialog ("Installed " + [string]$result.Total + " package(s) successfully.") "Done" "OK" "Information"
            }
        } | Out-Null
})

# -- Search button click ------------------------------------------------------
(Find "BtnSearchPackage").Add_Click({ Search-WingetPackages })

# -- Quick Install (dynamic, persisted in settings) ---------------------------
$script:quickInstalls      = [System.Collections.Generic.List[hashtable]]::new()
$script:quickBundles       = [System.Collections.Generic.List[hashtable]]::new()
$script:selectedQuickItems = [System.Collections.Generic.List[hashtable]]::new()

$script:quickInstallEditMode = $false

$script:defaultQuickCategories = @("Development", "Communication", "Media", "Utilities", "Gaming", "Productivity", "Security", "Browsers")

function Get-AllQuickCategories {
    $custom = @($script:quickInstalls | ForEach-Object { $_.Category } | Where-Object { $_ } | Select-Object -Unique)
    $all = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($c in $script:defaultQuickCategories) {
        if ($c -notin $script:hiddenDefaultInstallCategories) { $all.Add($c) | Out-Null }
    }
    foreach ($c in $script:customInstallCategories) { $all.Add($c) | Out-Null }
    foreach ($c in $custom) { $all.Add($c) | Out-Null }
    return @($all | Sort-Object)
}

function Refresh-QuickInstallCategories {
    $quickInstallCategoryBox.Items.Clear()
    foreach ($c in (Get-AllQuickCategories)) { $quickInstallCategoryBox.Items.Add($c) | Out-Null }
    $quickInstallCategoryBox.Items.Add("+ New group...") | Out-Null
}

$quickInstallCategoryBox.Add_SelectionChanged({
    if ($this.SelectedItem -eq "+ New group...") {
        Ensure-VisualBasic; $gName = [Microsoft.VisualBasic.Interaction]::InputBox("Category name:", "New Category", "")
        if (-not [string]::IsNullOrWhiteSpace($gName)) {
            $gName = $gName.Trim()
            if ($gName -notin (Get-AllQuickCategories)) {
                $script:customInstallCategories.Add($gName)
                Save-Settings
                if ((Get-Command Render-GroupSettings -ErrorAction SilentlyContinue)) { Render-GroupSettings }
            }
            Refresh-QuickInstallCategories
            $quickInstallCategoryBox.Text = $gName
        } else {
            $this.SelectedIndex = -1
            $this.Text = ""
        }
    }
})

function Update-QuickInstallSelectedState {
    $installBtn = Find "BtnQuickInstallSelected"
    $count = $script:selectedQuickItems.Count
    $installBtn.IsEnabled = ($count -gt 0)
    $installBtn.Content   = if ($count -gt 0) { "Install ($count)" } else { "Install" }
}

function Show-QuickInstallConfirmDialog {
    $dlgAppBg   = "#{0:X2}{1:X2}{2:X2}" -f $window.Resources["AppBgBrush"].Color.R,  $window.Resources["AppBgBrush"].Color.G,  $window.Resources["AppBgBrush"].Color.B
    $dlgFg      = "#{0:X2}{1:X2}{2:X2}" -f $window.Resources["FgBrush"].Color.R,      $window.Resources["FgBrush"].Color.G,      $window.Resources["FgBrush"].Color.B
    $dlgSurface = "#{0:X2}{1:X2}{2:X2}" -f $window.Resources["SurfaceBrush"].Color.R, $window.Resources["SurfaceBrush"].Color.G, $window.Resources["SurfaceBrush"].Color.B
    $dlgBorder  = "#{0:X2}{1:X2}{2:X2}" -f $window.Resources["BorderBrush"].Color.R,  $window.Resources["BorderBrush"].Color.G,  $window.Resources["BorderBrush"].Color.B
    $dlgMuted   = "#{0:X2}{1:X2}{2:X2}" -f $window.Resources["MutedText"].Color.R,    $window.Resources["MutedText"].Color.G,    $window.Resources["MutedText"].Color.B
    $dlgAccent  = "#{0:X2}{1:X2}{2:X2}" -f $window.Resources["AccentBrush"].Color.R,  $window.Resources["AccentBrush"].Color.G,  $window.Resources["AccentBrush"].Color.B
    $dlgXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="480" Height="500"
        WindowStartupLocation="CenterOwner"
        ResizeMode="NoResize"
        Background="$dlgAppBg"
        FontFamily="Segoe UI"
        ShowInTaskbar="False">
    <Grid Margin="24">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock x:Name="DlgTitle" Grid.Row="0" FontSize="14" FontWeight="SemiBold"
                   Foreground="$dlgFg" Margin="0,0,0,14"/>
        <Border Grid.Row="1" Background="$dlgSurface" CornerRadius="4"
                BorderBrush="$dlgBorder" BorderThickness="1">
            <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="10">
                <StackPanel x:Name="DlgPackageList"/>
            </ScrollViewer>
        </Border>
        <TextBlock x:Name="DlgTotal" Grid.Row="2" FontSize="11" Foreground="$dlgMuted"
                   Margin="0,8,0,12" HorizontalAlignment="Right"/>
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="DlgCancelBtn" Content="Cancel"
                    Background="$dlgBorder" Foreground="$dlgFg" BorderThickness="0"
                    Padding="14,8" FontSize="11" Cursor="Hand" Margin="0,0,8,0"/>
            <Button x:Name="DlgInstallBtn" Content="Install All"
                    Background="$dlgAccent" Foreground="#ffffff" BorderThickness="0"
                    Padding="14,8" FontSize="11" Cursor="Hand" FontWeight="SemiBold"/>
        </StackPanel>
    </Grid>
</Window>
"@

    $dlg       = [Windows.Markup.XamlReader]::Parse($dlgXaml)
    $dlg.Owner = $window
    $dlg.Title = "Review installation"

    $listPanel = $dlg.FindName("DlgPackageList")

    # Collect all unique packages for installation, build display rows
    $allPackages   = [System.Collections.Generic.List[hashtable]]::new()
    $seenIds       = [System.Collections.Generic.HashSet[string]]::new()

    $indApps = @($script:selectedQuickItems | Where-Object { $_.Type -eq "App" })
    $bundles  = @($script:selectedQuickItems | Where-Object { $_.Type -eq "Bundle" })

    function Add-SectionHeader($text) {
        $hdr            = New-Object System.Windows.Controls.TextBlock
        $hdr.Text       = $text
        $hdr.Foreground = $window.Resources["MutedText"]
        $hdr.FontSize   = 10
        $hdr.FontWeight = "SemiBold"
        $hdr.Margin     = [System.Windows.Thickness]::new(0, 0, 0, 4)
        $listPanel.Children.Add($hdr) | Out-Null
    }

    function Add-PkgRow($name, $id, $indent) {
        $row = New-Object System.Windows.Controls.Grid
        $rc0 = New-Object System.Windows.Controls.ColumnDefinition; $rc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $rc1 = New-Object System.Windows.Controls.ColumnDefinition; $rc1.Width = [System.Windows.GridLength]::Auto
        $row.ColumnDefinitions.Add($rc0); $row.ColumnDefinitions.Add($rc1)
        $row.Margin = [System.Windows.Thickness]::new($indent, 0, 0, 3)

        $nb = New-Object System.Windows.Controls.TextBlock
        $nb.Text = $name; $nb.FontSize = 11
        $nb.Foreground = $window.Resources["FgBrush"]
        $nb.VerticalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetColumn($nb, 0)

        $ib = New-Object System.Windows.Controls.TextBlock
        $ib.Text = $id; $ib.FontSize = 10
        $ib.Foreground = $window.Resources["MutedText"]
        $ib.VerticalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetColumn($ib, 1)

        $row.Children.Add($nb) | Out-Null
        $row.Children.Add($ib) | Out-Null
        $listPanel.Children.Add($row) | Out-Null
    }

    if ($indApps.Count -gt 0) {
        Add-SectionHeader ("Apps (" + [string]$indApps.Count + ")")
        foreach ($item in $indApps) {
            Add-PkgRow $item.Name $item.Id 0
            if ($seenIds.Add($item.Id)) { $allPackages.Add(@{Name=$item.Name; Id=$item.Id}) }
        }
    }

    foreach ($item in $bundles) {
        $b = $item.Bundle
        if ($indApps.Count -gt 0 -or ($bundles.IndexOf($item) -gt 0)) {
            $spacer        = New-Object System.Windows.Controls.Border
            $spacer.Height = 8
            $listPanel.Children.Add($spacer) | Out-Null
        }
        Add-SectionHeader ($b.Name + " — bundle (" + [string]$b.Apps.Count + " apps)")
        foreach ($app in $b.Apps) {
            Add-PkgRow $app.Name $app.Id 8
            if ($seenIds.Add($app.Id)) { $allPackages.Add(@{Name=$app.Name; Id=$app.Id}) }
        }
    }

    ($dlg.FindName("DlgTitle")).Text = "Review — " + [string]$allPackages.Count + " package(s)"
    ($dlg.FindName("DlgTotal")).Text = [string]$allPackages.Count + " unique package(s) to install"
    ($dlg.FindName("DlgCancelBtn")).Add_Click({ $dlg.Close() })

    $installBtn     = $dlg.FindName("DlgInstallBtn")
    $installBtn.Tag = @{ Dlg = $dlg; Packages = $allPackages }
    $installBtn.Add_Click({
        param($s, $e)
        if ($script:installInProgress) { return }
        $info   = $s.Tag
        $pkgIds = @($info.Packages | ForEach-Object { $_.Id })
        $total  = $info.Packages.Count
        $info.Dlg.Close()

        $script:installInProgress = $true
        Set-BusyStatus ("Installing " + [string]$total + " package(s)...")
        Show-ScyProgress -Border $installsProgressBorder -Bar $installsProgressBar -Label $installsProgressLabel `
                         -Text ("Starting install of " + [string]$total + " package(s)...") -Value 0 -Max $total

        Start-ScyJob `
            -Variables @{ pkgs = $pkgIds } `
            -Context   @{ Total = $total } `
            -Work {
                param($emit)
                $failed = @()
                $i = 0
                foreach ($pkg in $pkgs) {
                    $i++
                    & $emit @{ Index = $i; Name = $pkg }
                    & winget install --id $pkg --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { $failed += $pkg }
                }
                return @{ Failed = $failed; Total = $pkgs.Count }
            } `
            -OnLine {
                param($line, $ctx)
                if ($line -is [hashtable]) {
                    $installsProgressBar.Value   = [double]$line.Index
                    $installsProgressLabel.Text  = "Installing " + [string]$line.Index + " of " + [string]$ctx.Total + " - " + [string]$line.Name
                    $footerStatus.Text           = "Scy - Installing: " + [string]$line.Name
                } else {
                    $footerStatus.Text = "Scy - Installing: " + [string]$line
                }
            } `
            -OnComplete {
                param($result, $err, $ctx)
                $script:installInProgress = $false
                Hide-ScyProgress $installsProgressBorder $installsProgressBar
                Set-ReadyStatus
                $script:selectedQuickItems.Clear()
                Update-QuickInstalls
                Update-QuickInstallSelectedState
                if ($err) {
                    Show-ThemedDialog ("Install error: " + $err.Exception.Message) "Error" "OK" "Error"
                    return
                }
                if ($result.Failed.Count -gt 0) {
                    Show-ThemedDialog ("Done. Failed packages:`n" + ($result.Failed -join "`n")) "Result" "OK" "Warning"
                } else {
                    Show-ThemedDialog ("Installed " + [string]$result.Total + " package(s) successfully.") "Done" "OK" "Information"
                }
            } | Out-Null
    })

    $dlg.ShowDialog() | Out-Null
}

function Update-QuickInstalls {
    Refresh-QuickInstallCategories
    $panel   = Find "QuickInstallsPanel"
    $editBtn = Find "BtnEditQuickInstalls"
    $panel.Children.Clear()

    if ($script:quickInstallEditMode) {
        $editBtn.Content   = "Done"

        foreach ($qi in $script:quickInstalls) {
            $name = $qi.Name
            $id   = $qi.Id

            $row = New-Object System.Windows.Controls.Grid
            $c0  = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
            $c1  = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::Auto
            $c2  = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(120)
            $c3  = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = [System.Windows.GridLength]::Auto
            $row.ColumnDefinitions.Add($c0); $row.ColumnDefinitions.Add($c1)
            $row.ColumnDefinitions.Add($c2); $row.ColumnDefinitions.Add($c3)
            $row.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)

            $nameBlock = New-Object System.Windows.Controls.TextBlock
            $nameBlock.Text              = $name
            $nameBlock.Foreground        = $window.Resources["FgBrush"]
            $nameBlock.FontSize          = 12
            $nameBlock.VerticalAlignment = "Center"
            [System.Windows.Controls.Grid]::SetColumn($nameBlock, 0)

            $idBlock = New-Object System.Windows.Controls.TextBlock
            $idBlock.Text              = $id
            $idBlock.Foreground        = $window.Resources["MutedText"]
            $idBlock.FontSize          = 11
            $idBlock.Margin            = [System.Windows.Thickness]::new(10, 0, 10, 0)
            $idBlock.VerticalAlignment = "Center"
            [System.Windows.Controls.Grid]::SetColumn($idBlock, 1)

            $catBox                   = New-Object System.Windows.Controls.ComboBox
            $catBox.IsEditable        = $true
            $catBox.FontSize          = 11
            $catBox.VerticalAlignment = "Center"
            $catBox.Margin            = [System.Windows.Thickness]::new(0, 0, 10, 0)
            $catBox.ToolTip           = "Category (select or type new)"
            $catBox.Tag               = $qi
            # Populate with all categories (defaults + custom)
            foreach ($cat in (Get-AllQuickCategories)) { $catBox.Items.Add($cat) | Out-Null }
            $catBox.Items.Add("+ New group...") | Out-Null
            $catBox.Text = if ($qi.Category) { $qi.Category } else { "" }
            $catBox.Add_SelectionChanged({
                param($s, $e)
                if ($s.SelectedItem -eq "+ New group...") {
                    Ensure-VisualBasic; $gName = [Microsoft.VisualBasic.Interaction]::InputBox("Category name:", "New Category", "")
                    if (-not [string]::IsNullOrWhiteSpace($gName)) {
                        $gName = $gName.Trim()
                        if ($gName -notin (Get-AllQuickCategories)) {
                            $script:customInstallCategories.Add($gName)
                            Save-Settings
                            if ((Get-Command Render-GroupSettings -ErrorAction SilentlyContinue)) { Render-GroupSettings }
                        }
                        $s.Tag.Category = $gName
                        $s.Text = $gName
                    } else {
                        $s.SelectedIndex = -1
                    }
                } elseif ($s.SelectedItem) {
                    $s.Tag.Category = $s.SelectedItem
                }
            })
            # Also handle typed text via the editable TextBox
            $catBox.AddHandler(
                [System.Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,
                [System.Windows.RoutedEventHandler]{
                    param($s, $e)
                    $combo = $s
                    while ($combo -and $combo -isnot [System.Windows.Controls.ComboBox]) {
                        $combo = [System.Windows.Media.VisualTreeHelper]::GetParent($combo)
                    }
                    if ($combo) { $combo.Tag.Category = $combo.Text }
                }
            )
            [System.Windows.Controls.Grid]::SetColumn($catBox, 2)

            $removeBtn         = New-Object System.Windows.Controls.Button
            $removeBtn.Content = "Remove"
            $removeBtn.Style      = $window.Resources["SecondaryButton"]
            $removeBtn.Foreground = $window.Resources["DangerBrush"]
            $removeBtn.Tag        = $id
            $removeBtn.Add_Click({
                param($s, $e)
                $idToRemove = $s.Tag
                $idx = -1
                for ($i = 0; $i -lt $script:quickInstalls.Count; $i++) {
                    if ($script:quickInstalls[$i].Id -eq $idToRemove) { $idx = $i; break }
                }
                if ($idx -ge 0) {
                    $script:quickInstalls.RemoveAt($idx)
                    Save-Settings
                    Update-QuickInstalls
                }
            })
            [System.Windows.Controls.Grid]::SetColumn($removeBtn, 3)

            $row.Children.Add($nameBlock) | Out-Null
            $row.Children.Add($idBlock)   | Out-Null
            $row.Children.Add($catBox)    | Out-Null
            $row.Children.Add($removeBtn) | Out-Null
            $panel.Children.Add($row)     | Out-Null
        }

        # Bundles section in edit mode
        $sepLine            = New-Object System.Windows.Controls.Border
        $sepLine.Height     = 1
        $sepLine.Background = $window.Resources["BorderBrush"]
        $sepLine.Margin     = [System.Windows.Thickness]::new(0, 10, 0, 10)
        $panel.Children.Add($sepLine) | Out-Null

        $bEditHeader            = New-Object System.Windows.Controls.TextBlock
        $bEditHeader.Text       = "Bundles"
        $bEditHeader.Foreground = $window.Resources["MutedText"]
        $bEditHeader.FontSize   = 11
        $bEditHeader.FontWeight = "SemiBold"
        $bEditHeader.Margin     = [System.Windows.Thickness]::new(0, 0, 0, 8)
        $panel.Children.Add($bEditHeader) | Out-Null

        foreach ($bndl in $script:quickBundles) {
            $capturedBndl = $bndl

            $bCard             = New-Object System.Windows.Controls.Border
            $bCard.Background  = $window.Resources["InputBgBrush"]
            $bCard.CornerRadius = [System.Windows.CornerRadius]::new(4)
            $bCard.Padding     = [System.Windows.Thickness]::new(10, 8, 10, 8)
            $bCard.Margin      = [System.Windows.Thickness]::new(0, 0, 0, 6)

            $bCardStack = New-Object System.Windows.Controls.StackPanel

            # Name / desc / remove row
            $hRow = New-Object System.Windows.Controls.Grid
            $hc0  = New-Object System.Windows.Controls.ColumnDefinition; $hc0.Width = New-Object System.Windows.GridLength(130)
            $hc1  = New-Object System.Windows.Controls.ColumnDefinition; $hc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
            $hc2  = New-Object System.Windows.Controls.ColumnDefinition; $hc2.Width = [System.Windows.GridLength]::Auto
            $hRow.ColumnDefinitions.Add($hc0); $hRow.ColumnDefinitions.Add($hc1); $hRow.ColumnDefinitions.Add($hc2)
            $hRow.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)

            $nameBox                 = New-Object System.Windows.Controls.TextBox
            $nameBox.Text            = $bndl.Name
            $nameBox.FontSize        = 12
            $nameBox.Foreground      = $window.Resources["FgBrush"]
            $nameBox.Background      = $window.Resources["InputBgBrush"]
            $nameBox.BorderBrush     = $window.Resources["BorderBrush"]
            $nameBox.BorderThickness = [System.Windows.Thickness]::new(1)
            $nameBox.Padding         = [System.Windows.Thickness]::new(6, 3, 6, 3)
            $nameBox.Margin          = [System.Windows.Thickness]::new(0, 0, 8, 0)
            $nameBox.ToolTip         = "Bundle name"
            $nameBox.Tag             = $bndl
            $nameBox.Add_TextChanged({ param($s, $e); $s.Tag.Name = $s.Text })
            [System.Windows.Controls.Grid]::SetColumn($nameBox, 0)

            $descBox                 = New-Object System.Windows.Controls.TextBox
            $descBox.Text            = if ($bndl.Description) { $bndl.Description } else { "" }
            $descBox.FontSize        = 11
            $descBox.Foreground      = $window.Resources["FgBrush"]
            $descBox.Background      = $window.Resources["InputBgBrush"]
            $descBox.BorderBrush     = $window.Resources["BorderBrush"]
            $descBox.BorderThickness = [System.Windows.Thickness]::new(1)
            $descBox.Padding         = [System.Windows.Thickness]::new(6, 3, 6, 3)
            $descBox.Margin          = [System.Windows.Thickness]::new(0, 0, 8, 0)
            $descBox.ToolTip         = "Description"
            $descBox.Tag             = $bndl
            $descBox.Add_TextChanged({ param($s, $e); $s.Tag.Description = $s.Text })
            [System.Windows.Controls.Grid]::SetColumn($descBox, 1)

            $removeBndlBtn          = New-Object System.Windows.Controls.Button
            $removeBndlBtn.Content  = "Remove"
            $removeBndlBtn.Style    = $window.Resources["SecondaryButton"]
            $removeBndlBtn.Foreground = $window.Resources["DangerBrush"]
            $removeBndlBtn.Tag      = $capturedBndl.Name
            $removeBndlBtn.Add_Click({
                param($s, $e)
                $nameToRemove = $s.Tag
                $idx = -1
                for ($i = 0; $i -lt $script:quickBundles.Count; $i++) {
                    if ($script:quickBundles[$i].Name -eq $nameToRemove) { $idx = $i; break }
                }
                if ($idx -ge 0) {
                    $script:quickBundles.RemoveAt($idx)
                    Save-Settings
                    Update-QuickInstalls
                }
            })
            [System.Windows.Controls.Grid]::SetColumn($removeBndlBtn, 2)

            $hRow.Children.Add($nameBox)      | Out-Null
            $hRow.Children.Add($descBox)      | Out-Null
            $hRow.Children.Add($removeBndlBtn) | Out-Null
            $bCardStack.Children.Add($hRow)   | Out-Null

            # App rows inside the bundle
            foreach ($app in @($bndl.Apps)) {
                $capturedApp  = $app
                $capturedBndlForApp = $bndl

                $appRow = New-Object System.Windows.Controls.Grid
                $arc0   = New-Object System.Windows.Controls.ColumnDefinition; $arc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
                $arc1   = New-Object System.Windows.Controls.ColumnDefinition; $arc1.Width = [System.Windows.GridLength]::Auto
                $arc2   = New-Object System.Windows.Controls.ColumnDefinition; $arc2.Width = [System.Windows.GridLength]::Auto
                $appRow.ColumnDefinitions.Add($arc0); $appRow.ColumnDefinitions.Add($arc1); $appRow.ColumnDefinitions.Add($arc2)
                $appRow.Margin = [System.Windows.Thickness]::new(8, 0, 0, 2)

                $appNameBlock                  = New-Object System.Windows.Controls.TextBlock
                $appNameBlock.Text             = $app.Name
                $appNameBlock.Foreground       = $window.Resources["FgBrush"]
                $appNameBlock.FontSize         = 11
                $appNameBlock.VerticalAlignment = "Center"
                [System.Windows.Controls.Grid]::SetColumn($appNameBlock, 0)

                $appIdBlock                  = New-Object System.Windows.Controls.TextBlock
                $appIdBlock.Text             = $app.Id
                $appIdBlock.Foreground       = $window.Resources["MutedText"]
                $appIdBlock.FontSize         = 10
                $appIdBlock.Margin           = [System.Windows.Thickness]::new(8, 0, 10, 0)
                $appIdBlock.VerticalAlignment = "Center"
                [System.Windows.Controls.Grid]::SetColumn($appIdBlock, 1)

                $removeAppBtn           = New-Object System.Windows.Controls.Button
                $removeAppBtn.Content   = "×"
                $removeAppBtn.Style     = $window.Resources["SecondaryButton"]
                $removeAppBtn.Foreground = $window.Resources["MutedText"]
                $removeAppBtn.Padding   = [System.Windows.Thickness]::new(6, 1, 6, 1)
                $removeAppBtn.Add_Click(({
                    $capturedBndlForApp.Apps.Remove($capturedApp) | Out-Null
                    Save-Settings
                    Update-QuickInstalls
                }.GetNewClosure()))
                [System.Windows.Controls.Grid]::SetColumn($removeAppBtn, 2)

                $appRow.Children.Add($appNameBlock) | Out-Null
                $appRow.Children.Add($appIdBlock)   | Out-Null
                $appRow.Children.Add($removeAppBtn) | Out-Null
                $bCardStack.Children.Add($appRow)   | Out-Null
            }

            $bCard.Child = $bCardStack
            $panel.Children.Add($bCard) | Out-Null
        }

        $newBundleBtn                     = New-Object System.Windows.Controls.Button
        $newBundleBtn.Content             = "+ New Bundle"
        $newBundleBtn.Style               = $window.Resources["ActionButton"]
        $newBundleBtn.Margin              = [System.Windows.Thickness]::new(0, 4, 0, 0)
        $newBundleBtn.HorizontalAlignment = "Left"
        $newBundleBtn.Add_Click({
            Ensure-VisualBasic; $bName = [Microsoft.VisualBasic.Interaction]::InputBox("Bundle name:", "New Bundle", "")
            if ([string]::IsNullOrWhiteSpace($bName)) { return }
            if ($script:quickBundles | Where-Object { $_.Name -eq $bName }) {
                Show-ThemedDialog "A bundle named '$bName' already exists." "Duplicate" "OK" "Warning"
                return
            }
            Ensure-VisualBasic; $bDesc = [Microsoft.VisualBasic.Interaction]::InputBox("Description (optional):", "Bundle Description", "")
            $script:quickBundles.Add(@{
                Name        = $bName
                Description = $bDesc
                Apps        = [System.Collections.Generic.List[hashtable]]::new()
            })
            Save-Settings
            Update-QuickInstalls
        })
        $panel.Children.Add($newBundleBtn) | Out-Null

    } else {
        $editBtn.Content = "Edit"

        # Capture script-scoped references so they are accessible inside .GetNewClosure() handlers
        $selItems = $script:selectedQuickItems

        # Group by category; items with no category go to "Uncategorized"
        $groups = [ordered]@{}
        foreach ($qi in $script:quickInstalls) {
            $cat = if ($qi.Category) { $qi.Category } else { "Uncategorized" }
            if (-not $groups.Contains($cat)) {
                $groups[$cat] = [System.Collections.Generic.List[hashtable]]::new()
            }
            $groups[$cat].Add($qi)
        }

        # Named categories alphabetically, Uncategorized last
        $named   = @($groups.Keys | Where-Object { $_ -ne "Uncategorized" } | Sort-Object)
        $allCats = if ($groups.Contains("Uncategorized")) { $named + @("Uncategorized") } else { $named }

        # Build 2-column grid
        $twoColGrid = New-Object System.Windows.Controls.Grid
        $col0 = New-Object System.Windows.Controls.ColumnDefinition; $col0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $colG = New-Object System.Windows.Controls.ColumnDefinition; $colG.Width = [System.Windows.GridLength]::new(8)
        $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $twoColGrid.ColumnDefinitions.Add($col0)
        $twoColGrid.ColumnDefinitions.Add($colG)
        $twoColGrid.ColumnDefinitions.Add($col2)

        $leftCol  = New-Object System.Windows.Controls.StackPanel; $leftCol.VerticalAlignment  = "Top"
        $rightCol = New-Object System.Windows.Controls.StackPanel; $rightCol.VerticalAlignment = "Top"
        [System.Windows.Controls.Grid]::SetColumn($leftCol,  0)
        [System.Windows.Controls.Grid]::SetColumn($rightCol, 2)
        $twoColGrid.Children.Add($leftCol)  | Out-Null
        $twoColGrid.Children.Add($rightCol) | Out-Null
        $panel.Children.Add($twoColGrid) | Out-Null

        $colIdx = 0

        # ── Category cards ────────────────────────────────────────
        foreach ($cat in $allCats) {
            if (-not $groups.Contains($cat) -or $groups[$cat].Count -eq 0) { continue }

            $border              = New-Object System.Windows.Controls.Border
            $border.Background   = $window.Resources["Surface2Brush"]
            $border.CornerRadius = [System.Windows.CornerRadius]::new(6)
            $border.BorderBrush  = $window.Resources["BorderBrush"]
            $border.BorderThickness = [System.Windows.Thickness]::new(1)
            $border.Padding      = [System.Windows.Thickness]::new(14, 12, 14, 12)
            $border.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 8)

            $cardStack = New-Object System.Windows.Controls.StackPanel

            $header = New-Object System.Windows.Controls.TextBlock
            $header.Text = $cat
            $header.FontSize = 11
            $header.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
            $header.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
            $cardStack.Children.Add($header) | Out-Null

            $itemsPanel = New-Object System.Windows.Controls.StackPanel
            $cardStack.Children.Add($itemsPanel) | Out-Null
            $border.Child = $cardStack

            if ($colIdx % 2 -eq 0) { $leftCol.Children.Add($border)  | Out-Null }
            else                   { $rightCol.Children.Add($border) | Out-Null }
            $colIdx++

            $isFirstItem = $true
            foreach ($qi in $groups[$cat]) {
                $qiName = $qi.Name
                $qiId   = $qi.Id

                if (-not $isFirstItem) {
                    $sep = New-Object System.Windows.Shapes.Rectangle
                    $sep.Height = 1
                    $sep.SetResourceReference([System.Windows.Shapes.Rectangle]::FillProperty, "BorderBrush")
                    $itemsPanel.Children.Add($sep) | Out-Null
                }
                $isFirstItem = $false

                $btn = New-Object System.Windows.Controls.Button
                $btn.Style = $window.FindResource("ShortcutRowButton")

                $rowGrid = New-Object System.Windows.Controls.Grid
                $starCol = New-Object System.Windows.Controls.ColumnDefinition; $starCol.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
                $autoCol = New-Object System.Windows.Controls.ColumnDefinition; $autoCol.Width = [System.Windows.GridLength]::Auto
                $rowGrid.ColumnDefinitions.Add($starCol)
                $rowGrid.ColumnDefinitions.Add($autoCol)

                $nameBlock = New-Object System.Windows.Controls.TextBlock
                $nameBlock.Text = $qiName
                $nameBlock.FontSize = 12
                $nameBlock.VerticalAlignment = "Center"
                [System.Windows.Controls.Grid]::SetColumn($nameBlock, 0)

                $idBlock = New-Object System.Windows.Controls.TextBlock
                $idBlock.Text = $qiId
                $idBlock.FontSize = 11
                $idBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                $idBlock.VerticalAlignment = "Center"
                [System.Windows.Controls.Grid]::SetColumn($idBlock, 1)

                $rowGrid.Children.Add($nameBlock) | Out-Null
                $rowGrid.Children.Add($idBlock)   | Out-Null
                $btn.Content = $rowGrid

                $capturedNameBlock = $nameBlock
                if ($null -ne ($selItems | Where-Object { $_.Key -eq $qiId } | Select-Object -First 1)) {
                    $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "SuccessBrush")
                } else {
                    $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
                }

                $btn.Add_Click(({
                    $existingIdx = -1
                    for ($i = 0; $i -lt $selItems.Count; $i++) {
                        if ($selItems[$i].Key -eq $qiId) { $existingIdx = $i; break }
                    }
                    if ($existingIdx -ge 0) {
                        $selItems.RemoveAt($existingIdx)
                        $capturedNameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
                    } else {
                        $selItems.Add(@{Key=$qiId; Type="App"; Name=$qiName; Id=$qiId})
                        $capturedNameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "SuccessBrush")
                    }
                    Update-QuickInstallSelectedState
                }.GetNewClosure()))

                $itemsPanel.Children.Add($btn) | Out-Null
            }
        }

        # ── Bundles card ──────────────────────────────────────────
        if ($script:quickBundles.Count -gt 0) {
            $bBorder              = New-Object System.Windows.Controls.Border
            $bBorder.Background   = $window.Resources["Surface2Brush"]
            $bBorder.CornerRadius = [System.Windows.CornerRadius]::new(6)
            $bBorder.BorderBrush  = $window.Resources["BorderBrush"]
            $bBorder.BorderThickness = [System.Windows.Thickness]::new(1)
            $bBorder.Padding      = [System.Windows.Thickness]::new(14, 12, 14, 12)
            $bBorder.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 8)

            $bCardStack = New-Object System.Windows.Controls.StackPanel
            $bHeader = New-Object System.Windows.Controls.TextBlock
            $bHeader.Text = "Bundles"
            $bHeader.FontSize = 11
            $bHeader.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
            $bHeader.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
            $bCardStack.Children.Add($bHeader) | Out-Null

            $bItemsPanel = New-Object System.Windows.Controls.StackPanel
            $bCardStack.Children.Add($bItemsPanel) | Out-Null
            $bBorder.Child = $bCardStack

            if ($colIdx % 2 -eq 0) { $leftCol.Children.Add($bBorder)  | Out-Null }
            else                   { $rightCol.Children.Add($bBorder) | Out-Null }

            $isFirstBundle = $true
            foreach ($bndl in $script:quickBundles) {
                $qBundle = $bndl

                if (-not $isFirstBundle) {
                    $bSep = New-Object System.Windows.Shapes.Rectangle
                    $bSep.Height = 1
                    $bSep.SetResourceReference([System.Windows.Shapes.Rectangle]::FillProperty, "BorderBrush")
                    $bItemsPanel.Children.Add($bSep) | Out-Null
                }
                $isFirstBundle = $false

                $bBtn = New-Object System.Windows.Controls.Button
                $bBtn.Style = $window.FindResource("ShortcutRowButton")

                $bRowGrid = New-Object System.Windows.Controls.Grid
                $bStarCol = New-Object System.Windows.Controls.ColumnDefinition; $bStarCol.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
                $bAutoCol = New-Object System.Windows.Controls.ColumnDefinition; $bAutoCol.Width = [System.Windows.GridLength]::Auto
                $bRowGrid.ColumnDefinitions.Add($bStarCol)
                $bRowGrid.ColumnDefinitions.Add($bAutoCol)

                $bNameBlock = New-Object System.Windows.Controls.TextBlock
                $bNameBlock.Text = $bndl.Name
                $bNameBlock.FontSize = 12
                $bNameBlock.VerticalAlignment = "Center"
                [System.Windows.Controls.Grid]::SetColumn($bNameBlock, 0)

                $bDescBlock = New-Object System.Windows.Controls.TextBlock
                $bDescBlock.Text = if ($bndl.Description) { $bndl.Description } else { "$($bndl.Apps.Count) apps" }
                $bDescBlock.FontSize = 11
                $bDescBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                $bDescBlock.VerticalAlignment = "Center"
                [System.Windows.Controls.Grid]::SetColumn($bDescBlock, 1)

                $bRowGrid.Children.Add($bNameBlock) | Out-Null
                $bRowGrid.Children.Add($bDescBlock) | Out-Null
                $bBtn.Content = $bRowGrid

                $capturedBNameBlock = $bNameBlock
                if ($null -ne ($selItems | Where-Object { $_.Key -eq $qBundle.Name } | Select-Object -First 1)) {
                    $bNameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "SuccessBrush")
                } else {
                    $bNameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
                }

                $bBtn.Add_Click(({
                    $existingIdx = -1
                    for ($i = 0; $i -lt $selItems.Count; $i++) {
                        if ($selItems[$i].Key -eq $qBundle.Name) { $existingIdx = $i; break }
                    }
                    if ($existingIdx -ge 0) {
                        $selItems.RemoveAt($existingIdx)
                        $capturedBNameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
                    } else {
                        $selItems.Add(@{Key=$qBundle.Name; Type="Bundle"; Name=$qBundle.Name; Bundle=$qBundle})
                        $capturedBNameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "SuccessBrush")
                    }
                    Update-QuickInstallSelectedState
                }.GetNewClosure()))

                $bItemsPanel.Children.Add($bBtn) | Out-Null
            }
        }
    }
}

# -- Edit Quick Installs toggle -----------------------------------------------
(Find "BtnEditQuickInstalls").Add_Click({
    if ($script:quickInstallEditMode) { Save-Settings }
    $script:quickInstallEditMode = -not $script:quickInstallEditMode
    $script:selectedQuickItems.Clear()
    Update-QuickInstalls
    Update-QuickInstallSelectedState
})

# -- Quick Install — confirm and install selected -----------------------------
(Find "BtnQuickInstallSelected").Add_Click({
    if ($script:selectedQuickItems.Count -eq 0) { return }
    Show-QuickInstallConfirmDialog
})

# -- Add to Quick Installs button ---------------------------------------------
$btnAddToQuickInstalls.Add_Click({
    $toAdd      = @($script:searchItems | Where-Object { $_.CheckBox.IsChecked })
    $existingIds = @($script:quickInstalls | ForEach-Object { $_.Id })
    $category = $quickInstallCategoryBox.Text.Trim()
    $added = 0
    foreach ($item in $toAdd) {
        if ($item.Id -notin $existingIds) {
            $script:quickInstalls.Add(@{Name = $item.Name; Id = $item.Id; Category = $category})
            $added++
        }
    }
    if ($added -gt 0) {
        Save-Settings
        Update-QuickInstalls
        Refresh-QuickInstallCategories
        Show-ThemedDialog "Added $added package(s) to Quick Installs." "Done" "OK" "Information"
    } else {
        Show-ThemedDialog "Selected packages are already in Quick Installs." "No Change" "OK" "Information"
    }
})

# -- Add to Bundle ------------------------------------------------------------
$btnAddToBundle.Add_Click({
    $toAdd = @($script:searchItems | Where-Object { $_.CheckBox.IsChecked })
    if ($toAdd.Count -eq 0) { return }

    Ensure-VisualBasic; $bName = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Enter a bundle name (new or existing):",
        "Add to Bundle", "")
    if ([string]::IsNullOrWhiteSpace($bName)) { return }

    $bundle = $script:quickBundles | Where-Object { $_.Name -eq $bName } | Select-Object -First 1
    if ($null -eq $bundle) {
        Ensure-VisualBasic; $bDesc = [Microsoft.VisualBasic.Interaction]::InputBox(
            "Description for '$bName' (optional):",
            "Bundle Description", "")
        $bundle = @{
            Name        = $bName
            Description = $bDesc
            Apps        = [System.Collections.Generic.List[hashtable]]::new()
        }
        $script:quickBundles.Add($bundle)
    }

    $existingIds = @($bundle.Apps | ForEach-Object { $_.Id })
    $added = 0
    foreach ($item in $toAdd) {
        if ($item.Id -notin $existingIds) {
            $bundle.Apps.Add(@{Name = $item.Name; Id = $item.Id})
            $added++
        }
    }

    if ($added -gt 0) {
        Save-Settings
        Update-QuickInstalls
        Show-ThemedDialog "Added $added app(s) to bundle '$bName'." "Done" "OK" "Information"
    } else {
        Show-ThemedDialog "Selected apps are already in bundle '$bName'." "No Change" "OK" "Information"
    }
})

# -- Export bundles -----------------------------------------------------------
$btnExportBundles.Add_Click({
    if ($script:quickBundles.Count -eq 0) {
        Show-ThemedDialog "No bundles to export." "Export Bundles" "OK" "Information"
        return
    }
    Add-Type -AssemblyName System.Windows.Forms
    $dlg          = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title    = "Export Bundles"
    $dlg.Filter   = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    $dlg.FileName = "scy-bundles.json"
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $export = @{
        version = 1
        bundles = @($script:quickBundles | ForEach-Object {
            @{
                name        = $_.Name
                description = if ($_.Description) { $_.Description } else { "" }
                apps        = @($_.Apps | ForEach-Object { @{ name = $_.Name; id = $_.Id } })
            }
        })
    }
    $export | ConvertTo-Json -Depth 5 | Set-Content -Path $dlg.FileName -Encoding UTF8
    Show-ThemedDialog "Exported $($script:quickBundles.Count) bundle(s) to:`n$($dlg.FileName)" "Done" "OK" "Information"
})

# -- Import bundles -----------------------------------------------------------
$btnImportBundles.Add_Click({
    Add-Type -AssemblyName System.Windows.Forms
    $dlg        = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = "Import Bundles"
    $dlg.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    try {
        $json    = Get-Content -Path $dlg.FileName -Raw -Encoding UTF8
        $data    = $json | ConvertFrom-Json
        $bundles = if ($data.bundles) { @($data.bundles) } else { @($data) }
        $added   = 0
        $skipped = 0
        foreach ($b in $bundles) {
            $existing = $script:quickBundles | Where-Object { $_.Name -eq $b.name } | Select-Object -First 1
            if ($null -ne $existing) { $skipped++; continue }
            $apps = [System.Collections.Generic.List[hashtable]]::new()
            foreach ($a in @($b.apps)) { $apps.Add(@{ Name = $a.name; Id = $a.id }) }
            $script:quickBundles.Add(@{
                Name        = $b.name
                Description = if ($b.description) { $b.description } else { "" }
                Apps        = $apps
            })
            $added++
        }
        if ($added -gt 0) { Save-Settings; Update-QuickInstalls }
        $msg = "Imported $added bundle(s)."
        if ($skipped -gt 0) { $msg += " Skipped $skipped (name already exists)." }
        Show-ThemedDialog $msg "Import Bundles" "OK" "Information"
    } catch {
        Show-ThemedDialog ("Failed to import: " + $_.Exception.Message) "Error" "OK" "Error"
    }
})

# -- Local installers ---------------------------------------------------------
$script:localInstallFolder = [System.IO.Path]::Combine($env:USERPROFILE, "Downloads")

function Render-LocalInstallerButtons {
    param([array]$FileList)
    $panel = Find "LocalInstallersPanel"
    $panel.Children.Clear()

    if ($FileList.Count -eq 0) {
        $tb            = New-Object System.Windows.Controls.TextBlock
        $tb.Text       = "No .exe or .msi files found."
        $tb.Foreground = $window.Resources["MutedText"]
        $tb.FontSize   = 12
        $panel.Children.Add($tb) | Out-Null
        return
    }

    foreach ($f in $FileList) {
        $name     = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $fullPath = $f.FullName
        $fileName = $f.Name
        $btn         = New-Object System.Windows.Controls.Button
        $btn.Content = $name
        $btn.Style   = $window.Resources["QuickAppButton"]
        $btn.Margin  = [System.Windows.Thickness]::new(0, 0, 6, 6)
        $btn.ToolTip = $fullPath
        $btn.Add_Click(({
            try {
                Start-Process $fullPath
                $footerStatus.Text = "Scy - Launched: $fileName"
            } catch {
                Show-ThemedDialog "Could not run '$fileName':`n$_" "Error" "OK" "Error"
            }
        }.GetNewClosure()))
        $panel.Children.Add($btn) | Out-Null
    }
}

function Update-LocalInstallers {
    $panel  = Find "LocalInstallersPanel"
    $folder = $script:localInstallFolder
    $panel.Children.Clear()
    (Find "LocalInstallersFolder").Text = $folder

    if (-not (Test-Path $folder)) {
        $tb            = New-Object System.Windows.Controls.TextBlock
        $tb.Text       = "Folder not found."
        $tb.Foreground = $window.Resources["MutedText"]
        $tb.FontSize   = 12
        $panel.Children.Add($tb) | Out-Null
        return
    }

    $exts  = $script:localInstallerExtensions
    $files = @(Get-ChildItem -Path $folder -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in $exts } | Sort-Object Name)

    $fileList = @($files | ForEach-Object { @{Name=$_.Name; FullName=$_.FullName} })

    # Cache the list if remember is enabled
    if ($script:rememberLocalInstallers) {
        $script:cachedLocalInstallers = $fileList
        Save-Settings
    }

    Render-LocalInstallerButtons $fileList

    # After first scan, switch button to "Rescan" secondary style
    $rescanBtn = Find "BtnLocalRescan"
    $rescanBtn.Content = "Rescan"
    $rescanBtn.Style   = $window.Resources["SecondaryButton"]
}

(Find "BtnLocalRescan").Add_Click({ Update-LocalInstallers })

(Find "BtnLocalChangeFolder").Add_Click({
    Add-Type -AssemblyName System.Windows.Forms
    $dlg             = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select folder to scan for installers"
    $dlg.SelectedPath = $script:localInstallFolder
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Set-LocalInstallFolder $dlg.SelectedPath
    }
})

# Deferred — settings are loaded by Tab-Settings.ps1 which is sourced after this file
$window.Dispatcher.BeginInvoke([action]{
    if ($script:rememberLocalInstallers -and $script:cachedLocalInstallers.Count -gt 0) {
        Render-LocalInstallerButtons $script:cachedLocalInstallers
        $rescanBtn = Find "BtnLocalRescan"
        $rescanBtn.Content = "Rescan"
        $rescanBtn.Style   = $window.Resources["SecondaryButton"]
    } elseif ($script:autoScanLocalInstallers) {
        Update-LocalInstallers
    }
}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null

