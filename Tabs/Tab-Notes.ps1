# ── Tools sub-navigation ──────────────────────────────────────────
# (Software Export moved to Apps > Installed)
$script:toolsNavLabels = @("QR Code", "Notes", "File Hashing", "Passwords")

$toolsSectionQRCode      = Find "ToolsSection_QRCode"
$toolsSectionNotes       = Find "ToolsSection_Notes"
$toolsSectionHashing     = Find "ToolsSection_Hashing"
$toolsSectionPasswordGen = Find "ToolsSection_PasswordGen"

$script:toolsSections   = @($toolsSectionQRCode, $toolsSectionNotes, $toolsSectionHashing, $toolsSectionPasswordGen)

function Set-ToolsSubNav {
    param([int]$Index)
    if ($Index -lt 0 -or $Index -ge $script:toolsSections.Count) { $Index = 0 }
    $script:toolsSubNavIndex = $Index
    for ($i = 0; $i -lt $script:toolsSections.Count; $i++) {
        $script:toolsSections[$i].Visibility = if ($i -eq $Index) { "Visible" } else { "Collapsed" }
    }
    Build-Rail -Panel (Find "ToolsRail") -Labels $script:toolsNavLabels `
               -ActiveIndex $Index -OnSelect { param($i) Set-ToolsSubNav $i }
}

Set-ToolsSubNav 0

# ── Quick Notes / Scratchpad ─────────────────────────────────────
$notesTextBox    = Find "NotesTextBox"
$notesPlaceholder = Find "NotesPlaceholder"
$notesSaveStatus = Find "NotesSaveStatus"
$notesCharCount  = Find "NotesCharCount"
$btnNotesClear   = Find "BtnNotesClear"
$btnNotesPreview = Find "BtnNotesPreview"
$notesPreview    = Find "NotesPreview"
if ($null -eq $script:notesPreviewMode) { $script:notesPreviewMode = $false }

$notesTabsPanel  = Find "NotesTabsPanel"

# ── Storage: one Markdown file per note ──────────────────────────
# %APPDATA%\Scy\notes\<name>.md (see "User data folder" in Scy.ps1). The single
# notes.txt of older versions becomes the first note, "Notes".
$script:notesDir     = Join-Path $script:dataDir "notes"
$script:currentNote  = $null
$script:notesLoading = $false   # true while a note is loaded into the editor (not a user edit)

function Get-NoteNames {
    if (-not (Test-Path -LiteralPath $script:notesDir)) { return @() }
    @(Get-ChildItem -LiteralPath $script:notesDir -Filter "*.md" -File -ErrorAction SilentlyContinue |
      Sort-Object CreationTimeUtc, Name | ForEach-Object { $_.BaseName })
}

function Get-NotePath {
    param([string]$Name)
    Join-Path $script:notesDir ($Name + ".md")
}

# Turn user input into a usable, unused note name ($null if nothing usable is left).
function Resolve-NoteName {
    param([string]$Name, [string]$Except)
    $clean = ($Name -replace '[\\/:*?"<>|]', '').Trim().TrimEnd('.')
    if (-not $clean) { return $null }
    $existing = @(Get-NoteNames | Where-Object { $_ -ne $Except })
    $candidate = $clean; $n = 2
    while ($existing -contains $candidate) { $candidate = "$clean ($n)"; $n++ }
    return $candidate
}

function Initialize-Notes {
    if (-not (Test-Path -LiteralPath $script:notesDir)) { New-Item -ItemType Directory -Path $script:notesDir -Force | Out-Null }
    $legacy = Join-Path $script:dataDir "notes.txt"
    if ((Test-Path -LiteralPath $legacy) -and @(Get-NoteNames).Count -eq 0) {
        try { Move-Item -LiteralPath $legacy -Destination (Get-NotePath "Notes") -ErrorAction Stop } catch {}
    }
    if (@(Get-NoteNames).Count -eq 0) {
        [System.IO.File]::WriteAllText((Get-NotePath "Notes"), "", (New-Object System.Text.UTF8Encoding($false)))
    }
    $names = @(Get-NoteNames)
    $start = if ($script:notesActive -and ($names -contains $script:notesActive)) { $script:notesActive } else { $names[0] }
    Open-Note $start
}

# Load a note into the editor (saving any pending edits of the current one first).
function Open-Note {
    param([string]$Name)
    if ($script:notesSaveTimer.IsEnabled) { Save-NotesFile }
    $text = ""
    try { $text = [System.IO.File]::ReadAllText((Get-NotePath $Name), [System.Text.Encoding]::UTF8) } catch {}
    $script:currentNote = $Name
    $script:notesLoading = $true
    $notesTextBox.Text = $text
    $script:notesLoading = $false
    $notesPlaceholder.Visibility = if ($text -or $notesPreview.Visibility -eq "Visible") { "Collapsed" } else { "Visible" }
    if ($notesPreview.Visibility -eq "Visible") { $notesPreview.Document = ConvertTo-NotesFlowDocument $text }
    Update-NotesCharCount
    if ($script:notesActive -ne $Name) {
        $script:notesActive = $Name
        if (Get-Command Save-Settings -ErrorAction SilentlyContinue) { Save-Settings }
    }
    Show-NoteTabs
}

function Show-NoteTabs {
    $notesTabsPanel.Children.Clear()
    foreach ($name in @(Get-NoteNames)) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = $name
        $btn.Tag     = $name
        $btn.Style   = $window.Resources["SecondaryButton"]
        $btn.Margin  = [System.Windows.Thickness]::new(0, 0, 6, 6)
        $btn.ToolTip = "Right-click to rename or delete"
        if ($name -eq $script:currentNote) {
            $btn.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "AccentBrush")
            $btn.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "AccentBrush")
        }
        $btn.Add_Click({ param($s, $e) if ($s.Tag -ne $script:currentNote) { Open-Note $s.Tag } })

        $menu = New-Object System.Windows.Controls.ContextMenu
        $miRename = New-Object System.Windows.Controls.MenuItem
        $miRename.Header = "Rename..."
        $miRename.Tag    = $name
        $miRename.Add_Click({ param($s, $e) Rename-Note $s.Tag })
        $miDelete = New-Object System.Windows.Controls.MenuItem
        $miDelete.Header = "Delete"
        $miDelete.Tag    = $name
        $miDelete.Add_Click({ param($s, $e) Remove-Note $s.Tag })
        $menu.Items.Add($miRename) | Out-Null
        $menu.Items.Add($miDelete) | Out-Null
        $btn.ContextMenu = $menu

        $notesTabsPanel.Children.Add($btn) | Out-Null
    }

    $newBtn = New-Object System.Windows.Controls.Button
    $newBtn.Content = "+ New"
    $newBtn.Style   = $window.Resources["SecondaryButton"]
    $newBtn.Margin  = [System.Windows.Thickness]::new(0, 0, 6, 6)
    $newBtn.Add_Click({ New-Note })
    $notesTabsPanel.Children.Add($newBtn) | Out-Null
}

function New-Note {
    $suggest = Resolve-NoteName ("Note " + (@(Get-NoteNames).Count + 1))
    $raw = Show-ThemedInput -Prompt "Name for the new note:" -Title "New note" -Default $suggest
    if ([string]::IsNullOrWhiteSpace($raw)) { return }
    $name = Resolve-NoteName $raw
    if (-not $name) { Show-ThemedDialog "That name can't be used for a note." "New note" "OK" "Warning" | Out-Null; return }
    [System.IO.File]::WriteAllText((Get-NotePath $name), "", (New-Object System.Text.UTF8Encoding($false)))
    Open-Note $name
    $notesTextBox.Focus() | Out-Null
}

function Rename-Note {
    param([string]$Name)
    $raw = Show-ThemedInput -Prompt "Rename '$Name' to:" -Title "Rename note" -Default $Name
    if ([string]::IsNullOrWhiteSpace($raw)) { return }
    $new = Resolve-NoteName $raw -Except $Name
    if (-not $new -or $new -eq $Name) { return }
    if ($Name -eq $script:currentNote -and $script:notesSaveTimer.IsEnabled) { Save-NotesFile }
    try {
        Move-Item -LiteralPath (Get-NotePath $Name) -Destination (Get-NotePath $new) -ErrorAction Stop
    } catch {
        Show-ThemedDialog "Couldn't rename the note:`n$($_.Exception.Message)" "Rename note" "OK" "Error" | Out-Null
        return
    }
    if ($Name -eq $script:currentNote) { $script:currentNote = $new; $script:notesActive = $new; Save-Settings }
    Show-NoteTabs
}

