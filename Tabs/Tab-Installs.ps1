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

# Installed-app awareness: filled from the Installed-apps scan the user runs (see
# Set-StoreInstalledFromScan), so the store can swap Install for Uninstall and
# show an "Installed" pill. We never run winget just because a tab was opened.
$script:installedWingetIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Test-AppInstalled {
    param([string]$Id)
    if ([string]::IsNullOrWhiteSpace($Id)) { return $false }
    return $script:installedWingetIds.Contains($Id)
}

# -- Apps navigation ----------------------------------------------------------
# The old Store/Installed/Updates pills are gone: the category rail is now the
# only Apps navigation. Every view lives inside PkgSection_Store (which holds the
# rail), and the rail swaps the content column between:
#   All apps / <category>  -> the app grid
#   Local installers       -> PkgSection_Local
#   Installed              -> PkgSection_Installed
#   Updates                -> PkgSection_Updates
$pkgSectionStore     = Find "PkgSection_Store"
$pkgSectionInstalled = Find "PkgSection_Installed"
$pkgSectionUpdates   = Find "PkgSection_Updates"
$pkgSectionLocal     = Find "PkgSection_Local"

# Back-compat shim: Global Search and Apply-Theme still address the old
# sub-nav by index, so map those indices onto the rail selection.
function Set-PkgSubNav {
    param([int]$Index)
    $script:pkgSubNavIndex = $Index
    $target = switch ($Index) {
        1 { $script:storeInstalledCategoryLabel }
        2 { $script:storeUpdatesCategoryLabel }
        default { $script:storeAllCategoryLabel }
    }
    if (Get-Command Show-StoreCategory -ErrorAction SilentlyContinue) {
        Show-StoreCategory $target
    }
}

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

# Set-BusyStatus / Set-ReadyStatus / Show-ScyToast now live in Helpers-Status.ps1.

