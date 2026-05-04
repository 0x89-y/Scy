# -- Active Directory Tab -------------------------------------------------------

# -- Banner --------------------------------------------------------------------
$adStatusBanner     = Find "AdStatusBanner"
$adStatusBannerText = Find "AdStatusBannerText"
$btnAdInstallRsat   = Find "BtnAdInstallRsat"
$btnAdRecheck       = Find "BtnAdRecheck"

# -- Sub-navigation ------------------------------------------------------------
$adNavUsers     = Find "AdNav_Users"
$adNavGroups    = Find "AdNav_Groups"
$adNavComputers = Find "AdNav_Computers"
$adNavOUs       = Find "AdNav_OUs"
$adNavDomain    = Find "AdNav_Domain"

$adSectionUsers     = Find "AdSection_Users"
$adSectionGroups    = Find "AdSection_Groups"
$adSectionComputers = Find "AdSection_Computers"
$adSectionOUs       = Find "AdSection_OUs"
$adSectionDomain    = Find "AdSection_Domain"

$script:adNavButtons = @($adNavUsers, $adNavGroups, $adNavComputers, $adNavOUs, $adNavDomain)
$script:adSections   = @($adSectionUsers, $adSectionGroups, $adSectionComputers, $adSectionOUs, $adSectionDomain)

function Set-AdSubNav {
    param([int]$Index)
    $script:adSubNavIndex = $Index
    for ($i = 0; $i -lt $script:adSections.Count; $i++) {
        $script:adSections[$i].Visibility = if ($i -eq $Index) { "Visible" } else { "Collapsed" }
        $btn = $script:adNavButtons[$i]
        if ($i -eq $Index) {
            $btn.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "FgBrush")
            $btn.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "AccentBrush")
        } else {
            $btn.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "MutedText")
            $btn.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "BorderBrush")
        }
    }
}

Set-AdSubNav 0

$adNavUsers.Add_Click({     Set-AdSubNav 0 })
$adNavGroups.Add_Click({    Set-AdSubNav 1 })
$adNavComputers.Add_Click({ Set-AdSubNav 2 })
$adNavOUs.Add_Click({       Set-AdSubNav 3 })
$adNavDomain.Add_Click({    Set-AdSubNav 4 })

# -- Action controls -----------------------------------------------------------
$adUserSearchBox          = Find "AdUserSearchBox"
$adUserSearchPlaceholder  = Find "AdUserSearchPlaceholder"
$adUserPanel              = Find "AdUserPanel"
$btnAdUserLookup          = Find "BtnAdUserLookup"

$adGroupSearchBox         = Find "AdGroupSearchBox"
$adGroupSearchPlaceholder = Find "AdGroupSearchPlaceholder"
$adGroupPanel             = Find "AdGroupPanel"
$btnAdGroupLookup         = Find "BtnAdGroupLookup"
$btnAdGroupListMembers    = Find "BtnAdGroupListMembers"

$adComputerSearchBox         = Find "AdComputerSearchBox"
$adComputerSearchPlaceholder = Find "AdComputerSearchPlaceholder"
$adComputerPanel             = Find "AdComputerPanel"
$btnAdComputerLookup         = Find "BtnAdComputerLookup"

$adOuOutput      = Find "AdOuOutput"
$btnAdOuRefresh  = Find "BtnAdOuRefresh"

$adDomainPanel   = Find "AdDomainPanel"
$adShellOutput   = Find "AdShellOutput"
$btnAdDomainInfo = Find "BtnAdDomainInfo"
$btnAdForestInfo = Find "BtnAdForestInfo"
$btnAdDcList     = Find "BtnAdDcList"
$btnAdFsmo       = Find "BtnAdFsmo"
$btnAdWhoami     = Find "BtnAdWhoami"

# Buttons that need the AD module + reachable DC. whoami stays enabled
# because it doesn't depend on the AD PowerShell module.
$script:adGatedButtons = @(
    $btnAdUserLookup,
    $btnAdGroupLookup, $btnAdGroupListMembers,
    $btnAdComputerLookup,
    $btnAdOuRefresh,
    $btnAdDomainInfo, $btnAdForestInfo, $btnAdDcList, $btnAdFsmo
)