function Remove-Note {
    param([string]$Name)
    $r = Show-ThemedDialog "Delete the note '$Name'? This cannot be undone." "Delete note" "YesNo" "Warning"
    if ($r -ne "Yes") { return }
    $script:notesSaveTimer.Stop()   # don't write the deleted note back
    try { Remove-Item -LiteralPath (Get-NotePath $Name) -Force -ErrorAction Stop } catch {
        Show-ThemedDialog "Couldn't delete the note:`n$($_.Exception.Message)" "Delete note" "OK" "Error" | Out-Null
        return
    }
    $names = @(Get-NoteNames)
    if ($names.Count -eq 0) {
        # Always keep one note to type into
        [System.IO.File]::WriteAllText((Get-NotePath "Notes"), "", (New-Object System.Text.UTF8Encoding($false)))
        $names = @("Notes")
    }
    if ($Name -eq $script:currentNote) { Open-Note $names[0] } else { Show-NoteTabs }
}

# ── Placeholder behavior ─────────────────────────────────────────
$notesTextBox.Add_GotFocus({  $notesPlaceholder.Visibility = "Collapsed" })
$notesTextBox.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($notesTextBox.Text)) {
        $notesPlaceholder.Visibility = "Visible"
    }
})

# ── Update char count ────────────────────────────────────────────
function Update-NotesCharCount {
    $len = $notesTextBox.Text.Length
    $notesCharCount.Text = "$len character$(if ($len -ne 1) { 's' })"
}

