# -- Installs Tab -------------------------------------------------------------

# Shared install progress bar (used by both the Store install path and the
# Installed sub-tab uninstall flow).
$installsProgressBorder    = Find "InstallsProgressBorder"
$installsProgressBar       = Find "InstallsProgressBar"
$installsProgressLabel     = Find "InstallsProgressLabel"

# Settings > Groups > Quick installs hosts the Import/Export buttons now.
$btnImportBundles          = Find "BtnImportBundles"
$btnExportBundles          = Find "BtnExportBundles"

# Re-entry guard for async winget install
$script:installInProgress = $false

# -- Package sub-navigation ---------------------------------------------------
# 0 = Store (Search + Quick install + Local installers, all stacked)
# 1 = Installed (uninstall surface)
# 2 = Updates
$pkgNavStore     = Find "PkgNav_Store"
$pkgNavInstalled = Find "PkgNav_Installed"
$pkgNavUpdates   = Find "PkgNav_Updates"

$pkgSectionStore     = Find "PkgSection_Store"
$pkgSectionInstalled = Find "PkgSection_Installed"
$pkgSectionUpdates   = Find "PkgSection_Updates"

$script:pkgNavButtons  = @($pkgNavStore, $pkgNavInstalled, $pkgNavUpdates)
$script:pkgSections    = @($pkgSectionStore, $pkgSectionInstalled, $pkgSectionUpdates)

function Set-PkgSubNav {
    param([int]$Index)
    if ($Index -lt 0 -or $Index -ge $script:pkgSections.Count) { $Index = 0 }
    $script:pkgSubNavIndex = $Index
    for ($i = 0; $i -lt $script:pkgSections.Count; $i++) {
        $script:pkgSections[$i].Visibility = if ($i -eq $Index) { "Visible" } else { "Collapsed" }
        $btn = $script:pkgNavButtons[$i]
        if ($i -eq $Index) {
            $btn.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "FgBrush")
            $btn.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "AccentBrush")
        } else {
            $btn.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "MutedText")
            $btn.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "BorderBrush")
        }
    }
}

# Default landing: Store
Set-PkgSubNav 0

$pkgNavStore.Add_Click({     Set-PkgSubNav 0 })
$pkgNavInstalled.Add_Click({ Set-PkgSubNav 1 })
$pkgNavUpdates.Add_Click({   Set-PkgSubNav 2 })

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

# -- Quick Install (dynamic, persisted in settings) ---------------------------
$script:quickInstalls      = [System.Collections.Generic.List[hashtable]]::new()
$script:quickBundles       = [System.Collections.Generic.List[hashtable]]::new()
$script:selectedQuickItems = [System.Collections.Generic.List[hashtable]]::new()

$script:quickInstallEditMode = $false

$script:defaultQuickCategories = @(
    "Browsers", "Communication", "Media", "Utilities", "Development", "Gaming",
    "Productivity", "Security", "Network", "Cloud & Sync", "Office"
)

# Optional fields:
#   Source      - winget source ("msstore" etc); omitted means default winget repo
#   Description - hardcoded one-liner shown instantly in the detail panel; when
#                 present, the async winget-show description does not overwrite it
$script:curatedApps = @(
    # Browsers
    @{ Name = "Firefox";                  Id = "Mozilla.Firefox";                   Category = "Browsers";       Description = "Open-source web browser from Mozilla." }
    @{ Name = "Brave";                    Id = "Brave.Brave";                       Category = "Browsers";       Description = "Chromium browser with built-in ad and tracker blocking." }
    @{ Name = "Zen";                      Id = "Zen-Team.Zen-Browser";              Category = "Browsers";       Description = "Firefox-based browser with workspaces and focus features." }
    @{ Name = "Helium";                   Id = "imputnet.helium";                   Category = "Browsers";       Description = "Lightweight Chromium fork focused on speed and privacy." }
    @{ Name = "Vivaldi";                  Id = "Vivaldi.Vivaldi";                   Category = "Browsers";       Description = "Highly customizable Chromium browser with tab stacking and built-in tools." }
    @{ Name = "LibreWolf";                Id = "LibreWolf.LibreWolf";               Category = "Browsers";       Description = "Hardened Firefox fork with privacy-first defaults." }
    @{ Name = "Tor Browser";              Id = "TorProject.TorBrowser";             Category = "Browsers";       Description = "Routes traffic through the Tor network for anonymous browsing." }

    # Communication
    @{ Name = "Discord";                  Id = "Discord.Discord";                   Category = "Communication";  Description = "Voice, video, and text chat for communities." }
    @{ Name = "Element";                  Id = "Element.Element";                   Category = "Communication";  Description = "Matrix client for end-to-end encrypted team chat." }
    @{ Name = "Signal";                   Id = "OpenWhisperSystems.Signal";         Category = "Communication";  Description = "End-to-end encrypted messenger with voice and video calls." }
    @{ Name = "Telegram";                 Id = "Telegram.TelegramDesktop";          Category = "Communication";  Description = "Cloud-based messenger with channels, bots, and large groups." }
    @{ Name = "Thunderbird";              Id = "Mozilla.Thunderbird";               Category = "Communication";  Description = "Mozilla's open-source email, calendar, and feed client." }
    @{ Name = "SimpleX Chat";             Id = "SimpleXChat.SimpleX-Desktop";       Category = "Communication";  Description = "Messenger that requires no user IDs or phone numbers." }

    # Media
    @{ Name = "VLC";                      Id = "VideoLAN.VLC";                      Category = "Media";          Description = "Plays nearly any audio and video format." }
    @{ Name = "Spotify";                  Id = "Spotify.Spotify";                   Category = "Media";          Description = "Music streaming client." }
    @{ Name = "MusicBee";                 Id = "MusicBee.MusicBee";                 Category = "Media";          Description = "Local music library player with rich tagging." }
    @{ Name = "OBS Studio";               Id = "OBSProject.OBSStudio";              Category = "Media";          Description = "Live streaming and screen recording." }
    @{ Name = "GIMP";                     Id = "GIMP.GIMP";                         Category = "Media";          Description = "Open-source raster image editor." }
    @{ Name = "Audacity";                 Id = "Audacity.Audacity";                 Category = "Media";          Description = "Multi-track audio recording and editing." }
    @{ Name = "HandBrake";                Id = "HandBrake.HandBrake";               Category = "Media";          Description = "Video transcoder for converting between formats." }
    @{ Name = "Inkscape";                 Id = "Inkscape.Inkscape";                 Category = "Media";          Description = "Vector graphics editor." }
    @{ Name = "Krita";                    Id = "KDE.Krita";                         Category = "Media";          Description = "Digital painting and illustration." }
    @{ Name = "Blender";                  Id = "BlenderFoundation.Blender";         Category = "Media";          Description = "3D modeling, animation, and rendering suite." }
    @{ Name = "mpv";                      Id = "shinchiro.mpv";                     Category = "Media";          Description = "Minimalist scriptable media player." }
    @{ Name = "Plex";                     Id = "Plex.Plex";                         Category = "Media";          Description = "Client for the Plex media server." }
    @{ Name = "Jellyfin Media Player";    Id = "Jellyfin.JellyfinMediaPlayer";      Category = "Media";          Description = "Client for the open-source Jellyfin media server." }
    @{ Name = "DaVinci Resolve";          Id = "BlackmagicDesign.DaVinciResolve";   Category = "Media";          Description = "Professional video editing and color grading." }
    @{ Name = "Emby";                     Id = "9NBLGGH4T70L";                      Category = "Media";          Source = "msstore"; Description = "Client for the Emby media server." }

    # Utilities
    @{ Name = "7-Zip";                    Id = "7zip.7zip";                         Category = "Utilities";      Description = "High-ratio file archiver." }
    @{ Name = "Notepad++";                Id = "Notepad++.Notepad++";               Category = "Utilities";      Description = "Lightweight tabbed text and code editor." }
    @{ Name = "Everything";               Id = "voidtools.Everything";              Category = "Utilities";      Description = "Instant filename search across the file system." }
    @{ Name = "PowerToys";                Id = "Microsoft.PowerToys";               Category = "Utilities";      Description = "Microsoft's set of power-user utilities for Windows." }
    @{ Name = "ShareX";                   Id = "ShareX.ShareX";                     Category = "Utilities";      Description = "Screenshot, screen recorder, and upload automation." }
    @{ Name = "qBittorrent";              Id = "qBittorrent.qBittorrent";           Category = "Utilities";      Description = "Open-source BitTorrent client." }
    @{ Name = "WizTree";                  Id = "AntibodySoftware.WizTree";          Category = "Utilities";      Description = "Fast disk space visualizer using the NTFS MFT." }
    @{ Name = "File Pilot";               Id = "FilePilot.FilePilot";               Category = "Utilities";      Description = "Modern, very fast Windows file manager." }
    @{ Name = "Ditto";                    Id = "Ditto.Ditto";                       Category = "Utilities";      Description = "Clipboard history manager." }
    @{ Name = "CrystalDiskInfo";          Id = "CrystalDewWorld.CrystalDiskInfo";   Category = "Utilities";      Description = "Drive health monitor reading S.M.A.R.T. data." }
    @{ Name = "Greenshot";                Id = "Greenshot.Greenshot";               Category = "Utilities";      Description = "Lightweight screenshot tool with annotation." }
    @{ Name = "Flow Launcher";            Id = "Flow-Launcher.Flow-Launcher";       Category = "Utilities";      Description = "Quick app and file launcher (Alfred-style)." }
    @{ Name = "AutoHotkey";               Id = "AutoHotkey.AutoHotkey";             Category = "Utilities";      Description = "Scripting language for keyboard, mouse, and UI automation." }
    @{ Name = "NanaZip";                  Id = "M2Team.NanaZip";                    Category = "Utilities";      Description = "Modern 7-Zip fork with extra format support." }
    @{ Name = "Files";                    Id = "Files-Community.Files";             Category = "Utilities";      Description = "Tabbed modern file explorer for Windows." }
    @{ Name = "Rufus";                    Id = "Rufus.Rufus";                       Category = "Utilities";      Description = "Creates bootable USB drives from ISO files." }

    # Development
    @{ Name = "Visual Studio Code";       Id = "Microsoft.VisualStudioCode";        Category = "Development";    Description = "Cross-platform code editor from Microsoft." }
    @{ Name = "Git";                      Id = "Git.Git";                           Category = "Development";    Description = "Distributed version control." }
    @{ Name = "Windows Terminal";         Id = "Microsoft.WindowsTerminal";         Category = "Development";    Description = "Modern terminal for Cmd, PowerShell, and WSL." }
    @{ Name = "Node.js LTS";              Id = "OpenJS.NodeJS.LTS";                 Category = "Development";    Description = "JavaScript runtime built on V8 (long-term-support release)." }
    @{ Name = "Python 3.12";              Id = "Python.Python.3.12";                Category = "Development";    Description = "Python interpreter and tooling." }
    @{ Name = "Docker Desktop";           Id = "Docker.DockerDesktop";              Category = "Development";    Description = "Run and manage containers on Windows." }
    @{ Name = "JetBrains Toolbox";        Id = "JetBrains.Toolbox";                 Category = "Development";    Description = "Installer and manager for JetBrains IDEs." }
    @{ Name = "Sublime Text";             Id = "SublimeHQ.SublimeText.4";           Category = "Development";    Description = "Fast multi-language code editor." }
    @{ Name = "Postman";                  Id = "Postman.Postman";                   Category = "Development";    Description = "HTTP API client for testing and team collaboration." }
    @{ Name = "Insomnia";                 Id = "Insomnia.Insomnia";                 Category = "Development";    Description = "Open-source REST, GraphQL, and gRPC API client." }
    @{ Name = "Neovim";                   Id = "Neovim.Neovim";                     Category = "Development";    Description = "Modernized Vim with embedded scripting and async plugins." }
    @{ Name = "Cursor";                   Id = "Anysphere.Cursor";                  Category = "Development";    Description = "AI-powered code editor based on VS Code." }
    @{ Name = "Zed";                      Id = "Zed.Zed";                           Category = "Development";    Description = "Fast, collaborative code editor written in Rust." }
    @{ Name = "GitHub Desktop";           Id = "GitHub.GitHubDesktop";              Category = "Development";    Description = "Visual Git client for GitHub repositories." }
    @{ Name = "GitHub CLI";               Id = "GitHub.cli";                        Category = "Development";    Description = "Command-line tool for GitHub workflows." }
    @{ Name = "DBeaver";                  Id = "dbeaver.dbeaver";                   Category = "Development";    Description = "Universal database GUI for SQL and NoSQL engines." }
    @{ Name = "MongoDB Compass";          Id = "MongoDB.Compass.Community";         Category = "Development";    Description = "Official GUI for MongoDB databases." }

    # Gaming
    @{ Name = "Steam";                    Id = "Valve.Steam";                       Category = "Gaming";         Description = "Valve's game store and library." }
    @{ Name = "Epic Games Launcher";      Id = "EpicGames.EpicGamesLauncher";       Category = "Gaming";         Description = "Game store and library from Epic." }
    @{ Name = "GOG Galaxy";               Id = "GOG.Galaxy";                        Category = "Gaming";         Description = "DRM-free game library and unified launcher." }
    @{ Name = "Heroic Games Launcher";    Id = "HeroicGamesLauncher.HeroicGamesLauncher"; Category = "Gaming";   Description = "Open-source launcher for Epic, GOG, and Amazon Games." }
    @{ Name = "Battle.net";               Id = "Blizzard.BattleNet";                Category = "Gaming";         Description = "Blizzard's game launcher." }
    @{ Name = "EA Desktop";               Id = "ElectronicArts.EADesktop";          Category = "Gaming";         Description = "EA's game store and launcher." }
    @{ Name = "Ubisoft Connect";          Id = "Ubisoft.Connect";                   Category = "Gaming";         Description = "Ubisoft's game launcher and store." }
    @{ Name = "itch.io";                  Id = "itchio.itch";                       Category = "Gaming";         Description = "Indie game and asset store with built-in updates." }
    @{ Name = "Prism Launcher";           Id = "PrismLauncher.PrismLauncher";       Category = "Gaming";         Description = "Open-source Minecraft launcher with instance profiles and mod support." }
    @{ Name = "DS4Windows";               Id = "Ryochan7.DS4Windows";               Category = "Gaming";         Description = "Use DualShock 4 and DualSense controllers on Windows." }
    @{ Name = "Vortex";                   Id = "Nexus-Mods.Vortex";                 Category = "Gaming";         Description = "Nexus Mods' game mod manager." }

    # Productivity (LibreOffice moved to Office)
    @{ Name = "Obsidian";                 Id = "Obsidian.Obsidian";                 Category = "Productivity";   Description = "Markdown-based personal knowledge base." }
    @{ Name = "Notion";                   Id = "Notion.Notion";                     Category = "Productivity";   Description = "Notes, docs, and lightweight databases." }
    @{ Name = "Joplin";                   Id = "JoplinApp.Joplin";                  Category = "Productivity";   Description = "Open-source notes and to-do with end-to-end encryption." }
    @{ Name = "Logseq";                   Id = "Logseq.Logseq";                     Category = "Productivity";   Description = "Local-first outliner and knowledge graph." }
    @{ Name = "Anki";                     Id = "Anki.Anki";                         Category = "Productivity";   Description = "Spaced-repetition flashcards." }
    @{ Name = "Calibre";                  Id = "calibre.calibre";                   Category = "Productivity";   Description = "E-book library manager and converter." }
    @{ Name = "Standard Notes";           Id = "StandardNotes.StandardNotes";       Category = "Productivity";   Description = "Encrypted note-taking with cross-platform sync." }

    # Security
    @{ Name = "Bitwarden";                Id = "Bitwarden.Bitwarden";               Category = "Security";       Description = "Open-source password manager with cloud sync." }
    @{ Name = "Malwarebytes";             Id = "Malwarebytes.Malwarebytes";         Category = "Security";       Description = "Anti-malware scanner." }
    @{ Name = "KeePassXC";                Id = "KeePassXCTeam.KeePassXC";           Category = "Security";       Description = "Local-first password manager (KeePass-compatible)." }
    @{ Name = "Cryptomator";              Id = "Cryptomator.Cryptomator";           Category = "Security";       Description = "Encrypts files in any cloud storage folder." }
    @{ Name = "VeraCrypt";                Id = "IDRIX.VeraCrypt";                   Category = "Security";       Description = "Disk and container encryption (TrueCrypt successor)." }
    @{ Name = "WireGuard";                Id = "WireGuard.WireGuard";               Category = "Security";       Description = "Modern, fast VPN tunnel." }
    @{ Name = "Tailscale";                Id = "tailscale.tailscale";               Category = "Security";       Description = "Zero-config mesh VPN built on WireGuard." }

    # Network
    @{ Name = "Wireshark";                Id = "WiresharkFoundation.Wireshark";     Category = "Network";        Description = "Network protocol analyzer." }
    @{ Name = "PuTTY";                    Id = "PuTTY.PuTTY";                       Category = "Network";        Description = "SSH and serial terminal client." }
    @{ Name = "WinSCP";                   Id = "WinSCP.WinSCP";                     Category = "Network";        Description = "SFTP, FTP, and SCP file transfer client." }
    @{ Name = "FileZilla";                Id = "TimKosse.FileZilla.Client";         Category = "Network";        Description = "Cross-platform FTP, FTPS, and SFTP client." }

    # Cloud & Sync
    @{ Name = "Syncthing";                Id = "Syncthing.Syncthing";               Category = "Cloud & Sync";   Description = "Peer-to-peer continuous file sync." }
    @{ Name = "Nextcloud Desktop";        Id = "Nextcloud.NextcloudDesktop";        Category = "Cloud & Sync";   Description = "Sync client for self-hosted Nextcloud servers." }
    @{ Name = "Dropbox";                  Id = "Dropbox.Dropbox";                   Category = "Cloud & Sync";   Description = "File sync and sharing." }
    @{ Name = "MEGA Sync";                Id = "MEGALimited.MEGASync";              Category = "Cloud & Sync";   Description = "Encrypted cloud storage sync client." }

    # Office (LibreOffice moved here from Productivity)
    @{ Name = "LibreOffice";              Id = "TheDocumentFoundation.LibreOffice"; Category = "Office";         Description = "Free office suite with Writer, Calc, Impress, and more." }
    @{ Name = "OnlyOffice DesktopEditors"; Id = "ONLYOFFICE.DesktopEditors";        Category = "Office";         Description = "MS-Office-compatible office suite." }
)