# -- Quick Install (dynamic, persisted in settings) ---------------------------
$script:quickInstalls      = [System.Collections.Generic.List[hashtable]]::new()
$script:quickBundles       = [System.Collections.Generic.List[hashtable]]::new()

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
    @{ Name = "Firefox";                  Id = "Mozilla.Firefox";                   Category = "Browsers";       Homepage = "mozilla.org";              Description = "Open-source web browser from Mozilla." }
    @{ Name = "Brave";                    Id = "Brave.Brave";                       Category = "Browsers";       Homepage = "brave.com";                Description = "Chromium browser with built-in ad and tracker blocking." }
    @{ Name = "Zen";                      Id = "Zen-Team.Zen-Browser";              Category = "Browsers";       Homepage = "zen-browser.app";          Description = "Firefox-based browser with workspaces and focus features." }
    @{ Name = "Helium";                   Id = "imputnet.helium";                   Category = "Browsers";       Homepage = "helium.computer";          Description = "Lightweight Chromium fork focused on speed and privacy." }
    @{ Name = "Vivaldi";                  Id = "Vivaldi.Vivaldi";                   Category = "Browsers";       Homepage = "vivaldi.com";              Description = "Highly customizable Chromium browser with tab stacking and built-in tools." }
    @{ Name = "LibreWolf";                Id = "LibreWolf.LibreWolf";               Category = "Browsers";       Homepage = "librewolf.net";            Description = "Hardened Firefox fork with privacy-first defaults." }
    @{ Name = "Tor Browser";              Id = "TorProject.TorBrowser";             Category = "Browsers";       Homepage = "torproject.org";           Description = "Routes traffic through the Tor network for anonymous browsing." }

    # Communication
    @{ Name = "Discord";                  Id = "Discord.Discord";                   Category = "Communication";  Homepage = "discord.com";              Description = "Voice, video, and text chat for communities." }
    @{ Name = "Element";                  Id = "Element.Element";                   Category = "Communication";  Homepage = "element.io";               Description = "Matrix client for end-to-end encrypted team chat." }
    @{ Name = "Signal";                   Id = "OpenWhisperSystems.Signal";         Category = "Communication";  Homepage = "signal.org";               Description = "End-to-end encrypted messenger with voice and video calls." }
    @{ Name = "Telegram";                 Id = "Telegram.TelegramDesktop";          Category = "Communication";  Homepage = "telegram.org";             Description = "Cloud-based messenger with channels, bots, and large groups." }
    @{ Name = "Thunderbird";              Id = "Mozilla.Thunderbird";               Category = "Communication";  Homepage = "thunderbird.net";          Description = "Mozilla's open-source email, calendar, and feed client." }
    @{ Name = "SimpleX Chat";             Id = "SimpleXChat.SimpleX-Desktop";       Category = "Communication";  Homepage = "simplex.chat";             Description = "Messenger that requires no user IDs or phone numbers." }

    # Media
    @{ Name = "VLC";                      Id = "VideoLAN.VLC";                      Category = "Media";          Homepage = "videolan.org";             Description = "Plays nearly any audio and video format." }
    @{ Name = "Spotify";                  Id = "Spotify.Spotify";                   Category = "Media";          Homepage = "spotify.com";              Description = "Music streaming client." }
    @{ Name = "MusicBee";                 Id = "MusicBee.MusicBee";                 Category = "Media";          Homepage = "getmusicbee.com";          Description = "Local music library player with rich tagging." }
    @{ Name = "OBS Studio";               Id = "OBSProject.OBSStudio";              Category = "Media";          Homepage = "obsproject.com";           Description = "Live streaming and screen recording." }
    @{ Name = "GIMP";                     Id = "GIMP.GIMP";                         Category = "Media";          Homepage = "gimp.org";                 Description = "Open-source raster image editor." }
    @{ Name = "Audacity";                 Id = "Audacity.Audacity";                 Category = "Media";          Homepage = "audacityteam.org";         Description = "Multi-track audio recording and editing." }
    @{ Name = "HandBrake";                Id = "HandBrake.HandBrake";               Category = "Media";          Homepage = "handbrake.fr";             Description = "Video transcoder for converting between formats." }
    @{ Name = "Inkscape";                 Id = "Inkscape.Inkscape";                 Category = "Media";          Homepage = "inkscape.org";             Description = "Vector graphics editor." }
    @{ Name = "Krita";                    Id = "KDE.Krita";                         Category = "Media";          Homepage = "krita.org";                Description = "Digital painting and illustration." }
    @{ Name = "Blender";                  Id = "BlenderFoundation.Blender";         Category = "Media";          Homepage = "blender.org";              Description = "3D modeling, animation, and rendering suite." }
    @{ Name = "mpv";                      Id = "shinchiro.mpv";                     Category = "Media";          Homepage = "mpv.io";                   Description = "Minimalist scriptable media player." }
    @{ Name = "Plex";                     Id = "Plex.Plex";                         Category = "Media";          Homepage = "plex.tv";                  Description = "Client for the Plex media server." }
    @{ Name = "Jellyfin Media Player";    Id = "Jellyfin.JellyfinMediaPlayer";      Category = "Media";          Homepage = "jellyfin.org";             Description = "Client for the open-source Jellyfin media server." }
    @{ Name = "DaVinci Resolve";          Id = "BlackmagicDesign.DaVinciResolve";   Category = "Media";          Homepage = "blackmagicdesign.com";     Description = "Professional video editing and color grading." }
    @{ Name = "Emby";                     Id = "9NBLGGH4T70L";                      Category = "Media";          Source = "msstore"; Homepage = "emby.media";  Description = "Client for the Emby media server." }

    # Utilities
    @{ Name = "7-Zip";                    Id = "7zip.7zip";                         Category = "Utilities";      Homepage = "7-zip.org";                Description = "High-ratio file archiver." }
    @{ Name = "Notepad++";                Id = "Notepad++.Notepad++";               Category = "Utilities";      Homepage = "notepad-plus-plus.org";    Description = "Lightweight tabbed text and code editor." }
    @{ Name = "Everything";               Id = "voidtools.Everything";              Category = "Utilities";      Homepage = "voidtools.com";            Description = "Instant filename search across the file system." }
    @{ Name = "PowerToys";                Id = "Microsoft.PowerToys";               Category = "Utilities";                                              Description = "Microsoft's set of power-user utilities for Windows." }
    @{ Name = "ShareX";                   Id = "ShareX.ShareX";                     Category = "Utilities";      Homepage = "getsharex.com";            Description = "Screenshot, screen recorder, and upload automation." }
    @{ Name = "qBittorrent";              Id = "qBittorrent.qBittorrent";           Category = "Utilities";      Homepage = "qbittorrent.org";          Description = "Open-source BitTorrent client." }
    @{ Name = "WizTree";                  Id = "AntibodySoftware.WizTree";          Category = "Utilities";      Homepage = "antibodysoftware.com";     Description = "Fast disk space visualizer using the NTFS MFT." }
    @{ Name = "File Pilot";               Id = "FilePilot.FilePilot";               Category = "Utilities";      Homepage = "filepilot.tech";           Description = "Modern, very fast Windows file manager." }
    @{ Name = "Ditto";                    Id = "Ditto.Ditto";                       Category = "Utilities";                                              Description = "Clipboard history manager." }
    @{ Name = "CrystalDiskInfo";          Id = "CrystalDewWorld.CrystalDiskInfo";   Category = "Utilities";      Homepage = "crystalmark.info";         Description = "Drive health monitor reading S.M.A.R.T. data." }
    @{ Name = "Greenshot";                Id = "Greenshot.Greenshot";               Category = "Utilities";      Homepage = "getgreenshot.org";         Description = "Lightweight screenshot tool with annotation." }
    @{ Name = "Flow Launcher";            Id = "Flow-Launcher.Flow-Launcher";       Category = "Utilities";      Homepage = "flowlauncher.com";         Description = "Quick app and file launcher (Alfred-style)." }
    @{ Name = "AutoHotkey";               Id = "AutoHotkey.AutoHotkey";             Category = "Utilities";      Homepage = "autohotkey.com";           Description = "Scripting language for keyboard, mouse, and UI automation." }
    @{ Name = "NanaZip";                  Id = "M2Team.NanaZip";                    Category = "Utilities";                                              Description = "Modern 7-Zip fork with extra format support." }
    @{ Name = "Files";                    Id = "Files-Community.Files";             Category = "Utilities";      Homepage = "files.community";          Description = "Tabbed modern file explorer for Windows." }
    @{ Name = "Rufus";                    Id = "Rufus.Rufus";                       Category = "Utilities";      Homepage = "rufus.ie";                 Description = "Creates bootable USB drives from ISO files." }
    @{ Name = "balenaEtcher";             Id = "Balena.Etcher";                     Category = "Utilities";      Homepage = "etcher.balena.io";         Description = "Flash OS images to SD cards and USB drives." }

    # Development
    @{ Name = "Visual Studio Code";       Id = "Microsoft.VisualStudioCode";        Category = "Development";    Homepage = "code.visualstudio.com";    Description = "Cross-platform code editor from Microsoft." }
    @{ Name = "Git";                      Id = "Git.Git";                           Category = "Development";    Homepage = "git-scm.com";              Description = "Distributed version control." }
    @{ Name = "Windows Terminal";         Id = "Microsoft.WindowsTerminal";         Category = "Development";                                              Description = "Modern terminal for Cmd, PowerShell, and WSL." }
    @{ Name = "Node.js LTS";              Id = "OpenJS.NodeJS.LTS";                 Category = "Development";    Homepage = "nodejs.org";               Description = "JavaScript runtime built on V8 (long-term-support release)." }
    @{ Name = "Python 3.12";              Id = "Python.Python.3.12";                Category = "Development";    Homepage = "python.org";               Description = "Python interpreter and tooling." }
    @{ Name = "Docker Desktop";           Id = "Docker.DockerDesktop";              Category = "Development";    Homepage = "docker.com";               Description = "Run and manage containers on Windows." }
    @{ Name = "JetBrains Toolbox";        Id = "JetBrains.Toolbox";                 Category = "Development";    Homepage = "jetbrains.com";            Description = "Installer and manager for JetBrains IDEs." }
    @{ Name = "Sublime Text";             Id = "SublimeHQ.SublimeText.4";           Category = "Development";    Homepage = "sublimetext.com";          Description = "Fast multi-language code editor." }
    @{ Name = "Postman";                  Id = "Postman.Postman";                   Category = "Development";    Homepage = "postman.com";              Description = "HTTP API client for testing and team collaboration." }
    @{ Name = "Insomnia";                 Id = "Insomnia.Insomnia";                 Category = "Development";    Homepage = "insomnia.rest";            Description = "Open-source REST, GraphQL, and gRPC API client." }
    @{ Name = "Neovim";                   Id = "Neovim.Neovim";                     Category = "Development";    Homepage = "neovim.io";                Description = "Modernized Vim with embedded scripting and async plugins." }
    @{ Name = "Cursor";                   Id = "Anysphere.Cursor";                  Category = "Development";    Homepage = "cursor.com";               Description = "AI-powered code editor based on VS Code." }
    @{ Name = "Zed";                      Id = "Zed.Zed";                           Category = "Development";    Homepage = "zed.dev";                  Description = "Fast, collaborative code editor written in Rust." }
    @{ Name = "GitHub Desktop";           Id = "GitHub.GitHubDesktop";              Category = "Development";    Homepage = "desktop.github.com";       Description = "Visual Git client for GitHub repositories." }
    @{ Name = "GitHub CLI";               Id = "GitHub.cli";                        Category = "Development";    Homepage = "cli.github.com";           Description = "Command-line tool for GitHub workflows." }
    @{ Name = "DBeaver";                  Id = "dbeaver.dbeaver";                   Category = "Development";    Homepage = "dbeaver.io";               Description = "Universal database GUI for SQL and NoSQL engines." }
    @{ Name = "MongoDB Compass";          Id = "MongoDB.Compass.Community";         Category = "Development";    Homepage = "mongodb.com";              Description = "Official GUI for MongoDB databases." }

    # Gaming
    @{ Name = "Steam";                    Id = "Valve.Steam";                       Category = "Gaming";         Homepage = "steampowered.com";         Description = "Valve's game store and library." }
    @{ Name = "Epic Games Launcher";      Id = "EpicGames.EpicGamesLauncher";       Category = "Gaming";         Homepage = "epicgames.com";            Description = "Game store and library from Epic." }
    @{ Name = "GOG Galaxy";               Id = "GOG.Galaxy";                        Category = "Gaming";         Homepage = "gog.com";                  Description = "DRM-free game library and unified launcher." }
    @{ Name = "Heroic Games Launcher";    Id = "HeroicGamesLauncher.HeroicGamesLauncher"; Category = "Gaming";   Homepage = "heroicgameslauncher.com";  Description = "Open-source launcher for Epic, GOG, and Amazon Games." }
    @{ Name = "Battle.net";               Id = "Blizzard.BattleNet";                Category = "Gaming";         Homepage = "battle.net";               Description = "Blizzard's game launcher." }
    @{ Name = "EA Desktop";               Id = "ElectronicArts.EADesktop";          Category = "Gaming";         Homepage = "ea.com";                   Description = "EA's game store and launcher." }
    @{ Name = "Ubisoft Connect";          Id = "Ubisoft.Connect";                   Category = "Gaming";         Homepage = "ubisoft.com";              Description = "Ubisoft's game launcher and store." }
    @{ Name = "itch.io";                  Id = "itchio.itch";                       Category = "Gaming";         Homepage = "itch.io";                  Description = "Indie game and asset store with built-in updates." }
    @{ Name = "Prism Launcher";           Id = "PrismLauncher.PrismLauncher";       Category = "Gaming";         Homepage = "prismlauncher.org";        Description = "Open-source Minecraft launcher with instance profiles and mod support." }
    @{ Name = "DS4Windows";               Id = "Ryochan7.DS4Windows";               Category = "Gaming";                                                  Description = "Use DualShock 4 and DualSense controllers on Windows." }
    @{ Name = "Vortex";                   Id = "Nexus-Mods.Vortex";                 Category = "Gaming";         Homepage = "nexusmods.com";            Description = "Nexus Mods' game mod manager." }

    # Productivity (LibreOffice moved to Office)
    @{ Name = "Obsidian";                 Id = "Obsidian.Obsidian";                 Category = "Productivity";   Homepage = "obsidian.md";              Description = "Markdown-based personal knowledge base." }
    @{ Name = "Notion";                   Id = "Notion.Notion";                     Category = "Productivity";   Homepage = "notion.so";                Description = "Notes, docs, and lightweight databases." }
    @{ Name = "Joplin";                   Id = "JoplinApp.Joplin";                  Category = "Productivity";   Homepage = "joplinapp.org";            Description = "Open-source notes and to-do with end-to-end encryption." }
    @{ Name = "Logseq";                   Id = "Logseq.Logseq";                     Category = "Productivity";   Homepage = "logseq.com";               Description = "Local-first outliner and knowledge graph." }
    @{ Name = "Anki";                     Id = "Anki.Anki";                         Category = "Productivity";   Homepage = "ankiweb.net";              Description = "Spaced-repetition flashcards." }
    @{ Name = "Calibre";                  Id = "calibre.calibre";                   Category = "Productivity";   Homepage = "calibre-ebook.com";        Description = "E-book library manager and converter." }
    @{ Name = "Standard Notes";           Id = "StandardNotes.StandardNotes";       Category = "Productivity";   Homepage = "standardnotes.com";        Description = "Encrypted note-taking with cross-platform sync." }

    # Security
    @{ Name = "Bitwarden";                Id = "Bitwarden.Bitwarden";               Category = "Security";       Homepage = "bitwarden.com";            Description = "Open-source password manager with cloud sync." }
    @{ Name = "Malwarebytes";             Id = "Malwarebytes.Malwarebytes";         Category = "Security";       Homepage = "malwarebytes.com";         Description = "Anti-malware scanner." }
    @{ Name = "KeePassXC";                Id = "KeePassXCTeam.KeePassXC";           Category = "Security";       Homepage = "keepassxc.org";            Description = "Local-first password manager (KeePass-compatible)." }
    @{ Name = "Cryptomator";              Id = "Cryptomator.Cryptomator";           Category = "Security";       Homepage = "cryptomator.org";          Description = "Encrypts files in any cloud storage folder." }
    @{ Name = "VeraCrypt";                Id = "IDRIX.VeraCrypt";                   Category = "Security";       Homepage = "veracrypt.fr";             Description = "Disk and container encryption (TrueCrypt successor)." }
    @{ Name = "WireGuard";                Id = "WireGuard.WireGuard";               Category = "Security";       Homepage = "wireguard.com";            Description = "Modern, fast VPN tunnel." }
    @{ Name = "Tailscale";                Id = "tailscale.tailscale";               Category = "Security";       Homepage = "tailscale.com";            Description = "Zero-config mesh VPN built on WireGuard." }

    # Network
    @{ Name = "Wireshark";                Id = "WiresharkFoundation.Wireshark";     Category = "Network";        Homepage = "wireshark.org";            Description = "Network protocol analyzer." }
    @{ Name = "PuTTY";                    Id = "PuTTY.PuTTY";                       Category = "Network";        Homepage = "putty.org";                Description = "SSH and serial terminal client." }
    @{ Name = "WinSCP";                   Id = "WinSCP.WinSCP";                     Category = "Network";        Homepage = "winscp.net";               Description = "SFTP, FTP, and SCP file transfer client." }
    @{ Name = "FileZilla";                Id = "TimKosse.FileZilla.Client";         Category = "Network";        Homepage = "filezilla-project.org";    Description = "Cross-platform FTP, FTPS, and SFTP client." }

    # Cloud & Sync
    @{ Name = "Syncthing";                Id = "Syncthing.Syncthing";               Category = "Cloud & Sync";   Homepage = "syncthing.net";            Description = "Peer-to-peer continuous file sync." }
    @{ Name = "Nextcloud Desktop";        Id = "Nextcloud.NextcloudDesktop";        Category = "Cloud & Sync";   Homepage = "nextcloud.com";            Description = "Sync client for self-hosted Nextcloud servers." }
    @{ Name = "Dropbox";                  Id = "Dropbox.Dropbox";                   Category = "Cloud & Sync";   Homepage = "dropbox.com";              Description = "File sync and sharing." }
    @{ Name = "MEGA Sync";                Id = "MEGALimited.MEGASync";              Category = "Cloud & Sync";   Homepage = "mega.io";                  Description = "Encrypted cloud storage sync client." }

    # Office (LibreOffice moved here from Productivity)
    @{ Name = "LibreOffice";              Id = "TheDocumentFoundation.LibreOffice"; Category = "Office";         Homepage = "libreoffice.org";          Description = "Free office suite with Writer, Calc, Impress, and more." }
    @{ Name = "OnlyOffice DesktopEditors"; Id = "ONLYOFFICE.DesktopEditors";        Category = "Office";         Homepage = "onlyoffice.com";           Description = "MS-Office-compatible office suite." }
)