# -- Placeholder behaviour -----------------------------------------------------
foreach ($pair in @(
    @{ Box = $adUserSearchBox;     Placeholder = $adUserSearchPlaceholder },
    @{ Box = $adGroupSearchBox;    Placeholder = $adGroupSearchPlaceholder },
    @{ Box = $adComputerSearchBox; Placeholder = $adComputerSearchPlaceholder }
)) {
    $box = $pair.Box
    $ph  = $pair.Placeholder
    $box.Tag = $ph
    $box.Add_GotFocus({ param($s,$e) $s.Tag.Visibility = "Collapsed" })
    $box.Add_LostFocus({
        param($s, $e)
        if ([string]::IsNullOrWhiteSpace($s.Text)) { $s.Tag.Visibility = "Visible" }
    })
    $box.Add_TextChanged({
        param($s, $e)
        $s.Tag.Visibility = if ([string]::IsNullOrWhiteSpace($s.Text)) { "Visible" } else { "Collapsed" }
    })
}

# -- Environment detection -----------------------------------------------------
function Test-AdEnvironment {
    $script:adModuleAvailable = $false
    $script:adDomainReachable = $false
    $script:adIsDomainJoined  = $false
    $script:adDomainName      = $null

    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $script:adIsDomainJoined = [bool]$cs.PartOfDomain
        if ($script:adIsDomainJoined) { $script:adDomainName = $cs.Domain }
    } catch {}

    if (Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue) {
        $script:adModuleAvailable = $true
        if ($script:adIsDomainJoined) {
            try {
                Import-Module ActiveDirectory -ErrorAction Stop -WarningAction SilentlyContinue
                Get-ADDomain -ErrorAction Stop | Out-Null
                $script:adDomainReachable = $true
            } catch {}
        }
    }
}

function Update-AdBannerState {
    $ready = $script:adModuleAvailable -and $script:adDomainReachable

    foreach ($b in $script:adGatedButtons) {
        $b.IsEnabled = $ready
        $b.Opacity   = if ($ready) { 1.0 } else { 0.4 }
    }

    if ($ready) {
        $adStatusBanner.Visibility = "Collapsed"
        return
    }

    if (-not $script:adModuleAvailable) {
        $adStatusBannerText.Text = "Active Directory PowerShell module not installed. Install RSAT to enable user, group, computer and OU lookups. whoami still works."
        $btnAdInstallRsat.Visibility = "Visible"
    } elseif (-not $script:adIsDomainJoined) {
        $adStatusBannerText.Text = "This computer is not joined to a domain. AD-module lookups need a reachable domain controller. whoami still works."
        $btnAdInstallRsat.Visibility = "Collapsed"
    } else {
        $adStatusBannerText.Text = "Could not reach a domain controller. Check connectivity, VPN, or credentials and click Recheck."
        $btnAdInstallRsat.Visibility = "Collapsed"
    }
    $adStatusBanner.Visibility = "Visible"
}

Test-AdEnvironment
Update-AdBannerState