Update-NotesCharCount

# ── Auto-save with debounce ──────────────────────────────────────
function Save-NotesFile {
    $script:notesSaveTimer.Stop()
    if (-not $script:currentNote) { return }
    try {
        if (-not (Test-Path -LiteralPath $script:notesDir)) { New-Item -ItemType Directory -Path $script:notesDir -Force | Out-Null }
        [System.IO.File]::WriteAllText((Get-NotePath $script:currentNote), $notesTextBox.Text, (New-Object System.Text.UTF8Encoding($false)))
        $notesSaveStatus.Text = "Saved"
        # Fade out the status after a moment
        $fadeTimer = New-Object System.Windows.Threading.DispatcherTimer
        $fadeTimer.Interval = [TimeSpan]::FromSeconds(2)
        $fadeTimer.Add_Tick({
            $args[0].Stop()
            if ($notesSaveStatus.Text -eq "Saved") {
                $notesSaveStatus.Text = ""
            }
        })
        $fadeTimer.Start()
    } catch {
        $notesSaveStatus.Text = "Save failed"
    }
}

$script:notesSaveTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:notesSaveTimer.Interval = [TimeSpan]::FromMilliseconds(800)
$script:notesSaveTimer.Add_Tick({ Save-NotesFile })

# Flush a pending debounced save so edits made just before closing aren't lost.
$window.Add_Closing({ if ($script:notesSaveTimer.IsEnabled) { Save-NotesFile } })

$notesTextBox.Add_TextChanged({
    Update-NotesCharCount
    if ($script:notesLoading) { return }   # a note being opened, not an edit
    $notesSaveStatus.Text = ""
    $script:notesSaveTimer.Stop()
    $script:notesSaveTimer.Start()
})