function Get-MergedQuickInstalls {
    $userIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($qi in $script:quickInstalls) { [void]$userIds.Add([string]$qi.Id) }

    $merged = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($qi in $script:quickInstalls) {
        $src  = if ($qi.PSObject.Properties["Source"])      { [string]$qi.Source }      else { $null }
        $desc = if ($qi.PSObject.Properties["Description"]) { [string]$qi.Description } else { $null }
        $hp   = if ($qi.PSObject.Properties["Homepage"])    { [string]$qi.Homepage }    else { $null }
        $merged.Add(@{ Name = $qi.Name; Id = $qi.Id; Category = $qi.Category; IsCurated = $false; Source = $src; Description = $desc; Homepage = $hp })
    }

    foreach ($c in $script:curatedApps) {
        if ($userIds.Contains([string]$c.Id)) { continue }
        if ($c.Id -in $script:hiddenCuratedApps) { continue }
        if ($c.Category -in $script:hiddenDefaultInstallCategories) { continue }
        $src  = if ($c.ContainsKey("Source"))      { [string]$c.Source }      else { $null }
        $desc = if ($c.ContainsKey("Description")) { [string]$c.Description } else { $null }
        $hp   = if ($c.ContainsKey("Homepage"))    { [string]$c.Homepage }    else { $null }
        $merged.Add(@{ Name = $c.Name; Id = $c.Id; Category = $c.Category; IsCurated = $true; Source = $src; Description = $desc; Homepage = $hp })
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

function Update-QuickInstalls {
    $curatedPanel = Find "CuratedAppsPanel"
    $hiddenPanel  = Find "HiddenAppsPanel"
    $customPanel  = Find "CustomAppsPanel"
    if (-not $curatedPanel -or -not $hiddenPanel -or -not $customPanel) { return }

    $curatedPanel.Children.Clear()
    $hiddenPanel.Children.Clear()
    $customPanel.Children.Clear()

    # User QuickInstalls take precedence over curated ones with the same Id
    $userIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($qi in $script:quickInstalls) { [void]$userIds.Add([string]$qi.Id) }

    $curated = @($script:curatedApps | Where-Object {
        -not ($userIds.Contains([string]$_.Id)) -and
        -not ($_.Id -in $script:hiddenCuratedApps) -and
        -not ($_.Category -in $script:hiddenDefaultInstallCategories)
    } | Sort-Object Name)

    $hidden = @($script:curatedApps | Where-Object {
        $_.Id -in $script:hiddenCuratedApps
    } | Sort-Object Name)

    $custom = @($script:quickInstalls | Sort-Object Name)

    foreach ($app in $curated) {
        $row = New-QuickInstallsRow -Name $app.Name -Id $app.Id -Action "Hide" -OnAction {
            param($id)
            if (-not ($script:hiddenCuratedApps -contains $id)) {
                $script:hiddenCuratedApps.Add($id) | Out-Null
                Save-Settings
                Update-QuickInstalls
            }
        }
        $curatedPanel.Children.Add($row) | Out-Null
    }

    foreach ($app in $hidden) {
        $row = New-QuickInstallsRow -Name $app.Name -Id $app.Id -Action "Unhide" -OnAction {
            param($id)
            if ($script:hiddenCuratedApps -contains $id) {
                $script:hiddenCuratedApps.Remove($id) | Out-Null
                Save-Settings
                Update-QuickInstalls
            }
        }
        $hiddenPanel.Children.Add($row) | Out-Null
    }

    foreach ($app in $custom) {
        $row = New-CustomAppRow -Entry $app
        $customPanel.Children.Add($row) | Out-Null
    }

    # Header count badges
    $curatedCountLabel = Find "CuratedAppsCount"
    $hiddenCountLabel  = Find "HiddenAppsCount"
    $customCountLabel  = Find "CustomAppsCount"
    if ($curatedCountLabel) { $curatedCountLabel.Text = if ($curated.Count -eq 1) { "1 app" } else { [string]$curated.Count + " apps" } }
    if ($hiddenCountLabel)  { $hiddenCountLabel.Text  = if ($hidden.Count -eq 1)  { "1 app" } else { [string]$hidden.Count  + " apps" } }
    if ($customCountLabel)  { $customCountLabel.Text  = if ($custom.Count -eq 1)  { "1 app" } else { [string]$custom.Count  + " apps" } }

    # Keep the Store landing in sync with QuickInstalls changes
    if (Get-Command Show-StoreLanding -ErrorAction SilentlyContinue) {
        if ($storeCategoryArea.Visibility -ne "Visible" -and $storeSearchArea.Visibility -ne "Visible") {
            Show-StoreLanding
        }
    }
}

function New-QuickInstallsRow {
    param([string]$Name, [string]$Id, [string]$Action, [scriptblock]$OnAction)

    # cy-design divided list: flush row, hairline bottom divider only.
    $border  = New-Object System.Windows.Controls.Border
    $border.Background      = [System.Windows.Media.Brushes]::Transparent
    $border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
    $border.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
    $border.CornerRadius    = [System.Windows.CornerRadius]::new(0)
    $border.Padding         = [System.Windows.Thickness]::new(4, 10, 4, 10)
    $border.Margin          = [System.Windows.Thickness]::new(0)
    $border.Add_MouseEnter({ $this.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "HoverSurfaceBrush") })
    $border.Add_MouseLeave({ $this.Background = [System.Windows.Media.Brushes]::Transparent })

    $grid = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1)

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($stack, 0)

    $nameBlock = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text       = $Name
    $nameBlock.FontSize   = 12
    $nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
    $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
    $nameBlock.TextTrimming = "CharacterEllipsis"

    $idBlock = New-Object System.Windows.Controls.TextBlock
    $idBlock.Text       = $Id
    $idBlock.FontSize   = 11
    $idBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    $idBlock.TextTrimming = "CharacterEllipsis"
    $idBlock.Margin     = [System.Windows.Thickness]::new(0, 2, 0, 0)

    $stack.Children.Add($nameBlock) | Out-Null
    $stack.Children.Add($idBlock)   | Out-Null

    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = $Action
    $btn.Style   = $window.Resources["SecondaryButton"]
    $btn.Tag     = @{ Id = $Id; OnAction = $OnAction }
    $btn.Margin  = [System.Windows.Thickness]::new(8, 0, 0, 0)
    [System.Windows.Controls.Grid]::SetColumn($btn, 1)
    $btn.Add_Click({
        param($s, $e)
        $info = $s.Tag
        & $info.OnAction $info.Id
    })

    $grid.Children.Add($stack) | Out-Null
    $grid.Children.Add($btn)   | Out-Null
    $border.Child = $grid
    return $border
}