function Get-MergedQuickInstalls {
    $userIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($qi in $script:quickInstalls) { [void]$userIds.Add([string]$qi.Id) }

    $merged = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($qi in $script:quickInstalls) {
        $src  = if ($qi.PSObject.Properties["Source"])      { [string]$qi.Source }      else { $null }
        $desc = if ($qi.PSObject.Properties["Description"]) { [string]$qi.Description } else { $null }
        $merged.Add(@{ Name = $qi.Name; Id = $qi.Id; Category = $qi.Category; IsCurated = $false; Source = $src; Description = $desc })
    }

    foreach ($c in $script:curatedApps) {
        if ($userIds.Contains([string]$c.Id)) { continue }
        if ($c.Id -in $script:hiddenCuratedApps) { continue }
        if ($c.Category -in $script:hiddenDefaultInstallCategories) { continue }
        $src  = if ($c.ContainsKey("Source"))      { [string]$c.Source }      else { $null }
        $desc = if ($c.ContainsKey("Description")) { [string]$c.Description } else { $null }
        $merged.Add(@{ Name = $c.Name; Id = $c.Id; Category = $c.Category; IsCurated = $true; Source = $src; Description = $desc })
    }
    return $merged
}

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

# Refresh-QuickInstallCategories was tied to the deleted in-search ComboBox.
# Kept as a no-op so existing call sites (Update-QuickInstalls) don't break.
function Refresh-QuickInstallCategories { }

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
        $hdr.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
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
        $nb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
        $nb.VerticalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetColumn($nb, 0)

        $ib = New-Object System.Windows.Controls.TextBlock
        $ib.Text = $id; $ib.FontSize = 10
        $ib.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
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
        Add-SectionHeader ($b.Name + " - bundle (" + [string]$b.Apps.Count + " apps)")
        foreach ($app in $b.Apps) {
            Add-PkgRow $app.Name $app.Id 8
            if ($seenIds.Add($app.Id)) { $allPackages.Add(@{Name=$app.Name; Id=$app.Id}) }
        }
    }

    ($dlg.FindName("DlgTitle")).Text = "Review - " + [string]$allPackages.Count + " app(s)"
    ($dlg.FindName("DlgTotal")).Text = [string]$allPackages.Count + " unique app(s) to install"
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
        Set-BusyStatus ("Installing " + [string]$total + " app(s)...")
        Show-ScyProgress -Border $installsProgressBorder -Bar $installsProgressBar -Label $installsProgressLabel `
                         -Text ("Starting install of " + [string]$total + " app(s)...") -Value 0 -Max $total

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
                    Show-ThemedDialog ("Done. Failed apps:`n" + ($result.Failed -join "`n")) "Result" "OK" "Warning"
                } else {
                    Show-ThemedDialog ("Installed " + [string]$result.Total + " app(s) successfully.") "Done" "OK" "Information"
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

        # Restore-hidden affordance: only shown when at least one curated app has been hidden
        if ($script:hiddenCuratedApps.Count -gt 0) {
            $restoreRow = New-Object System.Windows.Controls.Grid
            $rc0 = New-Object System.Windows.Controls.ColumnDefinition; $rc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
            $rc1 = New-Object System.Windows.Controls.ColumnDefinition; $rc1.Width = [System.Windows.GridLength]::Auto
            $restoreRow.ColumnDefinitions.Add($rc0); $restoreRow.ColumnDefinitions.Add($rc1)
            $restoreRow.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)

            $restoreLabel = New-Object System.Windows.Controls.TextBlock
            $restoreLabel.Text              = "Curated hidden: " + [string]$script:hiddenCuratedApps.Count
            $restoreLabel.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
            $restoreLabel.FontSize          = 11
            $restoreLabel.VerticalAlignment = "Center"
            [System.Windows.Controls.Grid]::SetColumn($restoreLabel, 0)

            $restoreBtn = New-Object System.Windows.Controls.Button
            $restoreBtn.Content = "Restore all"
            $restoreBtn.Style   = $window.Resources["SecondaryButton"]
            $restoreBtn.Add_Click({
                $script:hiddenCuratedApps.Clear()
                Save-Settings
                Update-QuickInstalls
            })
            [System.Windows.Controls.Grid]::SetColumn($restoreBtn, 1)

            $restoreRow.Children.Add($restoreLabel) | Out-Null
            $restoreRow.Children.Add($restoreBtn)   | Out-Null
            $panel.Children.Add($restoreRow)        | Out-Null
        }

        foreach ($qi in (Get-MergedQuickInstalls)) {
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
            $nameBlock.Text              = if ($qi.IsCurated) { [char]0x2605 + "  " + $name } else { $name }
            $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
            $nameBlock.FontSize          = 12
            $nameBlock.VerticalAlignment = "Center"
            [System.Windows.Controls.Grid]::SetColumn($nameBlock, 0)

            $idBlock = New-Object System.Windows.Controls.TextBlock
            $idBlock.Text              = $id
            $idBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
            $idBlock.FontSize          = 11
            $idBlock.Margin            = [System.Windows.Thickness]::new(10, 0, 10, 0)
            $idBlock.VerticalAlignment = "Center"
            [System.Windows.Controls.Grid]::SetColumn($idBlock, 1)

            $row.Children.Add($nameBlock) | Out-Null
            $row.Children.Add($idBlock)   | Out-Null

            if ($qi.IsCurated) {
                $curLabel = New-Object System.Windows.Controls.TextBlock
                $curLabel.Text              = "Curated"
                $curLabel.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                $curLabel.FontSize          = 11
                $curLabel.VerticalAlignment = "Center"
                $curLabel.Margin            = [System.Windows.Thickness]::new(0, 0, 10, 0)
                [System.Windows.Controls.Grid]::SetColumn($curLabel, 2)

                $hideBtn         = New-Object System.Windows.Controls.Button
                $hideBtn.Content = "Hide"
                $hideBtn.Style   = $window.Resources["SecondaryButton"]
                $hideBtn.Tag     = $id
                $hideBtn.Add_Click({
                    param($s, $e)
                    $idToHide = [string]$s.Tag
                    if ($idToHide -notin $script:hiddenCuratedApps) {
                        $script:hiddenCuratedApps.Add($idToHide)
                        Save-Settings
                        Update-QuickInstalls
                    }
                })
                [System.Windows.Controls.Grid]::SetColumn($hideBtn, 3)

                $row.Children.Add($curLabel) | Out-Null
                $row.Children.Add($hideBtn)  | Out-Null
                $panel.Children.Add($row)    | Out-Null
                continue
            }

            $catBox                   = New-Object System.Windows.Controls.ComboBox
            $catBox.IsEditable        = $true
            $catBox.FontSize          = 11
            $catBox.VerticalAlignment = "Center"
            $catBox.Margin            = [System.Windows.Thickness]::new(0, 0, 10, 0)
            $catBox.ToolTip           = "Category (select or type new)"
            # Resolve back to the live $script:quickInstalls entry so edits persist
            $liveQi = $null
            foreach ($liveCandidate in $script:quickInstalls) {
                if ($liveCandidate.Id -eq $qi.Id) { $liveQi = $liveCandidate; break }
            }
            $catBox.Tag               = $liveQi
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
            $removeBtn.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "DangerBrush")
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

            $row.Children.Add($catBox)    | Out-Null
            $row.Children.Add($removeBtn) | Out-Null
            $panel.Children.Add($row)     | Out-Null
        }

        # Bundles section in edit mode
        $sepLine            = New-Object System.Windows.Controls.Border
        $sepLine.Height     = 1
        $sepLine.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BorderBrush")
        $sepLine.Margin     = [System.Windows.Thickness]::new(0, 10, 0, 10)
        $panel.Children.Add($sepLine) | Out-Null

        $bEditHeader            = New-Object System.Windows.Controls.TextBlock
        $bEditHeader.Text       = "Bundles"
        $bEditHeader.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
        $bEditHeader.FontSize   = 11
        $bEditHeader.FontWeight = "SemiBold"
        $bEditHeader.Margin     = [System.Windows.Thickness]::new(0, 0, 0, 8)
        $panel.Children.Add($bEditHeader) | Out-Null

        foreach ($bndl in $script:quickBundles) {
            $capturedBndl = $bndl

            $bCard             = New-Object System.Windows.Controls.Border
            $bCard.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "InputBgBrush")
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
            $nameBox.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "FgBrush")
            $nameBox.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, "InputBgBrush")
            $nameBox.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "BorderBrush")
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
            $descBox.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "FgBrush")
            $descBox.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, "InputBgBrush")
            $descBox.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "BorderBrush")
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
                $appNameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
                $appNameBlock.FontSize         = 11
                $appNameBlock.VerticalAlignment = "Center"
                [System.Windows.Controls.Grid]::SetColumn($appNameBlock, 0)

                $appIdBlock                  = New-Object System.Windows.Controls.TextBlock
                $appIdBlock.Text             = $app.Id
                $appIdBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                $appIdBlock.FontSize         = 10
                $appIdBlock.Margin           = [System.Windows.Thickness]::new(8, 0, 10, 0)
                $appIdBlock.VerticalAlignment = "Center"
                [System.Windows.Controls.Grid]::SetColumn($appIdBlock, 1)

                $removeAppBtn           = New-Object System.Windows.Controls.Button
                $removeAppBtn.Content   = "×"
                $removeAppBtn.Style     = $window.Resources["SecondaryButton"]
                $removeAppBtn.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "MutedText")
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
        foreach ($qi in (Get-MergedQuickInstalls)) {
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
            $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "Surface2Brush")
            $border.CornerRadius = [System.Windows.CornerRadius]::new(6)
            $border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
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
                $nameBlock.Text = if ($qi.IsCurated) { [char]0x2605 + "  " + $qiName } else { $qiName }
                $nameBlock.FontSize = 12
                $nameBlock.VerticalAlignment = "Center"
                if ($qi.IsCurated) { $nameBlock.ToolTip = "Curated: click to install, or use Edit to hide" }
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

                # ── Right-click context menu ──────────────────────────
                $ctxMenu = New-Object System.Windows.Controls.ContextMenu

                # Hide (curated) / Remove (user)
                $hideMi = New-Object System.Windows.Controls.MenuItem
                $hideMi.Header = if ($qi.IsCurated) { "Hide" } else { "Remove" }
                $hideMi.Tag    = $qi
                $hideMi.Add_Click({
                    param($s, $e)
                    $app = $s.Tag
                    if ($app.IsCurated) {
                        if ([string]$app.Id -notin $script:hiddenCuratedApps) {
                            $script:hiddenCuratedApps.Add([string]$app.Id)
                            Save-Settings
                            Update-QuickInstalls
                        }
                    } else {
                        for ($i = 0; $i -lt $script:quickInstalls.Count; $i++) {
                            if ($script:quickInstalls[$i].Id -eq $app.Id) {
                                $script:quickInstalls.RemoveAt($i)
                                Save-Settings
                                Update-QuickInstalls
                                break
                            }
                        }
                    }
                })
                $ctxMenu.Items.Add($hideMi) | Out-Null

                # Change category (user apps only — curated have fixed categories)
                if (-not $qi.IsCurated) {
                    $liveQi = $null
                    foreach ($lc in $script:quickInstalls) {
                        if ($lc.Id -eq $qi.Id) { $liveQi = $lc; break }
                    }
                    if ($liveQi) {
                        $catSub = New-Object System.Windows.Controls.MenuItem
                        $catSub.Header = "Change category"
                        foreach ($cat in (Get-AllQuickCategories)) {
                            $cmi = New-Object System.Windows.Controls.MenuItem
                            $cmi.Header    = $cat
                            $cmi.IsEnabled = ($liveQi.Category -ne $cat)
                            $cmi.Tag       = @{ LiveQi = $liveQi; Category = $cat }
                            $cmi.Add_Click({
                                param($s, $e)
                                $s.Tag.LiveQi.Category = $s.Tag.Category
                                Save-Settings
                                Update-QuickInstalls
                            })
                            $catSub.Items.Add($cmi) | Out-Null
                        }
                        $newCatMi = New-Object System.Windows.Controls.MenuItem
                        $newCatMi.Header = "+ New category..."
                        $newCatMi.Tag    = $liveQi
                        $newCatMi.Add_Click({
                            param($s, $e)
                            Ensure-VisualBasic
                            $g = [Microsoft.VisualBasic.Interaction]::InputBox("Category name:", "New Category", "")
                            if (-not [string]::IsNullOrWhiteSpace($g)) {
                                $g = $g.Trim()
                                if ($g -notin (Get-AllQuickCategories)) {
                                    $script:customInstallCategories.Add($g)
                                    if (Get-Command Render-GroupSettings -ErrorAction SilentlyContinue) { Render-GroupSettings }
                                }
                                $s.Tag.Category = $g
                                Save-Settings
                                Update-QuickInstalls
                            }
                        })
                        $catSub.Items.Add($newCatMi) | Out-Null
                        $ctxMenu.Items.Add($catSub) | Out-Null
                    }
                }

                # Add to bundle
                $bundleSub = New-Object System.Windows.Controls.MenuItem
                $bundleSub.Header = "Add to bundle"
                if ($script:quickBundles.Count -eq 0) {
                    $emptyMi = New-Object System.Windows.Controls.MenuItem
                    $emptyMi.Header    = "(no bundles yet)"
                    $emptyMi.IsEnabled = $false
                    $bundleSub.Items.Add($emptyMi) | Out-Null
                } else {
                    foreach ($b in $script:quickBundles) {
                        $alreadyIn = $false
                        foreach ($a in @($b.Apps)) { if ($a.Id -eq $qi.Id) { $alreadyIn = $true; break } }
                        $bmi = New-Object System.Windows.Controls.MenuItem
                        $bmi.Header    = $b.Name
                        $bmi.IsEnabled = -not $alreadyIn
                        $bmi.Tag       = @{ Bundle = $b; AppName = $qi.Name; AppId = $qi.Id }
                        $bmi.Add_Click({
                            param($s, $e)
                            $s.Tag.Bundle.Apps.Add(@{ Name = $s.Tag.AppName; Id = $s.Tag.AppId })
                            Save-Settings
                            Update-QuickInstalls
                        })
                        $bundleSub.Items.Add($bmi) | Out-Null
                    }
                }
                $newBundleMi = New-Object System.Windows.Controls.MenuItem
                $newBundleMi.Header = "+ New bundle..."
                $newBundleMi.Tag    = @{ AppName = $qi.Name; AppId = $qi.Id }
                $newBundleMi.Add_Click({
                    param($s, $e)
                    Ensure-VisualBasic
                    $bn = [Microsoft.VisualBasic.Interaction]::InputBox("Bundle name:", "New Bundle", "")
                    if (-not [string]::IsNullOrWhiteSpace($bn)) {
                        $bn = $bn.Trim()
                        $exists = $false
                        foreach ($eb in $script:quickBundles) { if ($eb.Name -eq $bn) { $exists = $true; break } }
                        if (-not $exists) {
                            $apps = [System.Collections.Generic.List[hashtable]]::new()
                            $apps.Add(@{ Name = $s.Tag.AppName; Id = $s.Tag.AppId })
                            $script:quickBundles.Add(@{ Name = $bn; Description = ""; Apps = $apps })
                            Save-Settings
                            Update-QuickInstalls
                        }
                    }
                })
                $bundleSub.Items.Add($newBundleMi) | Out-Null
                $ctxMenu.Items.Add($bundleSub) | Out-Null

                $btn.ContextMenu = $ctxMenu

                $itemsPanel.Children.Add($btn) | Out-Null
            }
        }

        # ── Bundles card ──────────────────────────────────────────
        if ($script:quickBundles.Count -gt 0) {
            $bBorder              = New-Object System.Windows.Controls.Border
            $bBorder.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "Surface2Brush")
            $bBorder.CornerRadius = [System.Windows.CornerRadius]::new(6)
            $bBorder.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
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

    # Keep the Store landing in sync with QuickInstalls changes (edits, adds, removes)
    if (Get-Command Show-StoreLanding -ErrorAction SilentlyContinue) {
        if ($storeCategoryArea.Visibility -ne "Visible") { Show-StoreLanding }
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

# -- Quick Install: confirm and install selected ------------------------------
(Find "BtnQuickInstallSelected").Add_Click({
    if ($script:selectedQuickItems.Count -eq 0) { return }
    Show-QuickInstallConfirmDialog
})

# (Removed: $btnAddToQuickInstalls and $btnAddToBundle handlers - they
# operated on the deleted checkbox-row search UI. The new Store search uses
# cards with single-app install via the detail panel.)

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
        $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
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
        $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
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

# Deferred: settings are loaded by Tab-Settings.ps1 which is sourced after this file
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


# ─────────────────────────────────────────────────────────────────
# Store landing: category tiles + app cards (GNOME-Software-style)
# Lives above the existing PkgSection_Search / PkgSection_Quick /
# PkgSection_Local surfaces. Click a category tile -> swap to the
# cards view for that category. Each card has a single Install
# button. The "Edit list" header button toggles the legacy
# PkgSection_Quick panel for managing the user's QuickInstalls.
# ─────────────────────────────────────────────────────────────────

$storeCategoriesPanel    = Find "StoreCategoriesPanel"
$storeCategoryArea       = Find "StoreCategoryArea"
$storeCategoryAppsPanel  = Find "StoreCategoryAppsPanel"
$storeCategoryBack       = Find "StoreCategoryBack"
$storeCategoryName       = Find "StoreCategoryName"
$storeHeaderText         = Find "StoreHeaderText"
$storeSearchBox          = Find "StoreSearchBox"
$storeSearchPlaceholder  = Find "StoreSearchPlaceholder"
$storeSearchClear        = Find "StoreSearchClear"
$storeSearchArea         = Find "StoreSearchArea"
$storeSearchHeader       = Find "StoreSearchHeader"
$storeSearchCuratedPanel = Find "StoreSearchCuratedPanel"
$btnStoreSearchWinget    = Find "BtnStoreSearchWinget"
$storeSearchWingetStatus = Find "StoreSearchWingetStatus"
$storeSearchWingetPanel  = Find "StoreSearchWingetPanel"

# Tiny accent palette for letter badges, drawn from the theme.
$script:storeBadgeBrushKeys = @("AccentBrush", "SuccessBrush", "WarningBrush", "DangerBrush")

function Get-StoreBadgeBrushKey {
    param([string]$Seed)
    if ([string]::IsNullOrEmpty($Seed)) { return "AccentBrush" }
    $sum = 0
    foreach ($ch in $Seed.ToCharArray()) { $sum += [int]$ch }
    $idx = $sum % $script:storeBadgeBrushKeys.Count
    return $script:storeBadgeBrushKeys[$idx]
}

function New-LetterBadge {
    param([string]$Name, [string]$Id, [int]$Size = 32)

    $border              = New-Object System.Windows.Controls.Border
    $border.Width        = $Size
    $border.Height       = $Size
    $border.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $border.SetResourceReference(
        [System.Windows.Controls.Border]::BackgroundProperty,
        (Get-StoreBadgeBrushKey ($Id + $Name)))

    $letter           = if ([string]::IsNullOrWhiteSpace($Name)) { "?" } else { ([string]$Name[0]).ToUpper() }
    $tb               = New-Object System.Windows.Controls.TextBlock
    $tb.Text          = $letter
    $tb.Foreground    = [System.Windows.Media.Brushes]::White
    $tb.FontSize      = [Math]::Round($Size * 0.5)
    $tb.FontWeight    = [System.Windows.FontWeights]::SemiBold
    $tb.HorizontalAlignment = "Center"
    $tb.VerticalAlignment   = "Center"
    $border.Child = $tb
    return $border
}

# Neutral placeholder shown while an icon is being fetched. If the fetch
# succeeds the favicon takes over; if it fails Set-BadgeToLetter swaps to
# the colored letter as a final fallback.
function New-LoadingBadge {
    param([int]$Size = 32)

    $border              = New-Object System.Windows.Controls.Border
    $border.Width        = $Size
    $border.Height       = $Size
    $border.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $border.SetResourceReference(
        [System.Windows.Controls.Border]::BackgroundProperty, "InputBgBrush")
    $border.SetResourceReference(
        [System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
    $border.BorderThickness = [System.Windows.Thickness]::new(1)

    $tb               = New-Object System.Windows.Controls.TextBlock
    $tb.Text          = [string][char]0x22EF  # midline horizontal ellipsis ⋯
    $tb.FontSize      = [Math]::Round($Size * 0.42)
    $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    $tb.HorizontalAlignment = "Center"
    $tb.VerticalAlignment   = "Center"
    $border.Child = $tb
    return $border
}

# In-place swap of a Border's contents/background to the letter-badge look.
# Used when an async icon fetch fails - we keep the same Border instance so
# parent layouts don't have to re-resolve a new child.
function Set-BadgeToLetter {
    param(
        [System.Windows.Controls.Border]$Target,
        [string]$Name, [string]$Id, [int]$Size = 32
    )
    $Target.SetResourceReference(
        [System.Windows.Controls.Border]::BackgroundProperty,
        (Get-StoreBadgeBrushKey ($Id + $Name)))
    $Target.BorderThickness = [System.Windows.Thickness]::new(0)

    $letter        = if ([string]::IsNullOrWhiteSpace($Name)) { "?" } else { ([string]$Name[0]).ToUpper() }
    $tb            = New-Object System.Windows.Controls.TextBlock
    $tb.Text       = $letter
    $tb.Foreground = [System.Windows.Media.Brushes]::White
    $tb.FontSize   = [Math]::Round($Size * 0.5)
    $tb.FontWeight = [System.Windows.FontWeights]::SemiBold
    $tb.HorizontalAlignment = "Center"
    $tb.VerticalAlignment   = "Center"
    $Target.Child = $tb
}

function Install-StoreSingleApp {
    param([string]$Id, [string]$Name, $TriggerButton, [string]$Source)

    if ($script:installInProgress) { return }
    $script:installInProgress = $true
    if ($TriggerButton) {
        $TriggerButton.IsEnabled = $false
        $TriggerButton.Content   = "Installing..."
    }

    Set-BusyStatus ("Installing " + $Name + "...")
    Show-ScyProgress -Border $installsProgressBorder -Bar $installsProgressBar -Label $installsProgressLabel `
                     -Text ("Installing " + $Name + "...") -Value $null -Max 1

    Start-ScyJob `
        -Variables @{ wingetId = $Id; wingetSrc = $Source } `
        -Context   @{ Name = $Name; Btn = $TriggerButton } `
        -Work {
            param($emit)
            & $emit ("Installing " + $wingetId)
            if ($wingetSrc) {
                & winget install --id $wingetId --source $wingetSrc --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            } else {
                & winget install --id $wingetId --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            }
            return @{ ExitCode = $LASTEXITCODE; Id = $wingetId }
        } `
        -OnLine {
            param($line, $ctx)
            $footerStatus.Text = "Scy - " + [string]$line
        } `
        -OnComplete {
            param($result, $err, $ctx)
            $script:installInProgress = $false
            Hide-ScyProgress $installsProgressBorder $installsProgressBar
            Set-ReadyStatus
            $btn = $ctx.Btn
            if ($btn) {
                $btn.IsEnabled = $true
                $btn.Content   = "Install"
            }
            if ($err) {
                Show-ThemedDialog ("Install error: " + $err.Exception.Message) "Error" "OK" "Error"
                return
            }
            if ($result.ExitCode -ne 0) {
                Show-ThemedDialog ("winget exited with code " + [string]$result.ExitCode + " installing " + $ctx.Name) "Install failed" "OK" "Warning"
            }
        } | Out-Null
}

function New-CategoryTile {
    param([string]$Category, [int]$Count)

    $border              = New-Object System.Windows.Controls.Border
    $border.SetResourceReference(
        [System.Windows.Controls.Border]::BackgroundProperty, "InputBgBrush")
    $border.SetResourceReference(
        [System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $border.CornerRadius    = [System.Windows.CornerRadius]::new(8)
    $border.Width           = 180
    $border.Height          = 84
    $border.Margin          = [System.Windows.Thickness]::new(0, 0, 10, 10)
    $border.Padding         = [System.Windows.Thickness]::new(16, 14, 16, 14)
    $border.Cursor          = [System.Windows.Input.Cursors]::Hand

    $sp = New-Object System.Windows.Controls.StackPanel

    $name              = New-Object System.Windows.Controls.TextBlock
    $name.Text         = $Category
    $name.FontSize     = 13
    $name.FontWeight   = [System.Windows.FontWeights]::SemiBold
    $name.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
    $name.TextTrimming = "CharacterEllipsis"

    $sub             = New-Object System.Windows.Controls.TextBlock
    $sub.Text        = if ($Count -eq 1) { "1 app" } else { [string]$Count + " apps" }
    $sub.FontSize    = 11
    $sub.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    $sub.Margin      = [System.Windows.Thickness]::new(0, 6, 0, 0)

    $sp.Children.Add($name) | Out-Null
    $sp.Children.Add($sub)  | Out-Null
    $border.Child = $sp

    $border.Tag = $Category
    $border.Add_MouseLeftButtonUp({
        param($s, $e)
        Show-StoreCategory ([string]$s.Tag)
    })

    return $border
}

function New-AppCard {
    param(
        [string]$Name, [string]$Id, [string]$Subtitle = "",
        [string]$Source, [string]$Description,
        [switch]$SkipIconFetch,      # true for raw winget search results - their icons are too expensive to fetch at bulk render time
        [switch]$SkipMeta,           # true for raw winget search results - skip description/publisher fetch on detail panel open
        [switch]$IsCurated           # attaches right-click "Hide app" context menu
    )

    $border              = New-Object System.Windows.Controls.Border
    $border.SetResourceReference(
        [System.Windows.Controls.Border]::BackgroundProperty, "InputBgBrush")
    $border.SetResourceReference(
        [System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $border.CornerRadius    = [System.Windows.CornerRadius]::new(6)
    $border.Width           = 220
    $border.Margin          = [System.Windows.Thickness]::new(0, 0, 10, 10)
    $border.Padding         = [System.Windows.Thickness]::new(12, 12, 12, 12)
    $border.Cursor          = [System.Windows.Input.Cursors]::Hand

    # Card layout: badge | name + subtitle
    $row = New-Object System.Windows.Controls.Grid
    $rc0 = New-Object System.Windows.Controls.ColumnDefinition; $rc0.Width = [System.Windows.GridLength]::Auto
    $rc1 = New-Object System.Windows.Controls.ColumnDefinition; $rc1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $row.ColumnDefinitions.Add($rc0); $row.ColumnDefinitions.Add($rc1)

    if ($SkipIconFetch) {
        # Letter badge directly - no async icon fetch (avoids N winget-show calls
        # when rendering big winget search result lists).
        $badge = New-LetterBadge -Name $Name -Id $Id -Size 36
    } else {
        $badge = New-LoadingBadge -Size 36

        # Kick off async icon fetch; swap to favicon when available, or fall
        # back to the colored letter badge if the fetch fails.
        $capturedBadge = $badge
        $capturedName  = $Name
        $capturedId    = $Id
        Get-AppIconAsync -Id $Id -Name $Name -Source $Source -OnReady ({
            param($iconPath)
            if ($iconPath) {
                Swap-BadgeToIcon -Target $capturedBadge -Path $iconPath -Size 36
            } else {
                Set-BadgeToLetter -Target $capturedBadge -Name $capturedName -Id $capturedId -Size 36
            }
        }.GetNewClosure())
    }
    $badge.Margin = [System.Windows.Thickness]::new(0, 0, 12, 0)
    [System.Windows.Controls.Grid]::SetColumn($badge, 0)

    $textStack = New-Object System.Windows.Controls.StackPanel
    $textStack.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($textStack, 1)

    $nameBlock              = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text         = $Name
    $nameBlock.FontSize     = 13
    $nameBlock.FontWeight   = [System.Windows.FontWeights]::SemiBold
    $nameBlock.TextTrimming = "CharacterEllipsis"
    $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")

    $subBlock              = New-Object System.Windows.Controls.TextBlock
    $subBlock.Text         = if ([string]::IsNullOrWhiteSpace($Subtitle)) { $Id } else { $Subtitle }
    $subBlock.FontSize     = 11
    $subBlock.TextTrimming = "CharacterEllipsis"
    $subBlock.Margin       = [System.Windows.Thickness]::new(0, 2, 0, 0)
    $subBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")

    $textStack.Children.Add($nameBlock) | Out-Null
    $textStack.Children.Add($subBlock)  | Out-Null

    $row.Children.Add($badge)     | Out-Null
    $row.Children.Add($textStack) | Out-Null
    $border.Child = $row

    # Click anywhere on the card opens the detail panel
    $border.Tag = @{ Id = $Id; Name = $Name; Source = $Source; Description = $Description; SkipMeta = [bool]$SkipMeta }
    $border.Add_MouseLeftButtonUp({
        param($s, $e)
        $info = $s.Tag
        Show-AppDetailPanel -Id $info.Id -Name $info.Name -Source $info.Source -Description $info.Description -SkipMeta:$info.SkipMeta
    })

    # Right-click on a curated card -> Hide app from the Store catalog.
    if ($IsCurated) {
        $menu = New-Object System.Windows.Controls.ContextMenu
        $hide = New-Object System.Windows.Controls.MenuItem
        $hide.Header = "Hide app"
        $hide.Tag    = $Id
        $hide.Add_Click({
            param($s, $e)
            $hideId = [string]$s.Tag
            if (-not ($script:hiddenCuratedApps -contains $hideId)) {
                $script:hiddenCuratedApps.Add($hideId) | Out-Null
                Save-Settings
                # Re-render the current view so the card disappears.
                if ($storeSearchArea.Visibility -eq "Visible") {
                    Show-StoreSearch -Query $storeSearchBox.Text
                } elseif ($storeCategoryArea.Visibility -eq "Visible") {
                    Show-StoreCategory -Category $storeCategoryName.Text
                } else {
                    Show-StoreLanding
                }
            }
        })
        $menu.Items.Add($hide) | Out-Null
        $border.ContextMenu = $menu
    }

    return $border
}

# ── Serialized 'winget show' meta fetcher ────────────────────────
# winget show is slow (~1-2s per call) and each one spawns a runspace +
# process. Firing N in parallel freezes the UI thread. We funnel all
# meta requests through this coordinator: max 1 in flight, the rest
# queue up. Both the icon fetcher and the detail panel share it.

# Shared meta-fetcher state bundled into one hashtable so it survives the
# Register-ObjectEvent boundary (subscriber actions get a private $script:
# scope - the only reliable way to share state is by reference via
# -MessageData). The Active flag is wrapped in a 1-element array to make
# the bool itself mutable through the same reference.
$script:metaState = @{
    Cache    = @{}                                                          # id -> parsed meta
    Pending  = @{}                                                          # id -> List[scriptblock]
    Queue    = [System.Collections.Generic.Queue[string]]::new()
    Active   = @($false)                                                    # use [0] for mutable bool
    Sources  = @{}                                                          # id -> winget source (e.g. "msstore"); absent = default
}
# Back-compat aliases so the rest of the file can keep reading $script:appMetaCache etc.
$script:appMetaCache = $script:metaState.Cache

function Start-MetaFetchJob {
    param([string]$Id)

    # Spawn winget show as a plain Process and let it exit, then read the
    # stdout buffer in one go. Avoids the ~300ms runspace creation cost that
    # Start-ScyJob pays per call. Process.Exited is wired through
    # Register-ObjectEvent so the handler runs on the engine thread (with a
    # runspace available); raw .NET delegates would crash because the .NET
    # thread pool has no PowerShell runspace.
    $src = $null
    if ($script:metaState.Sources.ContainsKey($Id)) { $src = [string]$script:metaState.Sources[$Id] }
    $wingetArgs = "show --id `"$Id`" --accept-source-agreements"
    if ($src) { $wingetArgs = "show --id `"$Id`" --source $src --accept-source-agreements" }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "winget"
    $psi.Arguments              = $wingetArgs
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8

    $proc                     = New-Object System.Diagnostics.Process
    $proc.StartInfo           = $psi
    $proc.EnableRaisingEvents = $true

    $sourceId = "MetaFetch_" + ([guid]::NewGuid().ToString("N"))
    # Pass the shared state hashtable + window by reference; the subscriber
    # action runs in a private $script: scope and can only see what arrives
    # via -MessageData.
    Register-ObjectEvent -InputObject $proc -EventName Exited `
        -SourceIdentifier $sourceId `
        -MessageData @{
            Id       = $Id
            SourceId = $sourceId
            State    = $script:metaState
            Win      = $window
        } `
        -Action {
            $msg   = $Event.MessageData
            $p     = $Sender
            $state = $msg.State
            try {
                $stdout = $p.StandardOutput.ReadToEnd()
                $lines  = $stdout -split "`r?`n"
                $meta   = $null
                try { $meta = Parse-WingetShowOutput -Lines $lines } catch {}
                if ($meta) { $state.Cache[$msg.Id] = $meta }

                if ($state.Pending.ContainsKey($msg.Id)) {
                    $cbs = $state.Pending[$msg.Id]
                    $state.Pending.Remove($msg.Id) | Out-Null
                    foreach ($cb in $cbs) { try { & $cb $meta $null } catch {} }
                }
                $state.Active[0] = $false

                if ($state.Queue.Count -gt 0) {
                    $nextId       = $state.Queue.Dequeue()
                    $state.Active[0] = $true
                    $drainAction = { Start-MetaFetchJob -Id $nextId }.GetNewClosure()
                    $msg.Win.Dispatcher.BeginInvoke([action]$drainAction,
                        [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
                }
            } finally {
                if ($state.Sources.ContainsKey($msg.Id)) { $state.Sources.Remove($msg.Id) | Out-Null }
                Unregister-Event -SourceIdentifier $msg.SourceId -ErrorAction SilentlyContinue
                try { $p.Dispose() } catch {}
            }
        } | Out-Null

    try {
        [void]$proc.Start()
    } catch {
        Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue
        if ($script:metaState.Pending.ContainsKey($Id)) {
            $cbs = $script:metaState.Pending[$Id]
            $script:metaState.Pending.Remove($Id) | Out-Null
            foreach ($cb in $cbs) { try { & $cb $null $_ } catch {} }
        }
        if ($script:metaState.Sources.ContainsKey($Id)) { $script:metaState.Sources.Remove($Id) | Out-Null }
        $script:metaState.Active[0] = $false
    }
}

function Get-AppMetaAsync {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][scriptblock]$OnReady,
        [string]$Source
    )

    # In-memory cache hit -> defer to a Background dispatcher tick so a burst
    # of callers don't all run their UI work in one stall.
    if ($script:metaState.Cache.ContainsKey($Id)) {
        $captured   = $OnReady
        $cachedMeta = $script:metaState.Cache[$Id]
        $action = {
            try { & $captured $cachedMeta $null } catch {}
        }.GetNewClosure()
        $window.Dispatcher.BeginInvoke([action]$action,
            [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
        return
    }

    # Record source for this id so Start-MetaFetchJob picks the right --source flag
    if ($Source -and -not $script:metaState.Sources.ContainsKey($Id)) {
        $script:metaState.Sources[$Id] = $Source
    }

    # Coalesce: same id already in flight or queued
    if ($script:metaState.Pending.ContainsKey($Id)) {
        $script:metaState.Pending[$Id].Add($OnReady) | Out-Null
        return
    }
    $script:metaState.Pending[$Id] = [System.Collections.Generic.List[scriptblock]]::new()
    $script:metaState.Pending[$Id].Add($OnReady) | Out-Null

    if ($script:metaState.Active[0]) {
        $script:metaState.Queue.Enqueue($Id)
    } else {
        $script:metaState.Active[0] = $true
        $deferredId = $Id
        $action = { Start-MetaFetchJob -Id $deferredId }.GetNewClosure()
        $window.Dispatcher.BeginInvoke([action]$action,
            [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
    }
}


# ── Icon cache + async favicon fetcher ───────────────────────────
# Pulls publisher / homepage URL out of `winget show`, derives the domain,
# fetches a favicon from google's s2 endpoint, and caches a PNG per Id at
# %LOCALAPPDATA%\Scy\IconCache. Cards and the detail panel show a letter
# badge first; once an icon is on disk, the badge is swapped for an Image.

function Get-ScyIconCacheDir {
    $dir = Join-Path $env:LOCALAPPDATA "Scy\IconCache"
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-CachedIconPath {
    param([string]$Id)
    $safe = ($Id -replace '[^A-Za-z0-9._-]', '_')
    return (Join-Path (Get-ScyIconCacheDir) ($safe + ".png"))
}

# Pending icon callbacks per Id, so multiple cards waiting on the same Id
# are all notified by a single fetch.
$script:iconPendingCallbacks = @{}
# Set of Ids we've already tried this session that returned nothing.
$script:iconFailedThisSession = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

function Load-ImageFromCache {
    param([string]$Path)
    try {
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.CacheOption  = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreImageCache
        $bmp.UriSource    = New-Object System.Uri($Path)
        $bmp.EndInit()
        $bmp.Freeze()
        return $bmp
    } catch {
        return $null
    }
}

function Get-DomainFromMeta {
    param([hashtable]$Meta)
    $url = ""
    if ($Meta.Homepage)        { $url = $Meta.Homepage }
    elseif ($Meta.PublisherUrl){ $url = $Meta.PublisherUrl }
    if (-not $url) { return $null }
    try {
        $uri = New-Object System.Uri($url)
        return $uri.Host
    } catch { return $null }
}

function Invoke-IconCallbacks {
    param([string]$Id, [string]$Path)
    if (-not $script:iconPendingCallbacks.ContainsKey($Id)) { return }
    $cbs = $script:iconPendingCallbacks[$Id]
    $script:iconPendingCallbacks.Remove($Id) | Out-Null
    foreach ($cb in $cbs) {
        try { & $cb $Path } catch {}
    }
}

function Fetch-FaviconAsync {
    param([string]$Id, [string]$Domain)

    $outPath = Get-CachedIconPath -Id $Id
    $url     = "https://www.google.com/s2/favicons?domain=" + $Domain + "&sz=64"

    Start-ScyJob `
        -Variables @{ favUrl = $url; favOut = $outPath } `
        -Context   @{ Id = $Id; OutPath = $outPath } `
        -Work {
            param($emit)
            try {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add('User-Agent', 'Mozilla/5.0 Scy')
                $wc.DownloadFile($favUrl, $favOut)
                $wc.Dispose()
                return @{ Ok = $true }
            } catch {
                return @{ Ok = $false; Err = $_.Exception.Message }
            }
        } `
        -OnComplete {
            param($result, $err, $ctx)
            $ok = $false
            if (-not $err -and $result.Ok -and (Test-Path $ctx.OutPath)) {
                $fi = Get-Item $ctx.OutPath -ErrorAction SilentlyContinue
                # Google's "domain has no icon" fallback is ~150-200 bytes; real
                # 64x64 PNGs are 800+ bytes. Use 400 as a conservative cutoff.
                if ($fi -and $fi.Length -gt 400) { $ok = $true }
                elseif ($fi) { Remove-Item $ctx.OutPath -Force -ErrorAction SilentlyContinue }
            }
            if ($ok) {
                Invoke-IconCallbacks -Id $ctx.Id -Path $ctx.OutPath
            } else {
                $script:iconFailedThisSession.Add($ctx.Id) | Out-Null
                Invoke-IconCallbacks -Id $ctx.Id -Path $null
            }
        } | Out-Null
}

function Get-AppIconAsync {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$OnReady,
        [string]$Source
    )

    # Disk cache hit -> defer callback to a Background tick so a burst of
    # card renders doesn't stall the UI thread.
    $cached = Get-CachedIconPath -Id $Id
    if (Test-Path $cached) {
        $captured     = $OnReady
        $capturedPath = $cached
        $action = {
            try { & $captured $capturedPath } catch {}
        }.GetNewClosure()
        $window.Dispatcher.BeginInvoke([action]$action,
            [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
        return
    }

    # Already failed this session - don't keep retrying
    if ($script:iconFailedThisSession.Contains($Id)) {
        & $OnReady $null
        return
    }

    # Coalesce concurrent requests for the same Id
    if ($script:iconPendingCallbacks.ContainsKey($Id)) {
        $script:iconPendingCallbacks[$Id].Add($OnReady) | Out-Null
        return
    }
    $script:iconPendingCallbacks[$Id] = [System.Collections.Generic.List[scriptblock]]::new()
    $script:iconPendingCallbacks[$Id].Add($OnReady) | Out-Null

    # Route meta lookup through the serial coordinator
    Get-AppMetaAsync -Id $Id -Source $Source -OnReady ({
        param($meta, $err)
        if ($err -or -not $meta) {
            $script:iconFailedThisSession.Add($Id) | Out-Null
            Invoke-IconCallbacks -Id $Id -Path $null
            return
        }
        $domain = Get-DomainFromMeta -Meta $meta
        if (-not $domain) {
            $script:iconFailedThisSession.Add($Id) | Out-Null
            Invoke-IconCallbacks -Id $Id -Path $null
            return
        }
        Fetch-FaviconAsync -Id $Id -Domain $domain
    }.GetNewClosure())
}

function Swap-BadgeToIcon {
    param([System.Windows.Controls.Border]$Target, [string]$Path, [int]$Size = 32)
    if (-not $Path) { return }
    $img = Load-ImageFromCache -Path $Path
    if (-not $img) { return }
    $imgCtl              = New-Object System.Windows.Controls.Image
    $imgCtl.Source       = $img
    $imgCtl.Width        = $Size
    $imgCtl.Height       = $Size
    $imgCtl.Stretch      = [System.Windows.Media.Stretch]::Uniform
    $Target.Child        = $imgCtl
    # Adopt a subtle background so light favicons stay visible
    $Target.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "SurfaceBrush")
}


# ── App detail side panel ────────────────────────────────────────
$appDetailPanel       = Find "AppDetailPanel"
$appDetailClose       = Find "AppDetailClose"
$appDetailIconHost    = Find "AppDetailIconHost"
$appDetailName        = Find "AppDetailName"
$appDetailPublisher   = Find "AppDetailPublisher"
$appDetailId          = Find "AppDetailId"
$appDetailVersion     = Find "AppDetailVersion"
$appDetailSource      = Find "AppDetailSource"
$appDetailDescription = Find "AppDetailDescription"
$appDetailAction      = Find "AppDetailAction"

# Cache of parsed `winget show` results keyed by Id.
$script:appMetaCache = @{}
# Id currently displayed in the detail panel (guards stale async writes).
$global:appDetailCurrentId = $null

# winget show is localized by Windows UI culture, so match keys against a
# multi-language alias table. Add more languages as needed.
$script:wingetFieldAliases = @{
    Description  = @('Description', 'Beschreibung', 'Descripción', 'Descrizione',
                     'Description', 'Descrição', 'Beschrijving', '描述', '說明',
                     '説明', '설명', 'Описание', 'Açıklama')
    Publisher    = @('Publisher', 'Herausgeber', 'Editor', 'Editore', 'Éditeur',
                     'Uitgever', '发布者', '發行者', '発行元', '게시자',
                     'Издатель', 'Yayıncı')
    PublisherUrl = @('Publisher Url', 'Herausgeber-URL', 'URL del editor',
                     'URL de l''éditeur', 'URL dell''editore', 'URL do editor',
                     'URL издателя', 'Publisher URL')
    Homepage     = @('Homepage', 'Startseite', 'Página principal', 'Page d''accueil',
                     'Pagina iniziale', 'Página inicial', 'Главная страница',
                     'Ana sayfa', '主页', '首頁', 'ホームページ', '홈페이지')
    Version      = @('Version', 'Versión', 'Versione', 'Версия', '版本',
                     'バージョン', '버전', 'Sürüm')
}

function Resolve-WingetField {
    param([string]$Key)
    foreach ($field in $script:wingetFieldAliases.Keys) {
        foreach ($alias in $script:wingetFieldAliases[$field]) {
            if ($Key -ieq $alias) { return $field }
        }
    }
    return $null
}

function Parse-WingetShowOutput {
    param([string[]]$Lines)
    $meta = @{
        Description  = ""
        Publisher    = ""
        PublisherUrl = ""
        Homepage     = ""
        Version      = ""
        Source       = ""
    }
    # Strip ANSI + CR
    $clean = @($Lines | ForEach-Object { ($_ -replace '\x1B\[[0-9;]*[mK]', '') -replace '\r', '' })
    $current = $null
    foreach ($raw in $clean) {
        $line = [string]$raw
        if ([string]::IsNullOrWhiteSpace($line)) { $current = $null; continue }
        if ($line -match '^\s{2,}\S' -and $null -ne $current -and $current -eq 'Description') {
            # Indented continuation of the description block
            $meta[$current] = (($meta[$current]) + ' ' + $line.Trim()).Trim()
            continue
        }
        $idx = $line.IndexOf(':')
        if ($idx -lt 1) { $current = $null; continue }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim()
        $field = Resolve-WingetField -Key $key
        if ($field) {
            $meta[$field] = $val
            $current = $field
        } else {
            $current = $null
        }
    }
    return $meta
}

function Set-AppDetailMeta {
    param([string]$Id, [hashtable]$Meta)
    if ($global:appDetailCurrentId -ne $Id) { return }  # Panel moved on
    if ($Meta.Version)   { $appDetailVersion.Text   = "v" + $Meta.Version }
    if ($Meta.Publisher) { $appDetailPublisher.Text = $Meta.Publisher }

    # Don't overwrite a hardcoded curated description with the fetched manifest copy.
    if ($global:appDetailDescriptionLocked) { return }

    if ($Meta.Description) {
        $appDetailDescription.Text = $Meta.Description
    } else {
        $appDetailDescription.Text = "No description provided by the manifest."
    }
}

function Show-AppDetailPanel {
    param([string]$Id, [string]$Name, [string]$Source, [string]$Description, [switch]$SkipMeta)

    $global:appDetailCurrentId = $Id

    # Reset fields
    $appDetailName.Text        = $Name
    $appDetailId.Text          = $Id
    $appDetailPublisher.Text   = ""
    $appDetailVersion.Text     = ""
    $appDetailSource.Text      = if ($Source) { $Source } else { "winget" }

    # Description resolution:
    # - Hardcoded curated description: render instantly, lock against overwrite
    # - SkipMeta (winget search result): empty + no fetch (collapses the spacer)
    # - Else: "Loading..." placeholder while async winget-show runs
    if ($Description) {
        $appDetailDescription.Text         = $Description
        $global:appDetailDescriptionLocked = $true
    } elseif ($SkipMeta) {
        $appDetailDescription.Text         = ""
        $global:appDetailDescriptionLocked = $true
    } else {
        $appDetailDescription.Text         = "Loading..."
        $global:appDetailDescriptionLocked = $false
    }

    # Icon: cached icon -> embed immediately; otherwise show a loading
    # placeholder and async-swap to favicon (or letter fallback on failure).
    $cachedIconPath = Get-CachedIconPath -Id $Id
    if (Test-Path $cachedIconPath) {
        Swap-BadgeToIcon -Target $appDetailIconHost -Path $cachedIconPath -Size 64
    } else {
        # Reset themed background a previous app may have left behind
        $appDetailIconHost.ClearValue([System.Windows.Controls.Border]::BackgroundProperty)
        $appDetailIconHost.Child = New-LoadingBadge -Size 64
        $expectedId      = $Id
        $capturedHost    = $appDetailIconHost
        $capturedName    = $Name
        $capturedId      = $Id
        Get-AppIconAsync -Id $Id -Name $Name -Source $Source -OnReady ({
            param($iconPath)
            if ($global:appDetailCurrentId -ne $expectedId) { return }
            if ($iconPath) {
                Swap-BadgeToIcon -Target $capturedHost -Path $iconPath -Size 64
            } else {
                # Replace the loading placeholder inside the host with a letter badge.
                $capturedHost.Child = New-LetterBadge -Name $capturedName -Id $capturedId -Size 64
            }
        }.GetNewClosure())
    }

    # Action button: Install (refresh when we know if installed - Phase 4 task)
    $appDetailAction.Content   = "Install"
    $appDetailAction.IsEnabled = $true
    $appDetailAction.Style     = $window.Resources["ActionButton"]
    $appDetailAction.Tag       = @{ Id = $Id; Name = $Name; Source = $Source }

    $appDetailPanel.Visibility = "Visible"

    # If we already have a hardcoded description we don't need winget-show at all
    # for this panel - the icon path has its own (independent) meta lookup when
    # the favicon isn't on disk.
    if ($global:appDetailDescriptionLocked) { return }

    # Route through the serial meta coordinator so we never duplicate
    # 'winget show' for the same id (cards request the same data).
    $detailExpectedId = $Id
    Get-AppMetaAsync -Id $Id -Source $Source -OnReady ({
        param($meta, $err)
        if ($global:appDetailCurrentId -ne $detailExpectedId) { return }
        if ($err -or -not $meta) {
            $appDetailDescription.Text = "Could not load details."
            return
        }
        Set-AppDetailMeta -Id $detailExpectedId -Meta $meta
    }.GetNewClosure())
}

function Hide-AppDetailPanel {
    $global:appDetailCurrentId         = $null
    $global:appDetailDescriptionLocked = $false
    $appDetailPanel.Visibility         = "Collapsed"
}

$appDetailClose.Add_Click({ Hide-AppDetailPanel })

$appDetailAction.Add_Click({
    param($s, $e)
    $info = $s.Tag
    if (-not $info) { return }
    Install-StoreSingleApp -Id $info.Id -Name $info.Name -TriggerButton $s -Source $info.Source
})

# Hide the panel automatically when leaving the Store sub-tab.
$pkgNavInstalled.Add_Click({ Hide-AppDetailPanel })
$pkgNavUpdates.Add_Click({   Hide-AppDetailPanel })


function Show-StoreLanding {
    $storeCategoriesPanel.Children.Clear()
    $storeHeaderText.Text       = "Browse"
    $storeCategoryArea.Visibility = "Collapsed"
    $storeSearchArea.Visibility = "Collapsed"
    $storeCategoriesPanel.Visibility = "Visible"

    # Group merged quick installs by category, fall back to "Other"
    $groups = @{}
    foreach ($qi in (Get-MergedQuickInstalls)) {
        $cat = if ([string]::IsNullOrWhiteSpace($qi.Category)) { "Other" } else { [string]$qi.Category }
        if (-not $groups.ContainsKey($cat)) { $groups[$cat] = 0 }
        $groups[$cat] = $groups[$cat] + 1
    }
    foreach ($cat in ($groups.Keys | Sort-Object)) {
        $tile = New-CategoryTile -Category $cat -Count $groups[$cat]
        $storeCategoriesPanel.Children.Add($tile) | Out-Null
    }
}

function Show-StoreCategory {
    param([string]$Category)
    $storeCategoryAppsPanel.Children.Clear()
    $storeCategoryName.Text       = $Category
    $storeHeaderText.Text         = "Browse"
    $storeCategoriesPanel.Visibility = "Collapsed"
    $storeSearchArea.Visibility = "Collapsed"
    $storeCategoryArea.Visibility = "Visible"

    foreach ($qi in (Get-MergedQuickInstalls)) {
        $cat = if ([string]::IsNullOrWhiteSpace($qi.Category)) { "Other" } else { [string]$qi.Category }
        if ($cat -ne $Category) { continue }
        $sub  = if ($qi.IsCurated) { "Curated - " + $qi.Id } else { $qi.Id }
        $src  = if ($qi.ContainsKey("Source"))      { [string]$qi.Source }      else { $null }
        $desc = if ($qi.ContainsKey("Description")) { [string]$qi.Description } else { $null }
        $card = New-AppCard -Name $qi.Name -Id $qi.Id -Subtitle $sub -Source $src -Description $desc -IsCurated:$qi.IsCurated
        $storeCategoryAppsPanel.Children.Add($card) | Out-Null
    }
}

# Live curated-first search. Empty query returns to the landing view; non-empty
# filters Get-MergedQuickInstalls and shows the matches as cards. A "Search
# winget" button below lets the user opt into a slower full registry query.
$script:storeSearchCuratedHits = @{}   # Id -> $true (so winget de-dup can skip)

function Show-StoreSearch {
    param([string]$Query)

    Hide-AppDetailPanel

    $q = ($Query | ForEach-Object { $_ }).Trim()
    if ([string]::IsNullOrWhiteSpace($q)) { Show-StoreLanding; return }

    $storeCategoriesPanel.Visibility = "Collapsed"
    $storeCategoryArea.Visibility    = "Collapsed"
    $storeSearchArea.Visibility      = "Visible"
    $storeSearchCuratedPanel.Children.Clear()
    $storeSearchWingetPanel.Children.Clear()
    $storeSearchWingetStatus.Visibility = "Collapsed"
    $script:storeSearchCuratedHits = @{}

    $qLower = $q.ToLower()
    $matches = @(Get-MergedQuickInstalls | Where-Object {
        ($_.Name -and $_.Name.ToLower().Contains($qLower)) -or
        ($_.Id   -and $_.Id.ToLower().Contains($qLower))   -or
        ($_.Category -and $_.Category.ToLower().Contains($qLower))
    })

    if ($matches.Count -eq 0) {
        $storeSearchHeader.Text = "No matches in the curated catalog for '" + $q + "'"
    } else {
        $word = if ($matches.Count -eq 1) { "match" } else { "matches" }
        $storeSearchHeader.Text = [string]$matches.Count + " curated " + $word + " for '" + $q + "'"
        foreach ($qi in $matches) {
            $sub  = if ($qi.IsCurated) { "Curated - " + $qi.Id } else { $qi.Id }
            $src  = if ($qi.ContainsKey("Source"))      { [string]$qi.Source }      else { $null }
            $desc = if ($qi.ContainsKey("Description")) { [string]$qi.Description } else { $null }
            $card = New-AppCard -Name $qi.Name -Id $qi.Id -Subtitle $sub -Source $src -Description $desc -IsCurated:$qi.IsCurated
            $storeSearchCuratedPanel.Children.Add($card) | Out-Null
            $script:storeSearchCuratedHits[[string]$qi.Id] = $true
        }
    }

    $btnStoreSearchWinget.Content = "Search winget for '" + $q + "'"
    $btnStoreSearchWinget.IsEnabled = $true
    $btnStoreSearchWinget.Tag = $q
}

function Search-StoreWinget {
    param([string]$Query)
    if ([string]::IsNullOrWhiteSpace($Query)) { return }

    $storeSearchWingetPanel.Children.Clear()
    $storeSearchWingetStatus.Visibility = "Visible"
    $storeSearchWingetStatus.Text       = "Searching winget..."
    $btnStoreSearchWinget.IsEnabled     = $false
    Set-BusyStatus "Searching winget..."

    Start-ScyJob `
        -Variables @{ wingetQuery = $Query } `
        -Context   @{ Query = $Query } `
        -Work {
            param($emit)
            $raw   = & winget search $wingetQuery --accept-source-agreements 2>&1
            $lines = @($raw | ForEach-Object { [string]$_ })
            return @{ Lines = $lines }
        } `
        -OnComplete {
            param($result, $err, $ctx)
            Set-ReadyStatus
            $btnStoreSearchWinget.IsEnabled = $true

            if ($err) {
                $storeSearchWingetStatus.Text = "winget error: " + $err.Exception.Message
                return
            }

            $rows = @(Get-WingetRows $result.Lines)
            $added = 0
            foreach ($row in $rows) {
                $name = if ($row.Count -gt 0) { $row[0].Trim() } else { "" }
                $id   = if ($row.Count -gt 1) { $row[1].Trim() } else { "" }
                if (-not $name -or -not $id) { continue }
                if ($name -eq "Name" -or $name -match '^-+$') { continue }
                if ($script:storeSearchCuratedHits.ContainsKey($id)) { continue }
                $card = New-AppCard -Name $name -Id $id -Subtitle $id -SkipIconFetch -SkipMeta
                $storeSearchWingetPanel.Children.Add($card) | Out-Null
                $added++
            }

            if ($added -eq 0) {
                $storeSearchWingetStatus.Text = "No additional results from winget."
            } else {
                $word = if ($added -eq 1) { "result" } else { "results" }
                $storeSearchWingetStatus.Text = [string]$added + " more " + $word + " from winget"
            }
        } | Out-Null
}

$storeSearchBox.Add_GotFocus({ $storeSearchPlaceholder.Visibility = "Collapsed" })
$storeSearchBox.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($storeSearchBox.Text)) {
        $storeSearchPlaceholder.Visibility = "Visible"
    }
})
$storeSearchBox.Add_TextChanged({
    $q = $storeSearchBox.Text
    $storeSearchClear.Visibility = if ($q.Length -gt 0) { "Visible" } else { "Collapsed" }
    Show-StoreSearch -Query $q
})
$storeSearchBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return -and $btnStoreSearchWinget.IsEnabled) {
        Search-StoreWinget -Query $storeSearchBox.Text
    }
})
$storeSearchClear.Add_Click({
    $storeSearchBox.Text = ""
    $storeSearchPlaceholder.Visibility = "Visible"
    $storeSearchClear.Visibility       = "Collapsed"
    Show-StoreLanding
})
$btnStoreSearchWinget.Add_Click({ Search-StoreWinget -Query $storeSearchBox.Text })

