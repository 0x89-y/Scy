# ── Tools sub-navigation ──────────────────────────────────────────
$toolsNavQRCode = Find "ToolsNav_QRCode"
$toolsNavNotes  = Find "ToolsNav_Notes"

$toolsSectionQRCode = Find "ToolsSection_QRCode"
$toolsSectionNotes  = Find "ToolsSection_Notes"

$script:toolsNavButtons = @($toolsNavQRCode, $toolsNavNotes)
$script:toolsSections   = @($toolsSectionQRCode, $toolsSectionNotes)

function Set-ToolsSubNav {
    param([int]$Index)
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

$toolsNavQRCode.Add_Click({ Set-ToolsSubNav 0 })
$toolsNavNotes.Add_Click({  Set-ToolsSubNav 1 })

# ── Quick Notes / Scratchpad ─────────────────────────────────────
$notesTextBox    = Find "NotesTextBox"
$notesPlaceholder = Find "NotesPlaceholder"
$notesSaveStatus = Find "NotesSaveStatus"
$notesCharCount  = Find "NotesCharCount"
$btnNotesClear   = Find "BtnNotesClear"

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