function New-CustomAppRow {
    param([hashtable]$Entry)

    # cy-design divided list: flush row, hairline bottom divider only.
    $border  = New-Object System.Windows.Controls.Border
    $border.Background      = [System.Windows.Media.Brushes]::Transparent
    $border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
    $border.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
    $border.CornerRadius    = [System.Windows.CornerRadius]::new(0)
    $border.Padding         = [System.Windows.Thickness]::new(4, 10, 4, 10)
    $border.Margin          = [System.Windows.Thickness]::new(0)
    $border.Add_MouseEnter({ $this.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "HoverSurfaceBrush") })
    $border.Add_MouseLeave({ $this.Background = [System.Windows.Media.Brushes]::Transparent })

    $grid = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(140)
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1); $grid.ColumnDefinitions.Add($c2)

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($stack, 0)

    $nameBlock = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text       = $Entry.Name
    $nameBlock.FontSize   = 12
    $nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
    $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")
    $nameBlock.TextTrimming = "CharacterEllipsis"

    $idBlock = New-Object System.Windows.Controls.TextBlock
    $idBlock.Text       = $Entry.Id
    $idBlock.FontSize   = 11
    $idBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
    $idBlock.TextTrimming = "CharacterEllipsis"
    $idBlock.Margin     = [System.Windows.Thickness]::new(0, 2, 0, 0)

    $stack.Children.Add($nameBlock) | Out-Null
    $stack.Children.Add($idBlock)   | Out-Null

    $catBox = New-Object System.Windows.Controls.ComboBox
    $catBox.IsEditable        = $true
    $catBox.FontSize          = 11
    $catBox.VerticalAlignment = "Center"
    $catBox.Margin            = [System.Windows.Thickness]::new(8, 0, 8, 0)
    foreach ($c in (Get-AllQuickCategories)) { $catBox.Items.Add($c) | Out-Null }
    $catBox.Text = if ($Entry.Category) { [string]$Entry.Category } else { "" }
    $catBox.Tag  = $Entry
    $catBox.Add_LostFocus({
        param($s, $e)
        $live = $s.Tag
        $newCat = [string]$s.Text
        if ([string]$live.Category -ne $newCat) {
            $live.Category = $newCat
            Save-Settings
            if (Get-Command Show-StoreLanding -ErrorAction SilentlyContinue) { Show-StoreLanding }
        }
    })
    [System.Windows.Controls.Grid]::SetColumn($catBox, 1)

    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = "Remove"
    $btn.Style   = $window.Resources["SecondaryButton"]
    $btn.Tag     = $Entry
    [System.Windows.Controls.Grid]::SetColumn($btn, 2)
    $btn.Add_Click({
        param($s, $e)
        $entry = $s.Tag
        $script:quickInstalls.Remove($entry) | Out-Null
        Save-Settings
        Update-QuickInstalls
    })

    $grid.Children.Add($stack)  | Out-Null
    $grid.Children.Add($catBox) | Out-Null
    $grid.Children.Add($btn)    | Out-Null
    $border.Child = $grid
    return $border
}

# ── Settings > Groups > Quick installs disclosure headers (collapsed by default) ──
$curatedAppsHeader   = Find "CuratedAppsHeader"
$curatedAppsContent  = Find "CuratedAppsContent"
$curatedAppsChevron  = Find "CuratedAppsChevron"
$hiddenAppsHeader    = Find "HiddenAppsHeader"
$hiddenAppsContent   = Find "HiddenAppsContent"
$hiddenAppsChevron   = Find "HiddenAppsChevron"
$customAppsHeader    = Find "CustomAppsHeader"
$customAppsContent   = Find "CustomAppsContent"
$customAppsChevron   = Find "CustomAppsChevron"

function Toggle-QuickInstallsDisclosure {
    param($Content, $Chevron)
    if ($Content.Visibility -eq "Visible") {
        $Content.Visibility = "Collapsed"
        $Chevron.Text       = [string][char]0x25B6
    } else {
        $Content.Visibility = "Visible"
        $Chevron.Text       = [string][char]0x25BC
    }
}

$curatedAppsHeader.Add_MouseLeftButtonUp({ Toggle-QuickInstallsDisclosure -Content $curatedAppsContent -Chevron $curatedAppsChevron })
$hiddenAppsHeader.Add_MouseLeftButtonUp({  Toggle-QuickInstallsDisclosure -Content $hiddenAppsContent  -Chevron $hiddenAppsChevron  })
$customAppsHeader.Add_MouseLeftButtonUp({  Toggle-QuickInstallsDisclosure -Content $customAppsContent  -Chevron $customAppsChevron  })

# ── Add custom app form (Settings > Apps & Groups > Catalog > Custom apps) ──
# Re-introduces the affordance to add user-defined apps to the Store. The
# data layer (Get-MergedQuickInstalls) and the Custom apps list already
# support these entries; this form is the missing UI to create them.
$addCustomAppNameBox         = Find "AddCustomAppNameBox"
$addCustomAppIdBox           = Find "AddCustomAppIdBox"
$addCustomAppCategoryBox     = Find "AddCustomAppCategoryBox"
$btnAddCustomApp             = Find "BtnAddCustomApp"
$addCustomAppStatus          = Find "AddCustomAppStatus"
$addCustomAppNamePlaceholder = Find "AddCustomAppNamePlaceholder"
$addCustomAppIdPlaceholder   = Find "AddCustomAppIdPlaceholder"

function Update-AddCustomAppCategories {
    $prev = [string]$addCustomAppCategoryBox.Text
    $addCustomAppCategoryBox.Items.Clear()
    foreach ($c in (Get-AllQuickCategories)) { $addCustomAppCategoryBox.Items.Add($c) | Out-Null }
    $addCustomAppCategoryBox.Text = $prev
}
Update-AddCustomAppCategories

$addCustomAppNameBox.Add_TextChanged({
    $addCustomAppNamePlaceholder.Visibility = if ($addCustomAppNameBox.Text) { "Collapsed" } else { "Visible" }
})
$addCustomAppIdBox.Add_TextChanged({
    $addCustomAppIdPlaceholder.Visibility = if ($addCustomAppIdBox.Text) { "Collapsed" } else { "Visible" }
})

function Set-AddCustomAppStatus {
    param([string]$Text, [string]$BrushKey = "MutedText")
    $addCustomAppStatus.Text = $Text
    $addCustomAppStatus.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $BrushKey)
}

function Refresh-StoreAfterCatalogChange {
    if (-not (Get-Command Show-StoreLanding -ErrorAction SilentlyContinue)) { return }
    if ($storeSearchArea.Visibility -eq "Visible") {
        Show-StoreSearch -Query $storeSearchBox.Text
    } elseif ($storeCategoryArea.Visibility -eq "Visible") {
        Show-StoreCategory -Category $storeCategoryName.Text
    } else {
        Show-StoreLanding
    }
}

function Add-CustomApp {
    param([string]$Name, [string]$Id, [string]$Category)

    $Name     = $Name.Trim()
    $Id       = $Id.Trim()
    $Category = $Category.Trim()

    if (-not $Name) {
        Set-AddCustomAppStatus -Text "Name is required." -BrushKey "DangerBrush"
        return $false
    }
    if (-not $Id) {
        Set-AddCustomAppStatus -Text "Winget Id is required." -BrushKey "DangerBrush"
        return $false
    }

    # Duplicate among existing custom apps
    foreach ($qi in $script:quickInstalls) {
        if ([string]$qi.Id -eq $Id) {
            Set-AddCustomAppStatus -Text "An app with this Id is already in your apps." -BrushKey "WarningBrush"
            return $false
        }
    }

    # If the Id matches a hidden curated app, offer to unhide it instead.
    $curated = $script:curatedApps | Where-Object { [string]$_.Id -eq $Id } | Select-Object -First 1
    if ($curated -and ($script:hiddenCuratedApps -contains $Id)) {
        $msg = "'" + [string]$curated.Name + "' is a curated app that you've hidden. Unhide it instead of adding it as custom?"
        $dlg = Show-ThemedDialog $msg "Already in catalog" "YesNoCancel" "Question"
        if ($dlg -eq "Yes") {
            $script:hiddenCuratedApps.Remove($Id) | Out-Null
            Save-Settings
            Update-QuickInstalls
            Refresh-StoreAfterCatalogChange
            Set-AddCustomAppStatus -Text ("Unhid curated app '" + [string]$curated.Name + "'.") -BrushKey "SuccessBrush"
            return $true
        } elseif ($dlg -eq "Cancel") {
            return $false
        }
        # "No" falls through and adds as a custom override.
    }

    $script:quickInstalls.Add(@{ Name = $Name; Id = $Id; Category = $Category })
    Save-Settings
    Update-QuickInstalls
    Update-AddCustomAppCategories
    Refresh-StoreAfterCatalogChange

    Set-AddCustomAppStatus -Text ("Added '" + $Name + "'.") -BrushKey "SuccessBrush"
    return $true
}

$btnAddCustomApp.Add_Click({
    $ok = Add-CustomApp -Name $addCustomAppNameBox.Text -Id $addCustomAppIdBox.Text -Category $addCustomAppCategoryBox.Text
    if ($ok) {
        $addCustomAppNameBox.Text     = ""
        $addCustomAppIdBox.Text       = ""
        $addCustomAppCategoryBox.Text = ""
    }
})

# Enter in any input triggers Add
$addCustomAppEnterHandler = {
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return) {
        $btnAddCustomApp.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        $e.Handled = $true
    }
}
$addCustomAppNameBox.Add_KeyDown($addCustomAppEnterHandler)
$addCustomAppIdBox.Add_KeyDown($addCustomAppEnterHandler)

# -- Export / import My apps list (shareable) ---------------------------------
(Find "BtnExportMyApps").Add_Click({
    if ($script:quickInstalls.Count -eq 0) {
        Show-ThemedDialog "You have no apps to export. Add some under My apps first." "Export my apps" "OK" "Information"
        return
    }
    Add-Type -AssemblyName System.Windows.Forms
    $dlg          = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title    = "Export my apps"
    $dlg.Filter   = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    $dlg.FileName = "scy-my-apps.json"
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $export = @{
        version = 1
        apps    = @($script:quickInstalls | ForEach-Object {
            @{ name = $_.Name; id = $_.Id; category = if ($_.Category) { [string]$_.Category } else { "" } }
        })
    }
    try {
        $export | ConvertTo-Json -Depth 5 | Set-Content -Path $dlg.FileName -Encoding UTF8
        if (Get-Command Write-ScyLog -ErrorAction SilentlyContinue) { Write-ScyLog "Exported $($script:quickInstalls.Count) custom app(s) to $($dlg.FileName)" }
        Show-ThemedDialog "Exported $($script:quickInstalls.Count) app(s) to:`n$($dlg.FileName)" "Done" "OK" "Information"
    } catch {
        Show-ThemedDialog ("Export failed: " + $_.Exception.Message) "Error" "OK" "Error"
    }
})