$storeCategoryBack.Add_Click({ Hide-AppDetailPanel; Show-StoreLanding })

# Refresh landing on startup, after the legacy Update-QuickInstalls has run.
$window.Dispatcher.BeginInvoke([action]{
    Show-StoreLanding
}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null


# ─────────────────────────────────────────────────────────────────
# Installed sub-tab (formerly Tab-Uninstall.ps1)
# Drives PkgSection_Installed: scan installed winget packages,
# filter, multi-select uninstall, show results.
# ─────────────────────────────────────────────────────────────────

$pkgPanel               = Find "PkgStackPanel"
$pkgCountLabel          = Find "PkgCountLabel"
$uninstallResultsCard   = Find "UninstallResultsCard"
$uninstallResultsPanel  = Find "UninstallResultsPanel"
$uninstallResultsStatus = Find "UninstallResultsStatus"
$uninstallResultsCount  = Find "UninstallResultsCount"

$script:uninstallItems = [System.Collections.Generic.List[hashtable]]::new()

function New-UninstallRow {
    param([string]$Name, [string]$Id, [string]$Version, [bool]$Alternate)

    $border = New-Object System.Windows.Controls.Border
    $bgKey = if ($Alternate) { "SurfaceBrush" } else { "InputBgBrush" }
    $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $bgKey)
    $border.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $border.Padding      = [System.Windows.Thickness]::new(10, 6, 10, 6)
    $border.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 2)
    $border.Cursor       = [System.Windows.Input.Cursors]::Hand

    $grid = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::Auto
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::Auto
    $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = [System.Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1)
    $grid.ColumnDefinitions.Add($c2); $grid.ColumnDefinitions.Add($c3)

    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Margin            = [System.Windows.Thickness]::new(0, 0, 12, 0)
    $cb.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($cb, 0)

    $nameBlock = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text              = $Name
    $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
    $nameBlock.FontSize          = 12
    $nameBlock.VerticalAlignment = "Center"
    $nameBlock.TextTrimming      = "CharacterEllipsis"
    [System.Windows.Controls.Grid]::SetColumn($nameBlock, 1)

    $idBlock = New-Object System.Windows.Controls.TextBlock
    $idBlock.Text              = $Id
    $idBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    $idBlock.FontSize          = 11
    $idBlock.Margin            = [System.Windows.Thickness]::new(12, 0, 16, 0)
    $idBlock.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($idBlock, 2)

    $verBlock = New-Object System.Windows.Controls.TextBlock
    $verBlock.Text              = $Version
    $verBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "SuccessBrush")
    $verBlock.FontSize          = 11
    $verBlock.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($verBlock, 3)

    $grid.Children.Add($cb)        | Out-Null
    $grid.Children.Add($nameBlock) | Out-Null
    $grid.Children.Add($idBlock)   | Out-Null
    $grid.Children.Add($verBlock)  | Out-Null
    $border.Child = $grid

    $border.Add_MouseLeftButtonUp(({ $cb.IsChecked = -not $cb.IsChecked }.GetNewClosure()))

    return @{ Border = $border; CheckBox = $cb; Id = $Id; Name = $Name; Tag = ($Name + " " + $Id).ToLower() }
}