# ── Markdown preview ─────────────────────────────────────────────
function ConvertTo-NotesFlowDocument {
    param([string]$Markdown)

    $doc = New-Object System.Windows.Documents.FlowDocument
    $doc.PagePadding = [System.Windows.Thickness]::new(4)

    $fgBrush      = $window.Resources["FgBrush"]
    $mutedBrush   = $window.Resources["MutedText"]
    $accentBrush  = $window.Resources["AccentBrush"]
    $codeBgBrush  = $window.Resources["InputBgBrush"]
    $monoFont     = New-Object System.Windows.Media.FontFamily("IBM Plex Mono, Cascadia Mono, Consolas")
    $defaultFont  = New-Object System.Windows.Media.FontFamily("IBM Plex Sans, Segoe UI")

    $lines = $Markdown -split "`n"
    $inCodeBlock = $false
    $codeLines = @()

    foreach ($line in $lines) {
        $line = $line.TrimEnd("`r")

        # Fenced code block toggle
        if ($line -match '^```') {
            if ($inCodeBlock) {
                # Close code block
                $para = New-Object System.Windows.Documents.Paragraph
                $para.FontFamily = $monoFont
                $para.FontSize = 11
                $para.Foreground = $mutedBrush
                $para.Background = $codeBgBrush
                $para.Padding = [System.Windows.Thickness]::new(8,6,8,6)
                $para.Margin = [System.Windows.Thickness]::new(0,4,0,4)
                $run = New-Object System.Windows.Documents.Run($codeLines -join "`r`n")
                $para.Inlines.Add($run)
                $doc.Blocks.Add($para)
                $codeLines = @()
                $inCodeBlock = $false
            } else {
                $inCodeBlock = $true
            }
            continue
        }

        if ($inCodeBlock) {
            $codeLines += $line
            continue
        }

        # Horizontal rule
        if ($line -match '^-{3,}\s*$') {
            $para = New-Object System.Windows.Documents.Paragraph
            $para.Margin = [System.Windows.Thickness]::new(0,6,0,6)
            $border = New-Object System.Windows.Controls.Border
            $border.BorderThickness = [System.Windows.Thickness]::new(0,1,0,0)
            $border.BorderBrush = $mutedBrush
            $border.Width = [double]::NaN
            $border.HorizontalAlignment = "Stretch"
            $border.Margin = [System.Windows.Thickness]::new(0,4,0,4)
            $container = New-Object System.Windows.Documents.InlineUIContainer($border)
            $para.Inlines.Add($container)
            $doc.Blocks.Add($para)
            continue
        }

        # Headings
        $para = New-Object System.Windows.Documents.Paragraph
        $para.Foreground = $fgBrush
        $para.FontFamily = $defaultFont
        $para.Margin = [System.Windows.Thickness]::new(0,2,0,2)

        $isHeading = $false
        if ($line -match '^###\s+(.+)') {
            $line = $Matches[1]
            $para.FontSize = 14; $para.FontWeight = "SemiBold"
            $para.Margin = [System.Windows.Thickness]::new(0,6,0,3)
            $isHeading = $true
        } elseif ($line -match '^##\s+(.+)') {
            $line = $Matches[1]
            $para.FontSize = 16; $para.FontWeight = "Bold"
            $para.Margin = [System.Windows.Thickness]::new(0,8,0,4)
            $isHeading = $true
        } elseif ($line -match '^#\s+(.+)') {
            $line = $Matches[1]
            $para.FontSize = 20; $para.FontWeight = "Bold"
            $para.Foreground = $accentBrush
            $para.Margin = [System.Windows.Thickness]::new(0,10,0,5)
            $isHeading = $true
        }

        # Bullet list
        $isBullet = $false
        if (-not $isHeading -and $line -match '^[\-\*]\s+(.+)') {
            $line = $Matches[1]
            $isBullet = $true
            $para.Margin = [System.Windows.Thickness]::new(16,1,0,1)
            $bullet = New-Object System.Windows.Documents.Run([char]0x2022 + "  ")
            $bullet.Foreground = $accentBrush
            $para.Inlines.Add($bullet)
        }

        # Inline formatting: bold, italic, inline code
        $remaining = $line
        while ($remaining.Length -gt 0) {
            # Single-quoted: each backtick here is a literal Markdown backtick.
            if ($remaining -match '^`(.+?)`') {
                $run = New-Object System.Windows.Documents.Run($Matches[1])
                $run.FontFamily = $monoFont
                $run.FontSize = 11
                $run.Background = $codeBgBrush
                $para.Inlines.Add($run)
                $remaining = $remaining.Substring($Matches[0].Length)
            } elseif ($remaining -match '^\*\*(.+?)\*\*') {
                $bold = New-Object System.Windows.Documents.Bold
                $bold.Inlines.Add((New-Object System.Windows.Documents.Run($Matches[1])))
                $para.Inlines.Add($bold)
                $remaining = $remaining.Substring($Matches[0].Length)
            } elseif ($remaining -match '^\*(.+?)\*') {
                $italic = New-Object System.Windows.Documents.Italic
                $italic.Inlines.Add((New-Object System.Windows.Documents.Run($Matches[1])))
                $para.Inlines.Add($italic)
                $remaining = $remaining.Substring($Matches[0].Length)
            } elseif ($remaining -match '^([^`\*]+)') {
                $para.Inlines.Add((New-Object System.Windows.Documents.Run($Matches[1])))
                $remaining = $remaining.Substring($Matches[0].Length)
            } else {
                # Single special char, emit it and move on
                $para.Inlines.Add((New-Object System.Windows.Documents.Run($remaining[0])))
                $remaining = $remaining.Substring(1)
            }
        }

        $doc.Blocks.Add($para)
    }

    # Close unclosed code block
    if ($inCodeBlock -and $codeLines.Count -gt 0) {
        $para = New-Object System.Windows.Documents.Paragraph
        $para.FontFamily = $monoFont
        $para.FontSize = 11
        $para.Foreground = $mutedBrush
        $para.Background = $codeBgBrush
        $para.Padding = [System.Windows.Thickness]::new(8,6,8,6)
        $run = New-Object System.Windows.Documents.Run($codeLines -join "`r`n")
        $para.Inlines.Add($run)
        $doc.Blocks.Add($para)
    }

    return $doc
}

