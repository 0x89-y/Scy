# ==================================================================
#  HOSTS FILE EDITOR TAB
#
#  Visual editor for C:\Windows\System32\drivers\etc\hosts
#  - Toggle entries on/off without deleting them (saved as # comment)
#  - Add / remove custom entries
#  - Save requires Administrator privileges
# ==================================================================

$hostsPath         = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
$hostsEntriesPanel = Find "HostsEntriesPanel"
$hostsStatusText   = Find "HostsStatusText"
$hostsAddPanel     = Find "HostsAddPanel"
$hostsNewIP        = Find "HostsNewIP"
$hostsNewHost      = Find "HostsNewHost"
$hostsNewComment   = Find "HostsNewComment"

# Every line of the file in order (comments, blanks and entries alike), plus the
# subset that are entries and get a row in the UI. Entries are the same
# hashtables in both lists, so a toggle or remove applies to both.
$script:hostsLines   = [System.Collections.Generic.List[hashtable]]::new()
$script:hostsEntries = [System.Collections.Generic.List[hashtable]]::new()

function Test-HostsIp {
    param([string]$Value)
    $ip = $null
    # Require a dotted quad or an IPv6-looking token: TryParse alone accepts "1".
    return (($Value -match '^\d{1,3}(\.\d{1,3}){3}$' -or $Value.Contains(':')) -and
            [System.Net.IPAddress]::TryParse($Value, [ref]$ip))
}

# -- Parse the hosts file -----------------------------------------
# Each line keeps its Raw text so saving only rewrites entries the user changed;
# comments, blank lines and anything unparseable are written back untouched.
function Read-HostsFile {
    $lines = [System.Collections.Generic.List[hashtable]]::new()
    if (-not (Test-Path $hostsPath)) { return ,$lines }

    foreach ($line in [System.IO.File]::ReadAllLines($hostsPath)) {
        $item     = @{ Raw = $line; IsEntry = $false }
        $content  = $line.Trim()
        $disabled = $false
        if ($content.StartsWith("#")) {
            # Could be a disabled entry: # 0.0.0.0 hostname
            $content  = $content.Substring(1).Trim()
            $disabled = $true
        }
        # IP, one or more hostnames, optional trailing comment
        if ($content -match '^(\S+)\s+([^#]+?)\s*(?:#\s*(.*))?$' -and (Test-HostsIp $Matches[1])) {
            $item.IsEntry     = $true
            $item.IP          = $Matches[1]
            $item.Host        = ($Matches[2].Trim() -split '\s+') -join ' '
            $item.Comment     = if ($Matches[3]) { $Matches[3].Trim() } else { "" }
            $item.Enabled     = -not $disabled
            $item.OrigEnabled = -not $disabled
        }
        $lines.Add($item)
    }
    return ,$lines
}