function New-ResultRow {
    param([string]$Name, [string]$Id, [bool]$Success, [bool]$Alternate)

    $accentKey = if ($Success) { "SuccessBrush" } else { "DangerBrush" }
    $iconChar  = if ($Success)   { [char]0x2714 } else { [char]0x2716 }
    $statusTxt = if ($Success)   { "removed" } else { "failed" }

    $border = New-Object System.Windows.Controls.Border
    $bgKey = if ($Alternate) { "SurfaceBrush" } else { "InputBgBrush" }
    $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $bgKey)
    $border.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $border.Padding      = [System.Windows.Thickness]::new(10, 7, 10, 7)
    $border.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 2)

    $grid = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::Auto
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::Auto
    $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = [System.Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1)
    $grid.ColumnDefinitions.Add($c2); $grid.ColumnDefinitions.Add($c3)

    $icon                   = New-Object System.Windows.Controls.TextBlock
    $icon.Text              = $iconChar
    $icon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $accentKey)
    $icon.FontSize          = 13
    $icon.Margin            = [System.Windows.Thickness]::new(0, 0, 12, 0)
    $icon.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($icon, 0)

    $nameBlock                   = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text              = $Name
    $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
    $nameBlock.FontSize          = 12
    $nameBlock.VerticalAlignment = "Center"
    $nameBlock.TextTrimming      = "CharacterEllipsis"
    [System.Windows.Controls.Grid]::SetColumn($nameBlock, 1)

    $idBlock                   = New-Object System.Windows.Controls.TextBlock
    $idBlock.Text              = $Id
    $idBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    $idBlock.FontSize          = 11
    $idBlock.Margin            = [System.Windows.Thickness]::new(12, 0, 16, 0)
    $idBlock.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($idBlock, 2)

    $statusBlock                   = New-Object System.Windows.Controls.TextBlock
    $statusBlock.Text              = $statusTxt
    $statusBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $accentKey)
    $statusBlock.FontSize          = 11
    $statusBlock.FontWeight        = [System.Windows.FontWeights]::SemiBold
    $statusBlock.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($statusBlock, 3)

    $grid.Children.Add($icon)        | Out-Null
    $grid.Children.Add($nameBlock)   | Out-Null
    $grid.Children.Add($idBlock)     | Out-Null
    $grid.Children.Add($statusBlock) | Out-Null
    $border.Child = $grid

    return $border
}

