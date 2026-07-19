# Shared row helpers used by Tab-Info and Tab-ActiveDirectory.
# Builds System Info-style key/value rows, headers, and separators.

function New-InfoRow {
    param(
        [string]$Label,
        [string]$Value,
        [string]$ValueBrushKey = "FgBrush",
        # Ignored. Rows are separated by hairlines, not by a zebra fill; kept so
        # the ~20 existing call sites don't all need touching.
        [bool]$Alternate = $false
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { $Value = "(none)" }

    # cy-design divided list: flush row, no fill, hairline bottom divider. The
    # border spans full width so dividers line up; only the text is inset.
    $border = New-Object System.Windows.Controls.Border
    $border.Background = [System.Windows.Media.Brushes]::Transparent
    $border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
    $border.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
    $border.CornerRadius = [System.Windows.CornerRadius]::new(0)
    $border.Padding      = [System.Windows.Thickness]::new(10, 7, 10, 7)
    $border.Margin       = [System.Windows.Thickness]::new(0)

    $grid = New-Object System.Windows.Controls.Grid
    $c0   = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::Auto
    $c1   = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $grid.ColumnDefinitions.Add($c0)
    $grid.ColumnDefinitions.Add($c1)

    $lbl          = New-Object System.Windows.Controls.TextBlock
    $lbl.Text     = $Label
    $lbl.FontSize = 12
    $lbl.MinWidth = 110
    $lbl.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    [System.Windows.Controls.Grid]::SetColumn($lbl, 0)

    $val                     = New-Object System.Windows.Controls.TextBlock
    $val.Text                = $Value
    $val.FontSize            = 12
    $val.HorizontalAlignment = "Right"
    $val.TextAlignment       = "Right"
    $val.TextWrapping        = "Wrap"
    $val.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $ValueBrushKey)
    [System.Windows.Controls.Grid]::SetColumn($val, 1)

    $grid.Children.Add($lbl) | Out-Null
    $grid.Children.Add($val) | Out-Null
    $border.Child = $grid
    return $border
}

function New-AdapterHeader {
    param([string]$Name)
    $tb            = New-Object System.Windows.Controls.TextBlock
    $tb.Text       = $Name
    $tb.FontSize   = 11
    $tb.FontWeight = "SemiBold"
    $tb.Margin     = [System.Windows.Thickness]::new(0, 8, 0, 4)
    $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "AccentBrush")
    return $tb
}

function New-SectionHeader {
    param([string]$Text)
    $tb            = New-Object System.Windows.Controls.TextBlock
    $tb.Text       = $Text
    $tb.FontSize   = 12
    $tb.FontWeight = "SemiBold"
    $tb.Margin     = [System.Windows.Thickness]::new(0, 8, 0, 4)
    $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "AccentBrush")
    return $tb
}

# Group break inside a divided list. Deliberately blank: the preceding row
# already draws a hairline, so a rule here would render as a double line. The
# gap plus the next header is what separates the groups.
function New-Separator {
    $sep = New-Object System.Windows.Controls.Border
    $sep.Height     = 10
    $sep.Background = [System.Windows.Media.Brushes]::Transparent
    return $sep
}

function New-PlainLine {
    param([string]$Text)
    $tb            = New-Object System.Windows.Controls.TextBlock
    $tb.Text       = $Text
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily("IBM Plex Mono, Cascadia Mono, Consolas")
    $tb.FontSize   = 11
    $tb.Margin     = [System.Windows.Thickness]::new(2, 1, 2, 1)
    $tb.TextWrapping = "Wrap"
    $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
    return $tb
}
