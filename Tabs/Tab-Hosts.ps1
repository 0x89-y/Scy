# ==================================================================
#  HOSTS FILE EDITOR TAB
#
#  Visual editor for C:\Windows\System32\drivers\etc\hosts
#  - Toggle entries on/off without deleting them (saved as # comment)
#  - Add / remove custom entries
#  - Save requires Administrator privileges
# ==================================================================

$hostsPath         = "C:\Windows\System32\drivers\etc\hosts"
$hostsEntriesPanel = Find "HostsEntriesPanel"
$hostsStatusText   = Find "HostsStatusText"
$hostsAddPanel     = Find "HostsAddPanel"
$hostsNewIP        = Find "HostsNewIP"
$hostsNewHost      = Find "HostsNewHost"
$hostsNewComment   = Find "HostsNewComment"

$script:hostsEntries = [System.Collections.Generic.List[hashtable]]::new()

# -- Parse the hosts file -----------------------------------------
function Read-HostsFile {
    $entries = [System.Collections.Generic.List[hashtable]]::new()
    if (-not (Test-Path $hostsPath)) { return $entries }

    $lines = Get-Content -Path $hostsPath -Encoding UTF8 -ErrorAction Stop
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "") { continue }

        $disabled = $false
        $content  = $trimmed

        if ($content.StartsWith("#")) {
            # Could be a disabled entry: # 0.0.0.0 hostname
            $inner = $content.Substring(1).Trim()
            if ($inner -match '^(\S+)\s+(\S+)') {
                $ip = $Matches[1]
                if ($ip -match '^\d{1,3}(?:\.\d{1,3}){3}$' -or $ip -match '^::') {
                    $disabled = $true
                    $content  = $inner
                } else { continue }
            } else { continue }
        }

        # Match: IP  hostname  [# comment]
        if ($content -match '^(\S+)\s+(\S+)(?:\s+#\s*(.*))?$') {
            $entries.Add(@{
                IP      = $Matches[1]
                Host    = $Matches[2]
                Comment = if ($Matches[3]) { $Matches[3].Trim() } else { "" }
                Enabled = !$disabled
            }) | Out-Null
        }
    }
    return $entries
}

# -- Build a single row for an entry ------------------------------
function New-HostsRow {
    param($Entry, [bool]$Alternate = $false)

    $border = New-Object System.Windows.Controls.Border
    $border.Background      = if ($Alternate) { $window.Resources["SurfaceBrush"] } else { $window.Resources["InputBgBrush"] }
    $border.Padding         = [System.Windows.Thickness]::new(14, 7, 14, 7)
    $border.Margin          = [System.Windows.Thickness]::new(0)

    $grid = New-Object System.Windows.Controls.Grid
    foreach ($spec in @(50, 150, "star", "star", "auto")) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = switch ($spec) {
            "star" { New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star) }
            "auto" { [System.Windows.GridLength]::Auto }
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

    # Col 4 - remove button
    $removeBtn                   = New-Object System.Windows.Controls.Button
    $removeBtn.Content           = "x"
    $removeBtn.FontSize          = 11
    $removeBtn.Padding           = [System.Windows.Thickness]::new(8, 3, 8, 3)
    $removeBtn.Style             = $window.Resources["SecondaryButton"]
    $removeBtn.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $removeBtn.Tag               = [PSCustomObject]@{ Entry = $Entry; Border = $border }
    [System.Windows.Controls.Grid]::SetColumn($removeBtn, 4)
    $removeBtn.Add_Click({
        param($btn, $e)
        $t = $btn.Tag
        $script:hostsEntries.Remove($t.Entry) | Out-Null
        $hostsEntriesPanel.Children.Remove($t.Border)
        $hostsStatusText.Text = "$($script:hostsEntries.Count) entries  (unsaved)"
        $hostsStatusText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "WarningBrush")
    })

    $grid.Children.Add($cb)          | Out-Null
    $grid.Children.Add($ipText)      | Out-Null
    $grid.Children.Add($hostText)    | Out-Null
    $grid.Children.Add($commentText) | Out-Null
    $grid.Children.Add($removeBtn)   | Out-Null
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
        $script:hostsEntries = [System.Collections.Generic.List[hashtable]](Read-HostsFile)
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
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("# Hosts file - managed by Scy")
        $lines.Add("")
        foreach ($entry in $script:hostsEntries) {
            $line = "{0,-20}{1}" -f $entry.IP, $entry.Host
            if ($entry.Comment) { $line += "  # $($entry.Comment)" }
            if (-not $entry.Enabled) { $line = "# $line" }
            $lines.Add($line)
        }
        Set-Content -Path $hostsPath -Value $lines -Encoding UTF8 -Force
        Invoke-ConfirmSound
        $hostsStatusText.Text = "Saved"
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

    $script:hostsEntries.Add(@{ IP=$ip; Host=$hostname; Comment=$comment; Enabled=$true }) | Out-Null

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
Load-HostsEntries