(Find "BtnScanInstalled").Add_Click({
    $statusIndicator.Text       = "● Scanning..."
    $statusIndicator.Foreground = $window.Resources["WarningBrush"]
    $footerStatus.Text          = "Scy - Scanning installed apps..."
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

    $pkgPanel.Children.Clear()
    $script:uninstallItems.Clear()
    (Find "PkgSearchBox").Text               = ""
    (Find "PkgSearchPlaceholder").Visibility = "Visible"

    try {
        $raw   = & winget list --accept-source-agreements 2>&1
        $lines = @($raw | ForEach-Object { [string]$_ })
        $rows  = @(Get-WingetRows $lines)

        if ($rows.Count -eq 0) { throw "No apps returned by winget." }

        $alt = $false
        foreach ($row in $rows) {
            $name = if ($row.Count -gt 0) { $row[0] } else { "" }
            $id   = if ($row.Count -gt 1) { $row[1] } else { "" }
            $ver  = if ($row.Count -gt 2) { $row[2] } else { "" }
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $item = New-UninstallRow $name $id $ver $alt
            $pkgPanel.Children.Add($item.Border) | Out-Null
            $script:uninstallItems.Add($item)
            $alt = -not $alt
        }

        $pkgCountLabel.Text                    = [string]$script:uninstallItems.Count + " apps installed"
        (Find "PkgListBorder").Visibility       = "Visible"
        (Find "BtnUninstallSelected").IsEnabled = $true

    } catch {
        Show-ThemedDialog ("Scan failed:`n" + $_.Exception.Message) "Scan Error" "OK" "Error"
    }

    $statusIndicator.Text       = "● Ready"
    $statusIndicator.Foreground = $window.Resources["SuccessBrush"]
    $footerStatus.Text          = "Ready"
})