# -- Build a single row for an entry ------------------------------
function New-HostsRow {
    param($Entry, [bool]$Alternate = $false)

    # cy-design divided list: flush row, hairline bottom divider (no zebra fill).
    $border = New-Object System.Windows.Controls.Border
    $border.Background      = [System.Windows.Media.Brushes]::Transparent
    $border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
    $border.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
    $border.Padding         = [System.Windows.Thickness]::new(14, 9, 14, 9)
    $border.Margin          = [System.Windows.Thickness]::new(0)

    $grid = New-Object System.Windows.Controls.Grid
    foreach ($spec in @(50, 150, "star", "star")) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = switch ($spec) {
            "star" { New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star) }
            default { [System.Windows.GridLength]::new([double]$spec) }
        }
        $grid.ColumnDefinitions.Add($cd)
    }

    # Col 0 - toggle
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Style             = $window.Resources["TweakToggle"]
    $cb.IsChecked         = $Entry.Enabled
    $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $cb.Tag               = $Entry
    [System.Windows.Controls.Grid]::SetColumn($cb, 0)
    $cb.Add_Checked({   param($s,$e); $s.Tag.Enabled = $true  })
    $cb.Add_Unchecked({ param($s,$e); $s.Tag.Enabled = $false })

    # Col 1 - IP address
    $ipText                   = New-Object System.Windows.Controls.TextBlock
    $ipText.Text              = $Entry.IP
    $ipText.FontSize          = 12
    $ipText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $ipText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    [System.Windows.Controls.Grid]::SetColumn($ipText, 1)

    # Col 2 - hostname
    $hostText                   = New-Object System.Windows.Controls.TextBlock
    $hostText.Text              = $Entry.Host
    $hostText.FontSize          = 12
    $hostText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $hostText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
    [System.Windows.Controls.Grid]::SetColumn($hostText, 2)

    # Col 3 - comment
    $commentText                   = New-Object System.Windows.Controls.TextBlock
    $commentText.Text              = if ($Entry.Comment) { "# $($Entry.Comment)" } else { "" }
    $commentText.FontSize          = 11
    $commentText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $commentText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    [System.Windows.Controls.Grid]::SetColumn($commentText, 3)

    # Right-click context menu for Remove
    $ctxMenu        = New-Object System.Windows.Controls.ContextMenu
    $miRemove       = New-Object System.Windows.Controls.MenuItem
    $miRemove.Header = "Remove entry"
    $miRemove.Tag    = [PSCustomObject]@{ Entry = $Entry; Border = $border }
    $miRemove.Add_Click({
        param($mi, $e)
        $t = $mi.Tag
        $script:hostsEntries.Remove($t.Entry) | Out-Null
        $script:hostsLines.Remove($t.Entry)   | Out-Null
        $hostsEntriesPanel.Children.Remove($t.Border)
        $hostsStatusText.Text = "$($script:hostsEntries.Count) entries  (unsaved)"
        $hostsStatusText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "WarningBrush")
    })
    $ctxMenu.Items.Add($miRemove) | Out-Null
    $border.ContextMenu = $ctxMenu

    $grid.Children.Add($cb)          | Out-Null
    $grid.Children.Add($ipText)      | Out-Null
    $grid.Children.Add($hostText)    | Out-Null
    $grid.Children.Add($commentText) | Out-Null
    $border.Child = $grid
    return $border
}

# -- Rebuild the entries panel ------------------------------------
function Refresh-HostsPanel {
    $hostsEntriesPanel.Children.Clear()
    $alt = $false
    foreach ($entry in $script:hostsEntries) {
        $hostsEntriesPanel.Children.Add((New-HostsRow -Entry $entry -Alternate $alt)) | Out-Null
        $alt = !$alt
    }
    $hostsStatusText.Text = "$($script:hostsEntries.Count) entries"
    $hostsStatusText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
}

# -- Load from disk -----------------------------------------------
function Load-HostsEntries {
    try {
        $script:hostsLines   = Read-HostsFile
        $script:hostsEntries = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($l in $script:hostsLines) { if ($l.IsEntry) { $script:hostsEntries.Add($l) } }
        Refresh-HostsPanel
    } catch {
        $hostsStatusText.Text = "Error loading: $_"
        $hostsStatusText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "DangerBrush")
    }
}

# -- Write entries back to disk -----------------------------------
function Save-HostsFile {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Show-ThemedDialog "Administrator privileges are required to modify the hosts file.`nRestart Scy as Administrator." "Permission denied" "OK" "Warning" | Out-Null
        return
    }

    try {
        $out = foreach ($l in $script:hostsLines) {
            # Untouched lines go back byte-for-byte; only new or toggled entries are reformatted.
            if (-not $l.IsEntry -or ($null -ne $l.Raw -and $l.Enabled -eq $l.OrigEnabled)) { $l.Raw; continue }
            $line = "{0,-20}{1}" -f $l.IP, $l.Host
            if ($l.Comment) { $line += "  # $($l.Comment)" }
            if (-not $l.Enabled) { $line = "# $line" }
            $line
        }
        if (Test-Path $hostsPath) { Copy-Item $hostsPath "$hostsPath.scy.bak" -Force }
        # No BOM: some tools misread a BOM'd first line of the hosts file.
        [System.IO.File]::WriteAllLines($hostsPath, [string[]]@($out), (New-Object System.Text.UTF8Encoding($false)))
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        Load-HostsEntries
        $hostsStatusText.Text = "Saved (backup: hosts.scy.bak)"
        $hostsStatusText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "SuccessBrush")
    } catch {
        $hostsStatusText.Text = "Save failed: $_"
        $hostsStatusText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "DangerBrush")
    }
}