$btnNotesPreview.Add_Click({
    $entering = $notesPreview.Visibility -ne "Visible"
    $script:notesPreviewMode = $entering
    if ($entering) {
        $notesPreview.Document       = ConvertTo-NotesFlowDocument $notesTextBox.Text
        $notesTextBox.Visibility     = "Collapsed"
        $notesPlaceholder.Visibility = "Collapsed"
        $notesPreview.Visibility     = "Visible"
        $btnNotesPreview.Content     = "Edit"
    } else {
        $notesPreview.Visibility     = "Collapsed"
        $notesTextBox.Visibility     = "Visible"
        if ([string]::IsNullOrWhiteSpace($notesTextBox.Text)) {
            $notesPlaceholder.Visibility = "Visible"
        }
        $btnNotesPreview.Content     = "Preview"
    }
    Save-Settings
})

# Load the notes (migrating an old notes.txt) and open the last-used one
Initialize-Notes

# Restore saved preview mode on startup
if ($script:notesPreviewMode) {
    $notesPreview.Document       = ConvertTo-NotesFlowDocument $notesTextBox.Text
    $notesTextBox.Visibility     = "Collapsed"
    $notesPlaceholder.Visibility = "Collapsed"
    $notesPreview.Visibility     = "Visible"
    $btnNotesPreview.Content     = "Edit"
}

# ── Delete button: deletes the open note (the last one is just emptied) ──
$btnNotesClear.Add_Click({
    if ($script:currentNote) { Remove-Note $script:currentNote }
})
