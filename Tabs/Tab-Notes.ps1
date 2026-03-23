# ── Tools sub-navigation ──────────────────────────────────────────
$toolsNavQRCode  = Find "ToolsNav_QRCode"
$toolsNavNotes   = Find "ToolsNav_Notes"
$toolsNavExport  = Find "ToolsNav_Export"
$toolsNavHashing = Find "ToolsNav_Hashing"

$toolsSectionQRCode  = Find "ToolsSection_QRCode"
$toolsSectionNotes   = Find "ToolsSection_Notes"
$toolsSectionExport  = Find "ToolsSection_Export"
$toolsSectionHashing = Find "ToolsSection_Hashing"

$script:toolsNavButtons = @($toolsNavQRCode, $toolsNavNotes, $toolsNavExport, $toolsNavHashing)
$script:toolsSections   = @($toolsSectionQRCode, $toolsSectionNotes, $toolsSectionExport, $toolsSectionHashing)

function Set-ToolsSubNav {
    param([int]$Index)
    $script:toolsSubNavIndex = $Index
    for ($i = 0; $i -lt $script:toolsSections.Count; $i++) {
        $script:toolsSections[$i].Visibility = if ($i -eq $Index) { "Visible" } else { "Collapsed" }
        $btn = $script:toolsNavButtons[$i]
        if ($i -eq $Index) {
            $btn.Foreground  = $window.Resources["FgBrush"]
            $btn.BorderBrush = $window.Resources["AccentBrush"]
        } else {
            $btn.Foreground  = $window.Resources["MutedText"]
            $btn.BorderBrush = $window.Resources["BorderBrush"]
        }
    }
}

Set-ToolsSubNav 0

$toolsNavQRCode.Add_Click({  Set-ToolsSubNav 0 })
$toolsNavNotes.Add_Click({   Set-ToolsSubNav 1 })
$toolsNavExport.Add_Click({  Set-ToolsSubNav 2 })
$toolsNavHashing.Add_Click({ Set-ToolsSubNav 3 })

# ── Quick Notes / Scratchpad ─────────────────────────────────────
$notesTextBox    = Find "NotesTextBox"
$notesPlaceholder = Find "NotesPlaceholder"
$notesSaveStatus = Find "NotesSaveStatus"
$notesCharCount  = Find "NotesCharCount"
$btnNotesClear   = Find "BtnNotesClear"
$btnNotesPreview = Find "BtnNotesPreview"
$notesPreview    = Find "NotesPreview"
if ($null -eq $script:notesPreviewMode) { $script:notesPreviewMode = $false }

$script:notesFilePath = Join-Path $PSScriptRoot "..\notes.txt"

# ── Load saved notes ─────────────────────────────────────────────
if (Test-Path $script:notesFilePath) {
    try {
        $saved = Get-Content $script:notesFilePath -Raw -Encoding UTF8
        if ($saved) {
            $notesTextBox.Text = $saved
            $notesPlaceholder.Visibility = "Collapsed"
        }
    } catch { }
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
$script:notesSaveTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:notesSaveTimer.Interval = [TimeSpan]::FromMilliseconds(800)
$script:notesSaveTimer.Add_Tick({
    $script:notesSaveTimer.Stop()
    try {
        $dir = Split-Path $script:notesFilePath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($script:notesFilePath, $notesTextBox.Text, [System.Text.Encoding]::UTF8)
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
})

$notesTextBox.Add_TextChanged({
    Update-NotesCharCount
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
    $monoFont     = New-Object System.Windows.Media.FontFamily("Consolas, Courier New")
    $defaultFont  = New-Object System.Windows.Media.FontFamily("Segoe UI, Arial")

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
            if ($remaining -match '^``(.+?)``') {
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

# Restore saved preview mode on startup
if ($script:notesPreviewMode) {
    $notesPreview.Document       = ConvertTo-NotesFlowDocument $notesTextBox.Text
    $notesTextBox.Visibility     = "Collapsed"
    $notesPlaceholder.Visibility = "Collapsed"
    $notesPreview.Visibility     = "Visible"
    $btnNotesPreview.Content     = "Edit"
}

# ── Clear button ─────────────────────────────────────────────────
$btnNotesClear.Add_Click({
    if ([string]::IsNullOrWhiteSpace($notesTextBox.Text)) { return }
    $result = Show-ThemedDialog "Clear all notes? This cannot be undone." "Clear Notes" "YesNo" "Warning"
    if ($result -eq "Yes") {
        $notesTextBox.Text = ""
        $notesPlaceholder.Visibility = "Visible"
        try {
            if (Test-Path $script:notesFilePath) {
                Remove-Item $script:notesFilePath -Force
            }
        } catch { }
        $notesSaveStatus.Text = "Cleared"
    }
}.GetNewClosure())