# -- Job helpers ---------------------------------------------------------------
# All AD-cmdlet work runs in a worker runspace via Start-ScyJob. The runspace
# does not inherit modules, so each Work block re-imports ActiveDirectory.
function Invoke-AdJob {
    param(
        [string]$Action,
        [hashtable]$Vars = @{},
        [System.Windows.Controls.Panel]$OutputPanel,
        [string]$Banner
    )

    $OutputPanel.Children.Clear()
    if ($Banner) {
        $OutputPanel.Children.Add((New-SectionHeader $Banner)) | Out-Null
    }

    $vars2 = @{} + $Vars
    $vars2['__adAction'] = $Action

    Start-ScyJob `
        -Variables $vars2 `
        -Context @{ Panel = $OutputPanel; Alt = [ref]$false } `
        -Work {
            param($emit)
            try {
                Import-Module ActiveDirectory -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
            } catch {
                & $emit "##KVA|Status|Failed to load ActiveDirectory module: $($_.Exception.Message)|DangerBrush"
                return
            }
            try {
                $sb  = [scriptblock]::Create($__adAction)
                $out = & $sb $emit 2>&1 | Out-String
                if ($out.Trim()) { & $emit ("##LINE|" + $out.TrimEnd()) }
            } catch {
                & $emit ("##KVA|Error|" + $_.Exception.Message + "|DangerBrush")
            }
        } `
        -OnLine {
            param($line, $ctx)
            $panel = $ctx.Panel
            if ($line -eq '##CLEAR') {
                $panel.Children.Clear()
                $ctx.Alt.Value = $false
                return
            }
            if ($line -eq '##DIV') {
                $panel.Children.Add((New-Separator)) | Out-Null
                $ctx.Alt.Value = $false
                return
            }
            if ($line -like '##SECTION|*') {
                $title = $line.Substring(10)
                $panel.Children.Add((New-SectionHeader $title)) | Out-Null
                $ctx.Alt.Value = $false
                return
            }
            if ($line -like '##KV|*') {
                $rest = $line.Substring(5)
                $parts = $rest -split '\|', 2
                $label = if ($parts.Count -ge 1) { $parts[0] } else { '' }
                $value = if ($parts.Count -ge 2) { $parts[1] } else { '' }
                $row = New-InfoRow $label $value "FgBrush" $ctx.Alt.Value
                $panel.Children.Add($row) | Out-Null
                $ctx.Alt.Value = -not $ctx.Alt.Value
                return
            }
            if ($line -like '##KVA|*') {
                $rest = $line.Substring(6)
                $parts = $rest -split '\|', 3
                $label = if ($parts.Count -ge 1) { $parts[0] } else { '' }
                $value = if ($parts.Count -ge 2) { $parts[1] } else { '' }
                $brush = if ($parts.Count -ge 3 -and $parts[2]) { $parts[2] } else { 'FgBrush' }
                $row = New-InfoRow $label $value $brush $ctx.Alt.Value
                $panel.Children.Add($row) | Out-Null
                $ctx.Alt.Value = -not $ctx.Alt.Value
                return
            }
            if ($line -like '##LINE|*') {
                $panel.Children.Add((New-PlainLine ($line.Substring(7)))) | Out-Null
                return
            }
            $panel.Children.Add((New-PlainLine $line)) | Out-Null
        } `
        -OnComplete {
            param($result, $err, $ctx)
            if ($err) {
                $ctx.Panel.Children.Add((New-InfoRow "Error" ([string]$err) "DangerBrush" $false)) | Out-Null
            }
        } | Out-Null
}

function Invoke-AdTextJob {
    param(
        [string]$Action,
        [hashtable]$Vars = @{},
        [System.Windows.Controls.TextBox]$OutputBox,
        [string]$Banner
    )

    if ($Banner) {
        Write-Output-Box $OutputBox $Banner -Clear
        Write-Output-Box $OutputBox ('-' * 60)
    }

    $vars2 = @{} + $Vars
    $vars2['__adAction'] = $Action

    Start-ScyJob `
        -Variables $vars2 `
        -Context @{ Box = $OutputBox } `
        -Work {
            param($emit)
            try {
                Import-Module ActiveDirectory -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
            } catch {
                & $emit "Failed to load ActiveDirectory module: $($_.Exception.Message)"
                return
            }
            try {
                $sb  = [scriptblock]::Create($__adAction)
                $out = & $sb $emit 2>&1 | Out-String
                if ($out.Trim()) { & $emit $out.TrimEnd() }
            } catch {
                & $emit "Error: $($_.Exception.Message)"
            }
        } `
        -OnLine {
            param($line, $ctx)
            $ctx.Box.AppendText("$line`r`n")
            $ctx.Box.ScrollToEnd()
        } `
        -OnComplete {
            param($result, $err, $ctx)
            if ($err) {
                $ctx.Box.AppendText("`r`nError: $err`r`n")
                $ctx.Box.ScrollToEnd()
            }
        } | Out-Null
}

function Show-DomainOutput {
    param([ValidateSet('Cards','Shell')][string]$Mode)
    if ($Mode -eq 'Cards') {
        $adShellOutput.Visibility = 'Collapsed'
        $adDomainPanel.Visibility = 'Visible'
    } else {
        $adDomainPanel.Visibility = 'Collapsed'
        $adShellOutput.Visibility = 'Visible'
    }
}