(Find "BtnImportMyApps").Add_Click({
    Add-Type -AssemblyName System.Windows.Forms
    $dlg        = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = "Import my apps"
    $dlg.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    try {
        $data  = Get-Content -Path $dlg.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
        $apps  = if ($data.apps) { @($data.apps) } else { @($data) }
        $existing = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($qi in $script:quickInstalls) { [void]$existing.Add([string]$qi.Id) }

        $added = 0; $skipped = 0
        foreach ($a in $apps) {
            $id   = [string]$a.id
            $name = [string]$a.name
            if (-not $id -or -not $name) { continue }
            if ($existing.Contains($id)) { $skipped++; continue }
            $cat = if ($a.category) { [string]$a.category } else { "" }
            $script:quickInstalls.Add(@{ Name = $name; Id = $id; Category = $cat })
            [void]$existing.Add($id)
            $added++
        }

        if ($added -gt 0) {
            Save-Settings
            Update-QuickInstalls
            if (Get-Command Update-AddCustomAppCategories -ErrorAction SilentlyContinue) { Update-AddCustomAppCategories }
            if (Get-Command Show-StoreLanding -ErrorAction SilentlyContinue) { Show-StoreLanding }
            if (Get-Command Write-ScyLog -ErrorAction SilentlyContinue) { Write-ScyLog "Imported $added custom app(s) from $($dlg.FileName)" }
        }
        $msg = "Imported $added app(s)."
        if ($skipped -gt 0) { $msg += " Skipped $skipped (already in your apps)." }
        Show-ThemedDialog $msg "Import my apps" "OK" "Information"
    } catch {
        Show-ThemedDialog ("Failed to import: " + $_.Exception.Message) "Error" "OK" "Error"
    }
})

# -- Export bundles -----------------------------------------------------------
$btnExportBundles.Add_Click({
    if ($script:quickBundles.Count -eq 0) {
        Show-ThemedDialog "No bundles to export." "Export bundles" "OK" "Information"
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
        Show-ThemedDialog $msg "Import bundles" "OK" "Information"
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

$storeCategoryList       = Find "StoreCategoryList"
$storeCategoryArea       = Find "StoreCategoryArea"
$storeCategoryAppsPanel  = Find "StoreCategoryAppsPanel"
$storeCategoryName       = Find "StoreCategoryName"   # state only (holds selected category)
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
    $border.CornerRadius = [System.Windows.CornerRadius]::new([Math]::Round($Size * 0.28))  # cy squircle avatar
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
    $border.CornerRadius = [System.Windows.CornerRadius]::new([Math]::Round($Size * 0.28))  # cy squircle avatar
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
    if (Get-Command Write-ScyLog -ErrorAction SilentlyContinue) { Write-ScyLog "Install requested: $Name ($Id)" }
    Show-ScyProgress -Border $installsProgressBorder -Bar $installsProgressBar -Label $installsProgressLabel `
                     -Text ("Installing " + $Name + "...") -Value $null -Max 1

    Start-ScyJob `
        -Variables @{ wingetId = $Id; wingetSrc = $Source } `
        -Context   @{ Name = $Name; Id = $Id; Btn = $TriggerButton } `
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
                return
            }
            # Mark installed so buttons/pills flip instantly. A full reconcile
            # happens next time the user runs the Installed-apps scan.
            [void]$script:installedWingetIds.Add([string]$ctx.Id)
            Refresh-StoreInstalledUi
        } | Out-Null
}

function Uninstall-StoreSingleApp {
    param([string]$Id, [string]$Name, $TriggerButton, [string]$Source)

    if ($script:installInProgress) { return }

    # App behavior > "Skip confirmation for single-app uninstalls" (shared with the Installed tab)
    if (-not $script:skipSingleUninstallConfirm) {
        $confirm = Show-ThemedDialog ("Uninstall " + $Name + "?") "Confirm uninstall" "YesNo" "Warning"
        if ($confirm -ne "Yes") { return }
    }

    $script:installInProgress = $true
    if ($TriggerButton) {
        $TriggerButton.IsEnabled = $false
        $TriggerButton.Content   = "Uninstalling..."
    }

    Set-BusyStatus ("Uninstalling " + $Name + "...")
    if (Get-Command Write-ScyLog -ErrorAction SilentlyContinue) { Write-ScyLog "Uninstall requested: $Name ($Id)" }
    Show-ScyProgress -Border $installsProgressBorder -Bar $installsProgressBar -Label $installsProgressLabel `
                     -Text ("Uninstalling " + $Name + "...") -Value $null -Max 1

    Start-ScyJob `
        -Variables @{ wingetId = $Id } `
        -Context   @{ Name = $Name; Id = $Id; Btn = $TriggerButton } `
        -Work {
            param($emit)
            & $emit ("Uninstalling " + $wingetId)
            & winget uninstall --id $wingetId --silent --accept-source-agreements 2>&1 | Out-Null
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
            if ($btn) { $btn.IsEnabled = $true }
            if ($err) {
                Show-ThemedDialog ("Uninstall error: " + $err.Exception.Message) "Error" "OK" "Error"
                return
            }
            if ($result.ExitCode -ne 0) {
                Show-ThemedDialog ("winget exited with code " + [string]$result.ExitCode + " uninstalling " + $ctx.Name) "Uninstall failed" "OK" "Warning"
                return
            }
            # Drop from the installed set so buttons/pills flip instantly. A full
            # reconcile happens next time the user runs the Installed-apps scan.
            [void]$script:installedWingetIds.Remove([string]$ctx.Id)
            Refresh-StoreInstalledUi
        } | Out-Null
}

# Fill the store's installed-id set from an Installed-apps scan (user-initiated
# on the Installed sub-tab). Only winget-sourced rows carry an id we can match
# against the catalog. Then refresh the store's pills/buttons in place.
function Set-StoreInstalledFromScan {
    param($Software)
    $script:installedWingetIds.Clear()
    foreach ($app in $Software) {
        if ([string]$app.Source -eq "Winget" -and -not [string]::IsNullOrWhiteSpace([string]$app.Id)) {
            [void]$script:installedWingetIds.Add([string]$app.Id)
        }
    }
    Refresh-StoreInstalledUi
}

# Update installed-state UI without rebuilding anything: toggle each card's
# "Installed" pill in place and re-evaluate the detail panel's action button.
# A full grid rebuild here would re-fetch every icon and freeze the UI thread.
function Refresh-StoreInstalledUi {
    foreach ($panelName in @("StoreCategoryAppsPanel", "StoreSearchCuratedPanel", "StoreSearchWingetPanel")) {
        $panel = Find $panelName
        if (-not $panel) { continue }
        foreach ($card in $panel.Children) {
            $tag = $card.Tag
            if ($tag -and $tag.InstalledPill) {
                $tag.InstalledPill.Visibility = if (Test-AppInstalled ([string]$tag.Id)) { "Visible" } else { "Collapsed" }
            }
        }
    }
    if ($appDetailPanel.Visibility -eq "Visible") {
        $info = $appDetailAction.Tag
        if ($info) { Set-AppDetailActionButton -Id $info.Id -Name $info.Name -Source $info.Source }
    }
}

# Set the detail panel's action button to Install or Uninstall based on whether
# the app is currently installed (per the winget index).
function Set-AppDetailActionButton {
    param([string]$Id, [string]$Name, [string]$Source)
    if (Test-AppInstalled $Id) {
        $appDetailAction.Content = "Uninstall"
        $appDetailAction.Style   = $window.Resources["DangerButton"]
        $appDetailAction.Tag     = @{ Id = $Id; Name = $Name; Source = $Source; Action = "Uninstall" }
    } else {
        $appDetailAction.Content = "Install"
        $appDetailAction.Style   = $window.Resources["ActionButton"]
        $appDetailAction.Tag     = @{ Id = $Id; Name = $Name; Source = $Source; Action = "Install" }
    }
    $appDetailAction.IsEnabled = $true
}