$script:pkgSearchClear = Find "PkgSearchClear"

(Find "PkgSearchBox").Add_TextChanged({
    $q           = (Find "PkgSearchBox").Text.ToLower()
    $placeholder = Find "PkgSearchPlaceholder"
    $placeholder.Visibility = if ($q) { "Collapsed" } else { "Visible" }
    $script:pkgSearchClear.Visibility = if ($q) { "Visible" } else { "Collapsed" }

    $visible = 0
    foreach ($item in $script:uninstallItems) {
        $show = (-not $q) -or $item.Tag.Contains($q)
        $item.Border.Visibility = if ($show) { "Visible" } else { "Collapsed" }
        if ($show) { $visible++ }
    }
    $total = $script:uninstallItems.Count
    $pkgCountLabel.Text = if ($q) { [string]$visible + " of " + [string]$total + " apps" } else { [string]$total + " apps installed" }
})

$script:pkgSearchClear.Add_Click({
    (Find "PkgSearchBox").Text = ""
})

(Find "BtnSelectAll").Add_Click({
    foreach ($item in $script:uninstallItems) { $item.CheckBox.IsChecked = $true }
})

(Find "BtnDeselectAll").Add_Click({
    foreach ($item in $script:uninstallItems) { $item.CheckBox.IsChecked = $false }
})