# -- Placeholder text ---------------------------------------------
$hostsNewIP.Add_GotFocus({       (Find "HostsNewIPPlaceholder").Visibility      = "Collapsed" })
$hostsNewIP.Add_LostFocus({      if (-not $hostsNewIP.Text)      { (Find "HostsNewIPPlaceholder").Visibility      = "Visible" } })
$hostsNewHost.Add_GotFocus({     (Find "HostsNewHostPlaceholder").Visibility    = "Collapsed" })
$hostsNewHost.Add_LostFocus({    if (-not $hostsNewHost.Text)    { (Find "HostsNewHostPlaceholder").Visibility    = "Visible" } })
$hostsNewComment.Add_GotFocus({  (Find "HostsNewCommentPlaceholder").Visibility = "Collapsed" })
$hostsNewComment.Add_LostFocus({ if (-not $hostsNewComment.Text) { (Find "HostsNewCommentPlaceholder").Visibility = "Visible" } })

# -- Button handlers ----------------------------------------------
(Find "BtnHostsReload").Add_Click({ Load-HostsEntries })
(Find "BtnHostsSave").Add_Click({   Save-HostsFile    })

(Find "BtnHostsAddEntry").Add_Click({
    $hostsAddPanel.Visibility = if ($hostsAddPanel.Visibility -eq "Collapsed") { "Visible" } else { "Collapsed" }
})

(Find "BtnHostsConfirmAdd").Add_Click({
    $ip       = $hostsNewIP.Text.Trim()
    $hostname = $hostsNewHost.Text.Trim()
    $comment  = $hostsNewComment.Text.Trim()

    if (-not $ip -or -not $hostname) {
        $hostsStatusText.Text = "IP address and hostname are required"
        $hostsStatusText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "DangerBrush")
        return
    }
    if (-not (Test-HostsIp $ip) -or $hostname.Contains('#')) {
        $hostsStatusText.Text = "Enter a valid IPv4/IPv6 address and hostname"
        $hostsStatusText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "DangerBrush")
        return
    }

    # Raw = $null marks it as new, so Save formats it instead of copying a line.
    $newEntry = @{ Raw = $null; IsEntry = $true; IP = $ip; Host = (($hostname -split '\s+') -join ' ')
                   Comment = $comment; Enabled = $true; OrigEnabled = $true }
    $script:hostsEntries.Add($newEntry) | Out-Null
    $script:hostsLines.Add($newEntry)   | Out-Null

    $hostsNewIP.Text      = ""
    $hostsNewHost.Text    = ""
    $hostsNewComment.Text = ""
    (Find "HostsNewIPPlaceholder").Visibility      = "Visible"
    (Find "HostsNewHostPlaceholder").Visibility    = "Visible"
    (Find "HostsNewCommentPlaceholder").Visibility = "Visible"
    $hostsAddPanel.Visibility = "Collapsed"

    Refresh-HostsPanel
    $hostsStatusText.Text = "$($script:hostsEntries.Count) entries  (unsaved)"
    $hostsStatusText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "WarningBrush")
})

(Find "BtnHostsCancelAdd").Add_Click({ $hostsAddPanel.Visibility = "Collapsed" })

# -- Show admin warning if not elevated ---------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    (Find "HostsAdminBanner").Visibility = "Visible"
    (Find "BtnHostsSave").IsEnabled      = $false
}

# -- Initial load -------------------------------------------------
# Deferred to first Network-tab visit (Invoke-ScyTabInit in Scy.ps1).
# Load-HostsEntries