function New-AppCard {
    param(
        [string]$Name, [string]$Id, [string]$Subtitle = "",
        [string]$Source, [string]$Description, [string]$Homepage,
        [switch]$SkipIconFetch,      # true for raw winget search results - their icons are too expensive to fetch at bulk render time
        [switch]$SkipMeta,           # true for raw winget search results - skip description/publisher fetch on detail panel open
        [switch]$IsCurated           # attaches right-click "Hide app" context menu
    )

    # cy-design divided grid (Acy Discover style): flush tile, no fill/radius/gap.
    # A 1px hairline all round + a -1 margin collapses shared edges into single
    # dividers on both axes. Fixed size keeps the grid aligned.
    $border              = New-Object System.Windows.Controls.Border
    $border.Background      = [System.Windows.Media.Brushes]::Transparent
    $border.SetResourceReference(
        [System.Windows.Controls.Border]::BorderBrushProperty, "BorderBrush")
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $border.CornerRadius    = [System.Windows.CornerRadius]::new(0)
    # Width comes from the UniformGrid column (see Update-StoreGridColumns) so the
    # grid always fills the pane with no leftover gap on the right.
    $border.HorizontalAlignment = "Stretch"
    $border.Height          = 112
    $border.Margin          = [System.Windows.Thickness]::new(0, 0, -1, -1)
    $border.Padding         = [System.Windows.Thickness]::new(16, 14, 16, 14)
    $border.Cursor          = [System.Windows.Input.Cursors]::Hand
    $border.Add_MouseEnter({ $this.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "HoverSurfaceBrush") })
    $border.Add_MouseLeave({ $this.Background = [System.Windows.Media.Brushes]::Transparent })

    # Tile layout: badge | name + description
    $row = New-Object System.Windows.Controls.Grid
    $row.VerticalAlignment = "Top"
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
    $nameBlock.VerticalAlignment = "Center"
    $nameBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "FgBrush")

    # Name row: name (trims) + optional "Installed" pill on the right
    $nameRow = New-Object System.Windows.Controls.Grid
    $nrc0 = New-Object System.Windows.Controls.ColumnDefinition; $nrc0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $nrc1 = New-Object System.Windows.Controls.ColumnDefinition; $nrc1.Width = [System.Windows.GridLength]::Auto
    $nameRow.ColumnDefinitions.Add($nrc0); $nameRow.ColumnDefinitions.Add($nrc1)
    [System.Windows.Controls.Grid]::SetColumn($nameBlock, 0)
    $nameRow.Children.Add($nameBlock) | Out-Null

    # "Installed" pill: built for every card, shown only when installed. Building
    # it up front (and keeping a ref on the card Tag) lets the background winget
    # scan toggle it in place, so we never rebuild the grid just to add badges.
    $pill                   = New-Object System.Windows.Controls.Border
    $pill.BorderThickness   = [System.Windows.Thickness]::new(1)
    $pill.CornerRadius      = [System.Windows.CornerRadius]::new(7)
    $pill.Padding           = [System.Windows.Thickness]::new(6, 0, 6, 1)
    $pill.Margin            = [System.Windows.Thickness]::new(6, 0, 0, 0)
    $pill.VerticalAlignment = "Center"
    $pill.Visibility        = if (Test-AppInstalled $Id) { "Visible" } else { "Collapsed" }
    $pill.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "SuccessBrush")
    $pillText               = New-Object System.Windows.Controls.TextBlock
    $pillText.Text          = "Installed"
    $pillText.FontSize      = 9
    $pillText.FontWeight    = [System.Windows.FontWeights]::SemiBold
    $pillText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "SuccessBrush")
    $pill.Child             = $pillText
    [System.Windows.Controls.Grid]::SetColumn($pill, 1)
    $nameRow.Children.Add($pill) | Out-Null

    $subBlock              = New-Object System.Windows.Controls.TextBlock
    $subBlock.Text         = if (-not [string]::IsNullOrWhiteSpace($Description)) { $Description }
                             elseif (-not [string]::IsNullOrWhiteSpace($Subtitle)) { $Subtitle }
                             else { $Id }
    $subBlock.FontSize     = 11
    $subBlock.TextWrapping = "Wrap"
    $subBlock.TextTrimming = "CharacterEllipsis"
    $subBlock.MaxHeight    = 48
    $subBlock.Margin       = [System.Windows.Thickness]::new(0, 3, 0, 0)
    $subBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")

    $textStack.Children.Add($nameRow)  | Out-Null
    $textStack.Children.Add($subBlock) | Out-Null

    $row.Children.Add($badge)     | Out-Null
    $row.Children.Add($textStack) | Out-Null
    $border.Child = $row

    # Click anywhere on the card opens the detail panel
    $border.Tag = @{ Id = $Id; Name = $Name; Source = $Source; Description = $Description; Homepage = $Homepage; SkipMeta = [bool]$SkipMeta; InstalledPill = $pill }
    $border.Add_MouseLeftButtonUp({
        param($s, $e)
        $info = $s.Tag
        Show-AppDetailPanel -Id $info.Id -Name $info.Name -Source $info.Source -Description $info.Description -Homepage $info.Homepage -SkipMeta:$info.SkipMeta
    })

    # Context menu: every card gets Install first, then a source-specific action:
    # - Curated catalog cards         -> "Hide app"
    # - User-saved cards (quickInstalls) -> "Remove from my apps"
    # - Winget search-result cards    -> "Save to my apps"
    $menu = New-Object System.Windows.Controls.ContextMenu

    # Install/Uninstall: label resolved when the menu opens and action resolved on
    # click, both live against the installed index (which the background scan may
    # fill after the card was built).
    $miInstall = New-Object System.Windows.Controls.MenuItem
    $miInstall.Header = "Install"
    $miInstall.Tag    = @{ Id = $Id; Name = $Name; Source = $Source }
    $miInstall.Add_Click({
        param($s, $e)
        $info = $s.Tag
        if (Test-AppInstalled $info.Id) {
            Uninstall-StoreSingleApp -Id $info.Id -Name $info.Name -Source $info.Source
        } else {
            Install-StoreSingleApp -Id $info.Id -Name $info.Name -Source $info.Source
        }
    })
    $menu.Items.Add($miInstall) | Out-Null
    $menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    $menu.Add_Opened({
        param($s, $e)
        $mi = $s.Items[0]
        if ($mi -and $mi.Tag) {
            $mi.Header = if (Test-AppInstalled $mi.Tag.Id) { "Uninstall" } else { "Install" }
        }
    })

    if ($IsCurated) {
        $hide = New-Object System.Windows.Controls.MenuItem
        $hide.Header = "Hide app"
        $hide.Tag    = $Id
        $hide.Add_Click({
            param($s, $e)
            $hideId = [string]$s.Tag
            if (-not ($script:hiddenCuratedApps -contains $hideId)) {
                $script:hiddenCuratedApps.Add($hideId) | Out-Null
                Save-Settings
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
    } else {
        $alreadyCustom = $false
        foreach ($qi in $script:quickInstalls) {
            if ([string]$qi.Id -eq $Id) { $alreadyCustom = $true; break }
        }
        if ($alreadyCustom) {
            $miRemove = New-Object System.Windows.Controls.MenuItem
            $miRemove.Header = "Remove from my apps"
            $miRemove.Tag    = $Id
            $miRemove.Add_Click({
                param($s, $e)
                $rid = [string]$s.Tag
                $entry = $null
                foreach ($qi in $script:quickInstalls) {
                    if ([string]$qi.Id -eq $rid) { $entry = $qi; break }
                }
                if ($entry) {
                    $script:quickInstalls.Remove($entry) | Out-Null
                    Save-Settings
                    Update-QuickInstalls
                    if ($storeSearchArea.Visibility -eq "Visible") {
                        Show-StoreSearch -Query $storeSearchBox.Text
                    } elseif ($storeCategoryArea.Visibility -eq "Visible") {
                        Show-StoreCategory -Category $storeCategoryName.Text
                    } else {
                        Show-StoreLanding
                    }
                }
            })
            $menu.Items.Add($miRemove) | Out-Null
        } else {
            $miSave = New-Object System.Windows.Controls.MenuItem
            $miSave.Header = "Save to my apps"
            $miSave.Tag    = @{ Id = $Id; Name = $Name }
            $miSave.Add_Click({
                param($s, $e)
                $info = $s.Tag
                $script:quickInstalls.Add(@{ Name = $info.Name; Id = $info.Id; Category = "" })
                Save-Settings
                Update-QuickInstalls
                if (Get-Command Show-ScyToast -ErrorAction SilentlyContinue) {
                    Show-ScyToast -Title "Scy" -Body ("Saved '" + $info.Name + "' to your apps. Set a category in Settings if you want it under a Store tile.")
                }
                if ($storeSearchArea.Visibility -eq "Visible") {
                    Show-StoreSearch -Query $storeSearchBox.Text
                } elseif ($storeCategoryArea.Visibility -eq "Visible") {
                    Show-StoreCategory -Category $storeCategoryName.Text
                } else {
                    Show-StoreLanding
                }
            })
            $menu.Items.Add($miSave) | Out-Null
        }
    }

    $border.ContextMenu = $menu

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
    if (Get-Command Write-BulkLog -ErrorAction SilentlyContinue) { Write-BulkLog ("Start-MetaFetchJob " + $Id) }

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
                if (Get-Command Write-BulkLog -ErrorAction SilentlyContinue) { Write-BulkLog ("subscriber action fired for " + $msg.Id) }
                $stdout = $p.StandardOutput.ReadToEnd()
                $lines  = $stdout -split "`r?`n"
                $meta   = $null
                try { $meta = Parse-WingetShowOutput -Lines $lines } catch {}
                if ($meta) { $state.Cache[$msg.Id] = $meta }
                if (Get-Command Write-BulkLog -ErrorAction SilentlyContinue) { Write-BulkLog ("meta parsed for " + $msg.Id + " hasMeta=" + [string]([bool]$meta) + " hasHomepage=" + [string]([bool]($meta -and $meta.Homepage))) }

                if ($state.Pending.ContainsKey($msg.Id)) {
                    $cbs = $state.Pending[$msg.Id]
                    $state.Pending.Remove($msg.Id) | Out-Null
                    foreach ($cb in $cbs) { try { & $cb $meta $null } catch { if (Get-Command Write-BulkLog -ErrorAction SilentlyContinue) { Write-BulkLog ("meta cb threw: " + $_.Exception.Message) } } }
                }
                if (Get-Command Write-BulkLog -ErrorAction SilentlyContinue) { Write-BulkLog ("post-cb. Queue.Count=" + [string]$state.Queue.Count) }
                $state.Active[0] = $false

                if ($state.Queue.Count -gt 0) {
                    $nextId       = $state.Queue.Dequeue()
                    $state.Active[0] = $true
                    if (Get-Command Write-BulkLog -ErrorAction SilentlyContinue) { Write-BulkLog ("dequeued next: " + $nextId) }
                    $drainAction = { Start-MetaFetchJob -Id $nextId }.GetNewClosure()
                    $msg.Win.Dispatcher.BeginInvoke([action]$drainAction,
                        [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
                    if (Get-Command Write-BulkLog -ErrorAction SilentlyContinue) { Write-BulkLog ("BeginInvoke posted for " + $nextId) }
                }
            } catch {
                if (Get-Command Write-BulkLog -ErrorAction SilentlyContinue) { Write-BulkLog ("ACTION THREW: " + $_.Exception.Message) }
            } finally {
                if ($state.Sources.ContainsKey($msg.Id)) { $state.Sources.Remove($msg.Id) | Out-Null }
                Unregister-Event -SourceIdentifier $msg.SourceId -ErrorAction SilentlyContinue
                try { $p.Dispose() } catch {}
                if (Get-Command Write-BulkLog -ErrorAction SilentlyContinue) { Write-BulkLog ("finally done for " + $msg.Id) }
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
$global:iconPendingCallbacks = @{}
# Set of Ids we've already tried this session that returned nothing.
$global:iconFailedThisSession = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

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
    if (Get-Command Write-BulkLog -ErrorAction SilentlyContinue) { Write-BulkLog ("Invoke-IconCallbacks " + $Id + " path=" + [string]$Path + " hasPending=" + [string]$global:iconPendingCallbacks.ContainsKey($Id)) }
    if (-not $global:iconPendingCallbacks.ContainsKey($Id)) { return }
    $cbs = $global:iconPendingCallbacks[$Id]
    $global:iconPendingCallbacks.Remove($Id) | Out-Null
    foreach ($cb in $cbs) {
        try { & $cb $Path } catch { if (Get-Command Write-BulkLog -ErrorAction SilentlyContinue) { Write-BulkLog ("icon cb threw: " + $_.Exception.Message) } }
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
                $global:iconFailedThisSession.Add($ctx.Id) | Out-Null
                Invoke-IconCallbacks -Id $ctx.Id -Path $null
            }
        } | Out-Null
}

function Get-AppIconAsync {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$OnReady,
        [string]$Source,
        [switch]$Force               # bypass the auto-fetch-disable toggle (used by bulk fetch)
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

    # Auto-fetch disabled in Settings -> just report no icon, never spawn winget.
    if (-not $Force -and $script:disableAutoIconFetch) {
        & $OnReady $null
        return
    }

    # Already failed this session - don't keep retrying (Force bypasses for explicit retry)
    if (-not $Force -and $global:iconFailedThisSession.Contains($Id)) {
        & $OnReady $null
        return
    }

    # Coalesce concurrent requests for the same Id
    if ($global:iconPendingCallbacks.ContainsKey($Id)) {
        $global:iconPendingCallbacks[$Id].Add($OnReady) | Out-Null
        return
    }
    $global:iconPendingCallbacks[$Id] = [System.Collections.Generic.List[scriptblock]]::new()
    $global:iconPendingCallbacks[$Id].Add($OnReady) | Out-Null

    # Route meta lookup through the serial coordinator
    Get-AppMetaAsync -Id $Id -Source $Source -OnReady ({
        param($meta, $err)
        if ($err -or -not $meta) {
            $global:iconFailedThisSession.Add($Id) | Out-Null
            Invoke-IconCallbacks -Id $Id -Path $null
            return
        }
        $domain = Get-DomainFromMeta -Meta $meta
        if (-not $domain) {
            $global:iconFailedThisSession.Add($Id) | Out-Null
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
$appDetailPanel         = Find "AppDetailPanel"
$appDetailClose         = Find "AppDetailClose"
$appDetailIconHost      = Find "AppDetailIconHost"
$appDetailName          = Find "AppDetailName"
$appDetailPublisher     = Find "AppDetailPublisher"
$appDetailId            = Find "AppDetailId"
$appDetailHomepageHost  = Find "AppDetailHomepageHost"
$appDetailHomepageLink  = Find "AppDetailHomepageLink"
$appDetailHomepageText  = Find "AppDetailHomepageText"
$appDetailVersion       = Find "AppDetailVersion"
$appDetailSource        = Find "AppDetailSource"
$appDetailDescription   = Find "AppDetailDescription"
$appDetailAction        = Find "AppDetailAction"

# Open homepage links in the user's default browser
$appDetailHomepageLink.Add_RequestNavigate({
    param($s, $e)
    try { Start-Process $e.Uri.AbsoluteUri } catch {}
    $e.Handled = $true
})

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
    param([string]$Id, [string]$Name, [string]$Source, [string]$Description, [string]$Homepage, [switch]$SkipMeta)

    $global:appDetailCurrentId = $Id

    # Reset fields
    $appDetailName.Text        = $Name
    $appDetailId.Text          = $Id
    $appDetailPublisher.Text   = ""
    $appDetailVersion.Text     = ""
    $appDetailSource.Text      = if ($Source) { $Source } else { "winget" }

    # Homepage link (curated entries usually have one; hide for raw winget results)
    if ($Homepage) {
        $hpUrl = $Homepage
        if ($hpUrl -notmatch '^https?://') { $hpUrl = "https://" + $hpUrl }
        try {
            $appDetailHomepageLink.NavigateUri = New-Object Uri($hpUrl)
            $appDetailHomepageText.Text        = $hpUrl -replace '^https?://', ''
            $appDetailHomepageHost.Visibility  = "Visible"
        } catch {
            $appDetailHomepageHost.Visibility  = "Collapsed"
        }
    } else {
        $appDetailHomepageHost.Visibility = "Collapsed"
    }

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

    # Action button: Install, or Uninstall if the winget index says it's installed
    Set-AppDetailActionButton -Id $Id -Name $Name -Source $Source

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
    if ($info.Action -eq "Uninstall") {
        Uninstall-StoreSingleApp -Id $info.Id -Name $info.Name -TriggerButton $s -Source $info.Source
    } else {
        Install-StoreSingleApp -Id $info.Id -Name $info.Name -TriggerButton $s -Source $info.Source
    }
})

# (Leaving the app grid via the rail hides the detail panel; see Show-StoreCategory.)


# The "All apps" rail entry shows every app; category entries filter the grid.
# "Local installers" is a special rail entry that swaps the grid for that panel.
$script:storeAllCategoryLabel       = "All apps"
$script:storeLocalCategoryLabel     = "Local installers"
$script:storeInstalledCategoryLabel = "Installed"
$script:storeUpdatesCategoryLabel   = "Updates"
# Rail section header for the catalog; selecting it means "all apps"
$script:storeSectionLabel           = "Store"

# Tiles stretch to fill their UniformGrid column, so the grid never leaves a gap
# on the right. Column count = how many tiles of at least this width fit.
$script:storeTileMinWidth = 240

function Update-StoreGridColumns {
    param($Panel)
    if (-not $Panel) { return }
    $w = $Panel.ActualWidth
    if ($w -le 0) { return }
    $cols = [Math]::Floor($w / $script:storeTileMinWidth)
    if ($cols -lt 1) { $cols = 1 }
    if ($Panel.Columns -ne $cols) { $Panel.Columns = [int]$cols }
}

# Recompute columns whenever a grid panel is resized.
foreach ($gridPanelName in @("StoreCategoryAppsPanel", "StoreSearchCuratedPanel", "StoreSearchWingetPanel")) {
    $gp = Find $gridPanelName
    if ($gp) {
        $gp.Add_SizeChanged({ param($s, $e) Update-StoreGridColumns $s })
    }
}

# Count apps per category (blank category -> "Other")
function Get-StoreCategoryCounts {
    $groups = [ordered]@{}
    foreach ($qi in (Get-MergedQuickInstalls)) {
        $cat = if ([string]::IsNullOrWhiteSpace($qi.Category)) { "Other" } else { [string]$qi.Category }
        if (-not $groups.Contains($cat)) { $groups[$cat] = 0 }
        $groups[$cat] = $groups[$cat] + 1
    }
    return $groups
}

# Rebuild the category rail, marking $Active as selected.
# Two-stage rail (same shape as Bookmarks):
#   Store            <- section; acts as "all apps", carries the total
#     Browsers       <- categories, indented, only while Store is selected
#     ...
#   Local installers <- sibling sections
#   Installed
#   Updates
function Build-StoreCategoryRail {
    param([string]$Active)
    if (-not $storeCategoryList) { return }
    $storeCategoryList.Children.Clear()

    $groups = Get-StoreCategoryCounts
    $total  = 0
    foreach ($k in $groups.Keys) { $total += $groups[$k] }

    $specials = @($script:storeLocalCategoryLabel,
                  $script:storeInstalledCategoryLabel,
                  $script:storeUpdatesCategoryLabel)
    $inStore  = ($Active -notin $specials)

    # The Store section itself is "all apps"
    $storeCategoryList.Children.Add(
        (New-RailEntry -Label $script:storeSectionLabel -Count $total -IsSection $true `
                       -IsActive ($Active -eq $script:storeAllCategoryLabel) `
                       -OnClick { Show-StoreCategory $script:storeAllCategoryLabel })) | Out-Null

    if ($inStore) {
        foreach ($cat in ($groups.Keys | Sort-Object)) {
            $c = $cat
            $storeCategoryList.Children.Add(
                (New-RailEntry -Label $c -Indent 1 -Count $groups[$c] -IsActive ($Active -eq $c) `
                               -OnClick ({ Show-StoreCategory $c }).GetNewClosure())) | Out-Null
        }
    }

    # Sibling sections after the Store group (not catalog categories, so no counts)
    foreach ($special in $specials) {
        $s = $special
        $storeCategoryList.Children.Add(
            (New-RailEntry -Label $s -IsSection $true -IsActive ($Active -eq $s) `
                           -OnClick ({ Show-StoreCategory $s }).GetNewClosure())) | Out-Null
    }
}

# Landing = the "All apps" rail selection.
function Show-StoreLanding {
    Show-StoreCategory $script:storeAllCategoryLabel
}

function Show-StoreCategory {
    param([string]$Category)
    if ([string]::IsNullOrWhiteSpace($Category)) { $Category = $script:storeAllCategoryLabel }

    $storeCategoryAppsPanel.Children.Clear()
    $storeCategoryName.Text = $Category      # state for refresh paths

    # Collapse every view, then show the selected one
    $storeSearchArea.Visibility   = "Collapsed"
    $storeCategoryArea.Visibility = "Collapsed"
    if ($pkgSectionLocal)     { $pkgSectionLocal.Visibility     = "Collapsed" }
    if ($pkgSectionInstalled) { $pkgSectionInstalled.Visibility = "Collapsed" }
    if ($pkgSectionUpdates)   { $pkgSectionUpdates.Visibility   = "Collapsed" }

    Build-StoreCategoryRail -Active $Category

    switch ($Category) {
        $script:storeLocalCategoryLabel {
            if ($pkgSectionLocal) { $pkgSectionLocal.Visibility = "Visible" }
            Update-LocalInstallers
            return
        }
        $script:storeInstalledCategoryLabel {
            if ($pkgSectionInstalled) { $pkgSectionInstalled.Visibility = "Visible" }
            Hide-AppDetailPanel
            return
        }
        $script:storeUpdatesCategoryLabel {
            if ($pkgSectionUpdates) { $pkgSectionUpdates.Visibility = "Visible" }
            Hide-AppDetailPanel
            return
        }
    }

    $storeCategoryArea.Visibility = "Visible"
    $showAll = ($Category -eq $script:storeAllCategoryLabel)
    foreach ($qi in (Get-MergedQuickInstalls | Sort-Object { $_.Name })) {
        $cat = if ([string]::IsNullOrWhiteSpace($qi.Category)) { "Other" } else { [string]$qi.Category }
        if (-not $showAll -and $cat -ne $Category) { continue }
        $sub  = if ($qi.IsCurated) { "Curated - " + $qi.Id } else { $qi.Id }
        $src  = if ($qi.ContainsKey("Source"))      { [string]$qi.Source }      else { $null }
        $desc = if ($qi.ContainsKey("Description")) { [string]$qi.Description } else { $null }
        $hp   = if ($qi.ContainsKey("Homepage"))    { [string]$qi.Homepage }    else { $null }
        $card = New-AppCard -Name $qi.Name -Id $qi.Id -Subtitle $sub -Source $src -Description $desc -Homepage $hp -IsCurated:$qi.IsCurated
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

    $storeCategoryArea.Visibility    = "Collapsed"
    if ($pkgSectionLocal) { $pkgSectionLocal.Visibility = "Collapsed" }
    $storeSearchArea.Visibility      = "Visible"
    $storeSearchCuratedPanel.Children.Clear()
    $storeSearchWingetPanel.Children.Clear()
    $storeSearchWingetStatus.Visibility = "Collapsed"
    $script:storeSearchCuratedHits = @{}

    $qLower = $q.ToLower()
    $hits = @(Get-MergedQuickInstalls | Where-Object {
        ($_.Name -and $_.Name.ToLower().Contains($qLower)) -or
        ($_.Id   -and $_.Id.ToLower().Contains($qLower))   -or
        ($_.Category -and $_.Category.ToLower().Contains($qLower))
    })

    if ($hits.Count -eq 0) {
        $storeSearchHeader.Text = "No matches in the curated catalog for '" + $q + "'"
    } else {
        $word = if ($hits.Count -eq 1) { "match" } else { "matches" }
        $storeSearchHeader.Text = [string]$hits.Count + " curated " + $word + " for '" + $q + "'"
        foreach ($qi in $hits) {
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

# Refresh landing on startup, after the legacy Update-QuickInstalls has run.
$window.Dispatcher.BeginInvoke([action]{
    Show-StoreLanding
    # Apply user's preferred default sub-tab once at startup (Settings > Apps & groups > App behavior)
    if ($script:defaultAppsSubTab) {
        $idx = switch ($script:defaultAppsSubTab) {
            "Installed" { 1 }
            "Updates"   { 2 }
            default     { 0 }
        }
        Set-PkgSubNav $idx
    }
}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null


# ─────────────────────────────────────────────────────────────────
# Bulk icon prefetch (Settings > Groups > Icon cache > "Fetch all icons now")
# Bypasses winget show entirely (it takes minutes per call on cold source
# caches). Instead derives a publisher domain from the winget Id and asks
# Google's favicon service directly, falling back .com -> .org -> .io if
# the response is the small "no icon found" globe. All downloads run inside
# one background runspace, serially, so the UI thread isn't blocked by N
# runspace creations.
# ─────────────────────────────────────────────────────────────────

$btnFetchAllIcons         = Find "BtnFetchAllIcons"
$btnClearIconCache        = Find "BtnClearIconCache"
$iconFetchProgressBorder  = Find "IconFetchProgressBorder"
$iconFetchProgressBar     = Find "IconFetchProgressBar"
$iconFetchProgressLabel   = Find "IconFetchProgressLabel"

$btnClearIconCache.Add_Click({
    $dir = Get-ScyIconCacheDir
    try {
        Get-ChildItem -Path $dir -Filter "*.png" -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {}
    # Drop in-memory state so re-fetches aren't blocked by the "failed this session" flag.
    $global:iconFailedThisSession.Clear()
    $global:iconPendingCallbacks.Clear()
    $iconFetchProgressBorder.Visibility = "Visible"
    $iconFetchProgressBar.Maximum       = 1
    $iconFetchProgressBar.Value         = 0
    $iconFetchProgressLabel.Text        = "Icon cache cleared. Click 'Fetch all icons now' to repopulate."
    if (Get-Command Show-StoreLanding -ErrorAction SilentlyContinue) {
        if ($storeCategoryArea.Visibility -eq "Visible") {
            Show-StoreCategory -Category $storeCategoryName.Text
        } elseif ($storeSearchArea.Visibility -ne "Visible") {
            Show-StoreLanding
        }
    }
})

$btnFetchAllIcons.Add_Click({
    # Only fetch apps that ship an explicit Homepage. Without one we'd have
    # to guess from the winget Id and the heuristic ended up grabbing the
    # publisher's logo (Microsoft, KDE, Mozilla, etc.) instead of the
    # product's icon - confusing.
    $todoApps = @($script:curatedApps | Where-Object {
        $_.ContainsKey("Homepage") -and
        -not [string]::IsNullOrWhiteSpace($_.Homepage) -and
        -not (Test-Path (Get-CachedIconPath -Id $_.Id))
    })

    $iconFetchProgressBorder.Visibility = "Visible"

    if ($todoApps.Count -eq 0) {
        $iconFetchProgressLabel.Text = "All curated icons with a known homepage are already cached."
        $iconFetchProgressBar.Maximum = 1
        $iconFetchProgressBar.Value   = 1
        return
    }

    # Build (Id, Domain, OutPath) tuples from the curated Homepage field
    $todo = New-Object System.Collections.ArrayList
    foreach ($app in $todoApps) {
        $appId = [string]$app.Id
        $hp    = [string]$app.Homepage
        # Normalize: accept bare domains or full URLs
        if ($hp -notmatch '^https?://') { $hp = "https://" + $hp }
        $domain = $null
        try { $domain = ([Uri]$hp).Host } catch {}
        if ([string]::IsNullOrWhiteSpace($domain)) { continue }
        [void]$todo.Add(@{
            Id     = $appId
            Domain = $domain
            Out    = Get-CachedIconPath -Id $appId
        })
    }
    if ($todo.Count -eq 0) {
        $iconFetchProgressLabel.Text = "No curated homepages to fetch."
        $iconFetchProgressBar.Maximum = 1
        $iconFetchProgressBar.Value   = 1
        return
    }

    $state = @{ Total = $todo.Count; Done = 0 }
    $bar   = $iconFetchProgressBar
    $label = $iconFetchProgressLabel
    $btn   = $btnFetchAllIcons
    $catArea    = $storeCategoryArea
    $catName    = $storeCategoryName
    $searchArea = $storeSearchArea

    $bar.Maximum   = $state.Total
    $bar.Value     = 0
    $label.Text    = "0 / " + [string]$state.Total + " icons"
    $btn.IsEnabled = $false

    Start-ScyJob `
        -Variables @{ items = $todo } `
        -Context   @{ Total = $state.Total } `
        -Work {
            param($emit)
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add('User-Agent', 'Mozilla/5.0 Scy')
            foreach ($item in $items) {
                $ok = $false
                try {
                    $url = "https://www.google.com/s2/favicons?domain=" + $item.Domain + "&sz=64"
                    $wc.DownloadFile($url, $item.Out)
                    $fi = Get-Item $item.Out -ErrorAction SilentlyContinue
                    # Google returns a ~150-200 byte generic globe when the domain has no
                    # favicon. Reject those - the curated app won't get a wrong-looking icon.
                    if ($fi -and $fi.Length -gt 400) { $ok = $true }
                    elseif ($fi) { Remove-Item $item.Out -Force -ErrorAction SilentlyContinue }
                } catch {}
                & $emit @{ Id = $item.Id; Ok = $ok }
            }
            try { $wc.Dispose() } catch {}
            return @{ Total = $items.Count }
        } `
        -OnLine ({
            param($line, $ctx)
            $state.Done = [int]$state.Done + 1
            $bar.Value  = $state.Done
            $label.Text = [string]$state.Done + " / " + [string]$ctx.Total + " icons"
        }.GetNewClosure()) `
        -OnComplete ({
            param($result, $err, $ctx)
            $btn.IsEnabled = $true
            if ($err) {
                $label.Text = "Bulk fetch error: " + $err.Exception.Message
                return
            }
            $label.Text = "Done. " + [string]$ctx.Total + " icon(s) processed."
            Show-ScyToast -Title "Scy" -Body ("Icon fetch complete: " + [string]$ctx.Total + " icon(s) processed.")
            if (Get-Command Show-StoreLanding -ErrorAction SilentlyContinue) {
                if ($catArea.Visibility -eq "Visible") {
                    Show-StoreCategory -Category $catName.Text
                } elseif ($searchArea.Visibility -ne "Visible") {
                    Show-StoreLanding
                }
            }
        }.GetNewClosure()) | Out-Null
})