(Find "BtnUninstallSelected").Add_Click({
    $selected = @($script:uninstallItems | Where-Object { $_.CheckBox.IsChecked -eq $true })
    if ($selected.Count -eq 0) {
        Show-ThemedDialog "No apps selected. Click a row or check the box to select apps." "Nothing Selected" "OK" "Information"
        return
    }

    $list    = ($selected | ForEach-Object { "  - " + $_.Id }) -join "`n"
    $confirm = Show-ThemedDialog ("Uninstall " + [string]$selected.Count + " app(s)?`n`n" + $list) "Confirm Uninstall" "YesNo" "Warning"
    if ($confirm -ne "Yes") { return }

    $statusIndicator.Text       = "● Uninstalling..."
    $statusIndicator.Foreground = $window.Resources["WarningBrush"]

    $uninstallResultsPanel.Children.Clear()
    $uninstallResultsCount.Text  = ""
    $uninstallResultsStatus.Text = "Working..."
    $uninstallResultsCard.Visibility = "Visible"
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

    $succeeded = 0
    $failed    = 0
    $i         = 0
    foreach ($item in $selected) {
        $uninstallResultsStatus.Text = "Removing " + $item.Name + " (" + ($i + 1) + " of " + $selected.Count + ")..."
        $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

        & winget uninstall --id $item.Id --silent --accept-source-agreements 2>&1 | Out-Null
        $success = ($LASTEXITCODE -eq 0)

        if ($success) { $succeeded++ } else { $failed++ }

        $uninstallResultsPanel.Children.Add((New-ResultRow $item.Name $item.Id $success ($i % 2 -eq 0))) | Out-Null
        $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
        $i++
    }

    $uninstallResultsCount.Text = [string]$succeeded
    if ($failed -gt 0) {
        $uninstallResultsCount.Foreground = $window.Resources["WarningBrush"]
        $uninstallResultsStatus.Text = "$succeeded removed, $failed failed - re-scan to refresh the list"
    } else {
        $uninstallResultsCount.Foreground = $window.Resources["SuccessBrush"]
        $uninstallResultsStatus.Text = "$succeeded removed - re-scan to refresh the list"
    }

    $statusIndicator.Text       = "● Ready"
    $statusIndicator.Foreground = $window.Resources["SuccessBrush"]
})