function Invoke-AdShellJob {
    param(
        [string]$Exe,
        [string]$ArgString,
        [System.Windows.Controls.TextBox]$OutputBox,
        [string]$Banner
    )

    Write-Output-Box $OutputBox $Banner -Clear
    Write-Output-Box $OutputBox ('-' * 60)

    Start-ScyJob `
        -Variables @{ exe = $Exe; argStr = $ArgString } `
        -Context   @{ Box = $OutputBox } `
        -Work {
            param($emit)
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName               = $exe
            $psi.Arguments              = $argStr
            $psi.UseShellExecute        = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.CreateNoWindow         = $true
            $p = [System.Diagnostics.Process]::new()
            $p.StartInfo = $psi
            try {
                $p.Start() | Out-Null
            } catch {
                & $emit "Failed to start ${exe}: $($_.Exception.Message)"
                return
            }
            while (-not $p.StandardOutput.EndOfStream) {
                & $emit $p.StandardOutput.ReadLine()
            }
            $errOut = $p.StandardError.ReadToEnd()
            if ($errOut) { & $emit $errOut.TrimEnd() }
            $p.WaitForExit()
        } `
        -OnLine {
            param($line, $ctx)
            $ctx.Box.AppendText("$line`r`n")
            $ctx.Box.ScrollToEnd()
        } | Out-Null
}

# -- Banner buttons ------------------------------------------------------------
$btnAdRecheck.Add_Click({
    Test-AdEnvironment
    Update-AdBannerState
})

