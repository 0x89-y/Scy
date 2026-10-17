# Shared cy-design side rail.
#
# One rail implementation for every tab (Apps, System, Tweaks, Bookmarks,
# Network, Active Directory, Tools, Settings) so they all look identical:
# flush entries without dividers; the active entry gets a 3px accent left-bar,
# white semi-bold text and a neutral row fill (readable on dark; purple is only
# the marker, like the underline on the top tabs).
#
# Usage:
#   Build-Rail -Panel (Find "SystemRail") -Labels @("Info","Cleanup") `
#              -ActiveIndex 0 -OnSelect { param($i) Set-SystemSubNav $i }

# A single rail entry. $Count -lt 0 renders no count.
# $Indent 1 nests the entry under a section header (two-level rails).
# $IsSection styles it as a group header rather than a leaf entry.
function New-RailEntry {
    param(
        [string]$Label,
        [int]$Count = -1,
        [bool]$IsActive = $false,
        [scriptblock]$OnClick,
        [int]$Indent = 0,
        [bool]$IsSection = $false
    )

    # The accent left-bar is a separate 3px element inside the entry.
    $border = New-Object System.Windows.Controls.Border
    $border.BorderThickness = [System.Windows.Thickness]::new(0)
    $border.Padding         = [System.Windows.Thickness]::new(0)
    $border.Cursor          = [System.Windows.Input.Cursors]::Hand
    $border.Background      = [System.Windows.Media.Brushes]::Transparent

    $outer = New-Object System.Windows.Controls.Grid
    $b0 = New-Object System.Windows.Controls.ColumnDefinition; $b0.Width = [System.Windows.GridLength]::Auto
    $b1 = New-Object System.Windows.Controls.ColumnDefinition; $b1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $outer.ColumnDefinitions.Add($b0); $outer.ColumnDefinitions.Add($b1)

    $bar = New-Object System.Windows.Controls.Border
    $bar.Width             = 3
    $bar.VerticalAlignment = "Stretch"
    $bar.Background        = [System.Windows.Media.Brushes]::Transparent
    [System.Windows.Controls.Grid]::SetColumn($bar, 0)

    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = [System.Windows.Thickness]::new((10 + ($Indent * 12)), 8, 12, 8)
    [System.Windows.Controls.Grid]::SetColumn($grid, 1)
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1)

    $name                   = New-Object System.Windows.Controls.TextBlock
    $name.Text              = $Label
    $name.FontSize          = 12
    $name.TextWrapping      = "Wrap"
    $name.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($name, 0)

    $countBlock                   = New-Object System.Windows.Controls.TextBlock
    $countBlock.Text              = if ($Count -ge 0) { [string]$Count } else { "" }
    $countBlock.FontSize          = 11
    $countBlock.VerticalAlignment = "Center"
    $countBlock.Margin            = [System.Windows.Thickness]::new(6, 0, 0, 0)
    [System.Windows.Controls.Grid]::SetColumn($countBlock, 1)

    if ($IsActive) {
        # Neutral row fill: in two-level rails the section headers are also white
        # semi-bold, so text alone wouldn't single out the selected entry
        $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "HoverSurfaceBrush")
        $bar.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "AccentBrush")
        $name.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
        $countBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
        $name.FontWeight = [System.Windows.FontWeights]::SemiBold
    } else {
        if ($IsSection) {
            # Section header: reads as a title, not a selectable leaf
            $name.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
            $name.FontWeight = [System.Windows.FontWeights]::SemiBold
        } else {
            $name.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "SubTextBrush")
        }
        $countBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
        $border.Add_MouseEnter({ $this.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "HoverSurfaceBrush") })
        $border.Add_MouseLeave({ $this.Background = [System.Windows.Media.Brushes]::Transparent })
    }

    $grid.Children.Add($name)       | Out-Null
    $grid.Children.Add($countBlock) | Out-Null
    $outer.Children.Add($bar)       | Out-Null
    $outer.Children.Add($grid)      | Out-Null
    $border.Child = $outer

    if ($OnClick) { $border.Add_MouseLeftButtonUp($OnClick) }
    return $border
}

# Fill $Panel with one entry per label. Clicking entry i invokes & $OnSelect $i.
# $Counts is optional and parallel to $Labels (-1 / omitted = no count shown).
function Build-Rail {
    param(
        $Panel,
        [string[]]$Labels,
        [int]$ActiveIndex = 0,
        [scriptblock]$OnSelect,
        [int[]]$Counts
    )
    if (-not $Panel) { return }
    $Panel.Children.Clear()

    for ($i = 0; $i -lt $Labels.Count; $i++) {
        $idx   = $i
        $count = if ($Counts -and $i -lt $Counts.Count) { $Counts[$i] } else { -1 }
        $click = if ($OnSelect) { ({ & $OnSelect $idx }).GetNewClosure() } else { $null }
        $Panel.Children.Add(
            (New-RailEntry -Label $Labels[$i] -Count $count `
                           -IsActive ($i -eq $ActiveIndex) -OnClick $click)) | Out-Null
    }
}
