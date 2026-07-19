# Built-in theme palettes — the cy-design system (shared across the "cy" family:
# Acy, Ncy, Scy). Single source of truth for the splash screen (Scy.ps1) and the
# runtime theme system (Tabs/Tab-Settings.ps1).
#
# cy-design uses ONE first-class Light + ONE Dark theme built on a zinc neutral
# ramp. The accent is chosen SEPARATELY by the user (see $AccentPresets) and
# overlaid onto the base by Apply-Theme — it is not baked into the palette.
# The Custom theme is user state and lives in Tab-Settings.ps1.

$script:BuiltinThemes = [ordered]@{
    # ── Light (zinc) ──────────────────────────────────────────────
    Light = @{
        WindowBg       = "#ffffff"   # title bar / window frame (surface)
        AppBg          = "#f4f4f5"   # app background, under the dots
        GridDot        = "#0F000000" # dotted "graph-paper" ground (~6% black)
        Surface        = "#ffffff"   # cards, bars, sheets
        Surface2       = "#f7f7f8"   # inset / rail / quiet hover
        HoverSurface   = "#f0f0f2"   # row hover / pressed
        FgBrush        = "#18181b"   # primary text
        SubText        = "#52525b"   # secondary text
        MutedText      = "#71717a"   # muted text, icons
        WinCtrlFg      = "#71717a"   # window control glyphs
        Border         = "#e4e4e7"   # hairlines
        BorderStrong   = "#d4d4d8"   # inputs, scrollbar, back button
        ScrollThumb    = "#d4d4d8"
        InputBg        = "#f7f7f8"   # inset field fill
        AccentContrast = "#ffffff"   # text/icon on accent
        Success        = "#16a34a"
        Warning        = "#d97706"
        Danger         = "#dc2626"
        # Accent is overlaid from the chosen preset; default shown for reference.
        Accent         = "#7c3aed"
    }
    # ── Dark (zinc) ───────────────────────────────────────────────
    Dark = @{
        WindowBg       = "#202024"
        AppBg          = "#161619"
        GridDot        = "#0AFFFFFF" # ~4% white
        Surface        = "#202024"
        Surface2       = "#27272c"
        HoverSurface   = "#2e2e34"
        FgBrush        = "#f4f4f5"
        SubText        = "#c4c4cd"
        MutedText      = "#a8a8b2"
        WinCtrlFg      = "#a8a8b2"
        Border         = "#313139"
        BorderStrong   = "#43434d"
        ScrollThumb    = "#43434d"
        InputBg        = "#27272c"
        AccentContrast = "#ffffff"
        Success        = "#4ade80"
        Warning        = "#fbbf24"
        Danger         = "#f87171"
        Accent         = "#8b5cf6"
    }
}

# User-selectable accent presets (cy-design §2). Each has a Light + Dark hex.
# purple is the default. Overlaid onto the base palette by Apply-Theme.
$script:AccentPresets = [ordered]@{
    purple = @{ Light = "#7c3aed"; Dark = "#8b5cf6" }
    blue   = @{ Light = "#2563eb"; Dark = "#3b82f6" }
    green  = @{ Light = "#059669"; Dark = "#10b981" }
    pink   = @{ Light = "#db2777"; Dark = "#ec4899" }
    orange = @{ Light = "#ea580c"; Dark = "#f97316" }
    teal   = @{ Light = "#0d9488"; Dark = "#14b8a6" }
}

# Read the Windows apps light/dark preference. Returns "Light" or "Dark".
function script:Get-WindowsThemeMode {
    try {
        $v = Get-ItemPropertyValue `
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" `
            "AppsUseLightTheme"
        if ($v -eq 1) { return "Light" } else { return "Dark" }
    } catch { return "Dark" }
}

# Resolve a stored ThemeMode ("System"|"Light"|"Dark") to a concrete "Light"/"Dark".
function script:Resolve-ThemeMode {
    param([string]$Mode)
    switch ($Mode) {
        "Light" { "Light" }
        "Dark"  { "Dark" }
        default { Get-WindowsThemeMode }   # "System" or unset → follow Windows
    }
}