$btnAdInstallRsat.Add_Click({
    $confirm = Show-ThemedDialog `
        "Install the RSAT Active Directory tools? This downloads from Windows Update and may take several minutes. Requires administrator rights." `
        "Install RSAT" "YesNo" "Information"
    if ($confirm -ne "Yes") { return }

    $adStatusBannerText.Text     = "Installing RSAT Active Directory tools. This can take several minutes..."
    $btnAdInstallRsat.IsEnabled  = $false
    $btnAdInstallRsat.Opacity    = 0.4
    $btnAdRecheck.IsEnabled      = $false
    $btnAdRecheck.Opacity        = 0.4

    Start-ScyJob `
        -Context @{ Banner = $adStatusBannerText; Install = $btnAdInstallRsat; Recheck = $btnAdRecheck } `
        -Work {
            param($emit)
            try {
                $caps = Get-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools*" -ErrorAction Stop
                foreach ($c in $caps) {
                    if ($c.State -ne "Installed") {
                        & $emit "Installing $($c.Name)..."
                        Add-WindowsCapability -Online -Name $c.Name -ErrorAction Stop | Out-Null
                    } else {
                        & $emit "$($c.Name) already installed."
                    }
                }
                & $emit "Done."
                return "OK"
            } catch {
                & $emit "Error: $($_.Exception.Message)"
                throw
            }
        } `
        -OnComplete {
            param($result, $err, $ctx)
            $ctx.Install.IsEnabled = $true; $ctx.Install.Opacity = 1.0
            $ctx.Recheck.IsEnabled = $true; $ctx.Recheck.Opacity = 1.0
            Test-AdEnvironment
            Update-AdBannerState
            if ($err) {
                Show-ThemedDialog "RSAT install failed: $err`r`n`r`nMake sure Scy is running as administrator." "Install RSAT" "OK" "Error"
            } else {
                Show-ThemedDialog "RSAT install finished." "Install RSAT" "OK" "Information"
            }
        } | Out-Null
})

# -- Users ---------------------------------------------------------------------
$adUserSearchBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return) { $btnAdUserLookup.RaiseEvent(
        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }
})

$btnAdUserLookup.Add_Click({
    $q = $adUserSearchBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) {
        Show-ThemedDialog "Enter a SAM, UPN, or display name first." "Active Directory" "OK" "Information"
        return
    }
    $action = @'
param($emit)
$q  = $userQuery
$qe = $q.Replace("'", "''")
$filter = "SamAccountName -eq '$qe' -or UserPrincipalName -eq '$qe' -or Name -like '*$qe*'"
$users = Get-ADUser -Filter $filter -Properties LockedOut,LastLogonDate,Enabled,AccountExpirationDate,Description,Title,EmailAddress,PasswordLastSet,PasswordNeverExpires,Department,MemberOf -ErrorAction Stop
if (-not $users) {
    & $emit "##KV|Status|No users found matching '$q'."
    return
}
$first = $true
foreach ($u in $users) {
    if (-not $first) { & $emit '##DIV' }
    $first = $false
    & $emit ("##SECTION|" + $u.Name)
    & $emit ("##KV|SAM|" + $u.SamAccountName)
    & $emit ("##KV|UPN|" + $u.UserPrincipalName)
    if ($u.Enabled) { & $emit ("##KV|Enabled|True") }
    else            { & $emit ("##KVA|Enabled|False|DangerBrush") }
    if ($u.LockedOut) { & $emit ("##KVA|Locked out|True|WarningBrush") }
    else              { & $emit ("##KV|Locked out|False") }
    & $emit ("##KV|Last logon|" + $u.LastLogonDate)
    & $emit ("##KV|Password set|" + $u.PasswordLastSet)
    & $emit ("##KV|Pwd never expires|" + $u.PasswordNeverExpires)
    & $emit ("##KV|Account expires|" + $u.AccountExpirationDate)
    & $emit ("##KV|Title|" + $u.Title)
    & $emit ("##KV|Department|" + $u.Department)
    & $emit ("##KV|Email|" + $u.EmailAddress)
    & $emit ("##KV|Description|" + $u.Description)
    & $emit ("##KV|DN|" + $u.DistinguishedName)
    if ($u.MemberOf) {
        & $emit "##SECTION|Member of"
        foreach ($g in ($u.MemberOf | Sort-Object)) {
            & $emit ("##KV| |" + $g)
        }
    }
}
'@
    Invoke-AdJob -Action $action -Vars @{ userQuery = $q } -OutputPanel $adUserPanel -Banner "Looking up users matching '$q'..."
})

# -- Groups --------------------------------------------------------------------
$adGroupSearchBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return) { $btnAdGroupLookup.RaiseEvent(
        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }
})

$btnAdGroupLookup.Add_Click({
    $q = $adGroupSearchBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) {
        Show-ThemedDialog "Enter a group name first." "Active Directory" "OK" "Information"
        return
    }
    $action = @'
param($emit)
$q  = $groupQuery
$qe = $q.Replace("'", "''")
$filter = "Name -eq '$qe' -or SamAccountName -eq '$qe' -or Name -like '*$qe*'"
$groups = Get-ADGroup -Filter $filter -Properties Description,GroupScope,GroupCategory,ManagedBy,Members -ErrorAction Stop
if (-not $groups) {
    & $emit "##KV|Status|No groups found matching '$q'."
    return
}
$first = $true
foreach ($g in $groups) {
    if (-not $first) { & $emit '##DIV' }
    $first = $false
    & $emit ("##SECTION|" + $g.Name)
    & $emit ("##KV|SAM|" + $g.SamAccountName)
    & $emit ("##KV|Scope|" + $g.GroupScope)
    & $emit ("##KV|Category|" + $g.GroupCategory)
    & $emit ("##KV|Description|" + $g.Description)
    & $emit ("##KV|Managed by|" + $g.ManagedBy)
    & $emit ("##KV|Members|" + (@($g.Members).Count))
    & $emit ("##KV|DN|" + $g.DistinguishedName)
}
'@
    Invoke-AdJob -Action $action -Vars @{ groupQuery = $q } -OutputPanel $adGroupPanel -Banner "Looking up groups matching '$q'..."
})

$btnAdGroupListMembers.Add_Click({
    $q = $adGroupSearchBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) {
        Show-ThemedDialog "Enter a group name first." "Active Directory" "OK" "Information"
        return
    }
    $action = @'
param($emit)
$q  = $groupQuery
$qe = $q.Replace("'", "''")
$g  = Get-ADGroup -Filter "Name -eq '$qe' -or SamAccountName -eq '$qe'" -ErrorAction Stop | Select-Object -First 1
if (-not $g) { & $emit ("##KV|Status|Group '$q' not found."); return }
& $emit ("##SECTION|Members of " + $g.Name + " (recursive)")
$members = Get-ADGroupMember -Identity $g.SamAccountName -Recursive -ErrorAction Stop |
           Sort-Object objectClass, SamAccountName
if (-not $members) { & $emit "##KV|Status|(no members)"; return }
foreach ($m in $members) {
    & $emit ("##KV|" + $m.SamAccountName + "|[" + $m.objectClass + "] " + $m.Name)
}
& $emit '##DIV'
& $emit ("##KV|Total|" + @($members).Count)
'@
    Invoke-AdJob -Action $action -Vars @{ groupQuery = $q } -OutputPanel $adGroupPanel -Banner "Listing members of '$q'..."
})

# -- Computers -----------------------------------------------------------------
$adComputerSearchBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return) { $btnAdComputerLookup.RaiseEvent(
        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }
})

$btnAdComputerLookup.Add_Click({
    $q = $adComputerSearchBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) {
        Show-ThemedDialog "Enter a computer name first." "Active Directory" "OK" "Information"
        return
    }
    $action = @'
param($emit)
$q  = $computerQuery
$qe = $q.Replace("'", "''")
$filter = "Name -eq '$qe' -or DNSHostName -eq '$qe' -or Name -like '*$qe*'"
$comps = Get-ADComputer -Filter $filter -Properties OperatingSystem,OperatingSystemVersion,LastLogonDate,Enabled,Description,IPv4Address,DNSHostName -ErrorAction Stop
if (-not $comps) {
    & $emit "##KV|Status|No computers found matching '$q'."
    return
}
$first = $true
foreach ($c in $comps) {
    if (-not $first) { & $emit '##DIV' }
    $first = $false
    & $emit ("##SECTION|" + $c.Name)
    & $emit ("##KV|DNS|" + $c.DNSHostName)
    & $emit ("##KV|IPv4|" + $c.IPv4Address)
    if ($c.Enabled) { & $emit ("##KV|Enabled|True") }
    else            { & $emit ("##KVA|Enabled|False|DangerBrush") }
    & $emit ("##KV|OS|" + $c.OperatingSystem)
    & $emit ("##KV|OS version|" + $c.OperatingSystemVersion)
    & $emit ("##KV|Last logon|" + $c.LastLogonDate)
    & $emit ("##KV|Description|" + $c.Description)
    & $emit ("##KV|DN|" + $c.DistinguishedName)
}
'@
    Invoke-AdJob -Action $action -Vars @{ computerQuery = $q } -OutputPanel $adComputerPanel -Banner "Looking up computers matching '$q'..."
})

# -- OUs -----------------------------------------------------------------------
$btnAdOuRefresh.Add_Click({
    $action = @'
param($emit)
$ous = Get-ADOrganizationalUnit -Filter * -Properties Description -ErrorAction Stop |
       Sort-Object @{Expression={ $_.DistinguishedName.Length }}, DistinguishedName
if (-not $ous) { & $emit "No OUs found."; return }
& $emit ("Total OUs: " + @($ous).Count)
& $emit ""
foreach ($o in $ous) {
    $depth  = ([regex]::Matches($o.DistinguishedName, ',OU=')).Count
    $indent = ' ' * ($depth * 2)
    $line   = "{0}{1}" -f $indent, $o.Name
    if ($o.Description) { $line += "  -  $($o.Description)" }
    & $emit $line
    & $emit ("{0}    {1}" -f $indent, $o.DistinguishedName)
}
'@
    Invoke-AdTextJob -Action $action -OutputBox $adOuOutput -Banner "Loading organizational units..."
})

# -- Domain --------------------------------------------------------------------
$btnAdDomainInfo.Add_Click({
    Show-DomainOutput -Mode Cards
    $action = @'
param($emit)
$d = Get-ADDomain -ErrorAction Stop
& $emit "##SECTION|Domain"
& $emit ("##KV|DNS root|" + $d.DNSRoot)
& $emit ("##KV|NetBIOS name|" + $d.NetBIOSName)
& $emit ("##KV|Domain mode|" + $d.DomainMode)
& $emit ("##KV|PDC emulator|" + $d.PDCEmulator)
& $emit ("##KV|RID master|" + $d.RIDMaster)
& $emit ("##KV|Infrastructure master|" + $d.InfrastructureMaster)
& $emit ("##KV|Forest|" + $d.Forest)
& $emit ("##KV|Domain SID|" + $d.DomainSID)
& $emit ("##KV|Distinguished name|" + $d.DistinguishedName)
& $emit "##SECTION|Domain controllers"
foreach ($dc in (Get-ADDomainController -Filter * -ErrorAction Stop | Sort-Object Name)) {
    & $emit ("##KV|" + $dc.Name + "|" + $dc.Site)
}
'@
    Invoke-AdJob -Action $action -OutputPanel $adDomainPanel -Banner "Domain info"
})

$btnAdForestInfo.Add_Click({
    Show-DomainOutput -Mode Cards
    $action = @'
param($emit)
$f = Get-ADForest -ErrorAction Stop
& $emit "##SECTION|Forest"
& $emit ("##KV|Name|" + $f.Name)
& $emit ("##KV|Forest mode|" + $f.ForestMode)
& $emit ("##KV|Schema master|" + $f.SchemaMaster)
& $emit ("##KV|Naming master|" + $f.DomainNamingMaster)
& $emit ("##KV|Root domain|" + $f.RootDomain)
& $emit ("##KV|Domains|" + ($f.Domains -join ', '))
& $emit ("##KV|Sites|" + ($f.Sites -join ', '))
& $emit ("##KV|Global catalogs|" + ($f.GlobalCatalogs -join ', '))
& $emit ("##KV|UPN suffixes|" + ($f.UPNSuffixes -join ', '))
'@
    Invoke-AdJob -Action $action -OutputPanel $adDomainPanel -Banner "Forest info"
})

$btnAdDcList.Add_Click({
    Show-DomainOutput -Mode Cards
    $action = @'
param($emit)
$dcs = Get-ADDomainController -Filter * -ErrorAction Stop | Sort-Object Site, Name
& $emit ("##KV|Total DCs|" + @($dcs).Count)
$first = $true
foreach ($dc in $dcs) {
    if (-not $first) { & $emit '##DIV' }
    $first = $false
    & $emit ("##SECTION|" + $dc.Name)
    & $emit ("##KV|Hostname|" + $dc.HostName)
    & $emit ("##KV|IP|" + $dc.IPv4Address)
    & $emit ("##KV|Site|" + $dc.Site)
    & $emit ("##KV|OS|" + $dc.OperatingSystem)
    & $emit ("##KV|Global catalog|" + $dc.IsGlobalCatalog)
    & $emit ("##KV|Read only|" + $dc.IsReadOnly)
}
'@
    Invoke-AdJob -Action $action -OutputPanel $adDomainPanel -Banner "Domain controllers"
})

$btnAdFsmo.Add_Click({
    Show-DomainOutput -Mode Cards
    $action = @'
param($emit)
$d = Get-ADDomain -ErrorAction Stop
$f = Get-ADForest -ErrorAction Stop
& $emit "##SECTION|Domain-level FSMO roles"
& $emit ("##KV|PDC emulator|" + $d.PDCEmulator)
& $emit ("##KV|RID master|" + $d.RIDMaster)
& $emit ("##KV|Infrastructure master|" + $d.InfrastructureMaster)
& $emit "##SECTION|Forest-level FSMO roles"
& $emit ("##KV|Schema master|" + $f.SchemaMaster)
& $emit ("##KV|Domain naming master|" + $f.DomainNamingMaster)
'@
    Invoke-AdJob -Action $action -OutputPanel $adDomainPanel -Banner "FSMO roles"
})

$btnAdWhoami.Add_Click({
    Show-DomainOutput -Mode Shell
    Invoke-AdShellJob -Exe "whoami" -ArgString "/all" -OutputBox $adShellOutput -Banner "whoami /all"
})
