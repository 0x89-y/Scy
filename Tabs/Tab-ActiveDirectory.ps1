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
            $btn.Foreground  = $window.Resources["FgBrush"]
            $btn.BorderBrush = $window.Resources["AccentBrush"]
        } else {
            $btn.Foreground  = $window.Resources["MutedText"]
            $btn.BorderBrush = $window.Resources["BorderBrush"]
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
$adUserOutput             = Find "AdUserOutput"
$btnAdUserLookup          = Find "BtnAdUserLookup"
$btnAdUserUnlock          = Find "BtnAdUserUnlock"
$btnAdUserResetPwd        = Find "BtnAdUserResetPwd"
$btnAdUserEnable          = Find "BtnAdUserEnable"
$btnAdUserDisable         = Find "BtnAdUserDisable"

$adGroupSearchBox         = Find "AdGroupSearchBox"
$adGroupSearchPlaceholder = Find "AdGroupSearchPlaceholder"
$adGroupOutput            = Find "AdGroupOutput"
$btnAdGroupLookup         = Find "BtnAdGroupLookup"
$btnAdGroupListMembers    = Find "BtnAdGroupListMembers"

$adComputerSearchBox         = Find "AdComputerSearchBox"
$adComputerSearchPlaceholder = Find "AdComputerSearchPlaceholder"
$adComputerOutput            = Find "AdComputerOutput"
$btnAdComputerLookup         = Find "BtnAdComputerLookup"
$btnAdComputerEnable         = Find "BtnAdComputerEnable"
$btnAdComputerDisable        = Find "BtnAdComputerDisable"

$adOuOutput      = Find "AdOuOutput"
$btnAdOuRefresh  = Find "BtnAdOuRefresh"

$adDomainOutput  = Find "AdDomainOutput"
$btnAdDomainInfo = Find "BtnAdDomainInfo"
$btnAdForestInfo = Find "BtnAdForestInfo"
$btnAdDcList     = Find "BtnAdDcList"
$btnAdFsmo       = Find "BtnAdFsmo"
$btnAdWhoami     = Find "BtnAdWhoami"
$btnAdKlist      = Find "BtnAdKlist"
$btnAdNltest     = Find "BtnAdNltest"

# Buttons that need the AD module + reachable DC. whoami/klist/nltest stay
# enabled because they don't depend on the AD PowerShell module.
$script:adGatedButtons = @(
    $btnAdUserLookup, $btnAdUserUnlock, $btnAdUserResetPwd, $btnAdUserEnable, $btnAdUserDisable,
    $btnAdGroupLookup, $btnAdGroupListMembers,
    $btnAdComputerLookup, $btnAdComputerEnable, $btnAdComputerDisable,
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
        $adStatusBannerText.Text = "Active Directory PowerShell module not installed. Install RSAT to enable user, group, computer and OU lookups. whoami / klist / nltest still work."
        $btnAdInstallRsat.Visibility = "Visible"
    } elseif (-not $script:adIsDomainJoined) {
        $adStatusBannerText.Text = "This computer is not joined to a domain. AD-module lookups need a reachable domain controller. whoami / klist / nltest still work."
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

# -- Helpers -------------------------------------------------------------------
function New-AdTempPassword {
    $upper = [char[]](65..90)
    $lower = [char[]](97..122)
    $digit = [char[]](48..57)
    $sym   = '!@#$%^&*-_'.ToCharArray()
    $all   = $upper + $lower + $digit + $sym
    $rng   = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = [byte[]]::new(16)
    $rng.GetBytes($bytes)
    $chars = for ($i = 0; $i -lt 16; $i++) { $all[$bytes[$i] % $all.Length] }
    # Force at least one of each category in the first four positions
    $rng.GetBytes($bytes)
    $chars[0] = $upper[$bytes[0] % $upper.Length]
    $chars[1] = $lower[$bytes[1] % $lower.Length]
    $chars[2] = $digit[$bytes[2] % $digit.Length]
    $chars[3] = $sym[$bytes[3] % $sym.Length]
    -join $chars
}

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
    & $emit "No users found matching '$q'."
    return
}
$first = $true
foreach ($u in $users) {
    if (-not $first) { & $emit ""; & $emit ("-" * 40) }
    $first = $false
    & $emit ("Name              : " + $u.Name)
    & $emit ("SAM               : " + $u.SamAccountName)
    & $emit ("UPN               : " + $u.UserPrincipalName)
    & $emit ("Enabled           : " + $u.Enabled)
    & $emit ("Locked out        : " + $u.LockedOut)
    & $emit ("Last logon        : " + $u.LastLogonDate)
    & $emit ("Password set      : " + $u.PasswordLastSet)
    & $emit ("Pwd never expires : " + $u.PasswordNeverExpires)
    & $emit ("Account expires   : " + $u.AccountExpirationDate)
    & $emit ("Title             : " + $u.Title)
    & $emit ("Department        : " + $u.Department)
    & $emit ("Email             : " + $u.EmailAddress)
    & $emit ("Description       : " + $u.Description)
    & $emit ("DN                : " + $u.DistinguishedName)
    if ($u.MemberOf) {
        & $emit ""
        & $emit "Member of:"
        foreach ($g in ($u.MemberOf | Sort-Object)) { & $emit "  $g" }
    }
}
'@
    Invoke-AdJob -Action $action -Vars @{ userQuery = $q } -OutputBox $adUserOutput -Banner "Looking up users matching '$q'..."
})

$btnAdUserUnlock.Add_Click({
    $q = $adUserSearchBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) {
        Show-ThemedDialog "Enter a user identifier first." "Active Directory" "OK" "Information"
        return
    }
    $confirm = Show-ThemedDialog "Unlock the account '$q'?" "Unlock account" "YesNo" "Warning"
    if ($confirm -ne "Yes") { return }
    $action = @'
param($emit)
$q = $userQuery
$qe = $q.Replace("'", "''")
$u = Get-ADUser -Filter "SamAccountName -eq '$qe' -or UserPrincipalName -eq '$qe'" -ErrorAction Stop | Select-Object -First 1
if (-not $u) { & $emit "User '$q' not found."; return }
Unlock-ADAccount -Identity $u.SamAccountName -ErrorAction Stop
& $emit "Unlocked $($u.SamAccountName)."
'@
    Invoke-AdJob -Action $action -Vars @{ userQuery = $q } -OutputBox $adUserOutput -Banner "Unlocking '$q'..."
})

$btnAdUserResetPwd.Add_Click({
    $q = $adUserSearchBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) {
        Show-ThemedDialog "Enter a user identifier first." "Active Directory" "OK" "Information"
        return
    }
    $confirm = Show-ThemedDialog `
        "Reset the password for '$q'? A new temporary password will be generated and the user will be required to change it at next logon." `
        "Reset password" "YesNo" "Warning"
    if ($confirm -ne "Yes") { return }

    $temp = New-AdTempPassword
    $action = @'
param($emit)
$q = $userQuery
$qe = $q.Replace("'", "''")
$u = Get-ADUser -Filter "SamAccountName -eq '$qe' -or UserPrincipalName -eq '$qe'" -ErrorAction Stop | Select-Object -First 1
if (-not $u) { & $emit "User '$q' not found."; return }
$secure = ConvertTo-SecureString $tempPwd -AsPlainText -Force
Set-ADAccountPassword -Identity $u.SamAccountName -Reset -NewPassword $secure -ErrorAction Stop
Set-ADUser -Identity $u.SamAccountName -ChangePasswordAtLogon $true -ErrorAction Stop
& $emit "Password reset for $($u.SamAccountName)."
& $emit ""
& $emit "Temporary password: $tempPwd"
& $emit ""
& $emit "User must change password at next logon."
'@
    Invoke-AdJob -Action $action -Vars @{ userQuery = $q; tempPwd = $temp } -OutputBox $adUserOutput -Banner "Resetting password for '$q'..."
})

$btnAdUserEnable.Add_Click({
    $q = $adUserSearchBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) {
        Show-ThemedDialog "Enter a user identifier first." "Active Directory" "OK" "Information"
        return
    }
    $action = @'
param($emit)
$q = $userQuery
$qe = $q.Replace("'", "''")
$u = Get-ADUser -Filter "SamAccountName -eq '$qe' -or UserPrincipalName -eq '$qe'" -ErrorAction Stop | Select-Object -First 1
if (-not $u) { & $emit "User '$q' not found."; return }
Enable-ADAccount -Identity $u.SamAccountName -ErrorAction Stop
& $emit "Enabled $($u.SamAccountName)."
'@
    Invoke-AdJob -Action $action -Vars @{ userQuery = $q } -OutputBox $adUserOutput -Banner "Enabling '$q'..."
})

$btnAdUserDisable.Add_Click({
    $q = $adUserSearchBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) {
        Show-ThemedDialog "Enter a user identifier first." "Active Directory" "OK" "Information"
        return
    }
    $confirm = Show-ThemedDialog "Disable the account '$q'?" "Disable account" "YesNo" "Warning"
    if ($confirm -ne "Yes") { return }
    $action = @'
param($emit)
$q = $userQuery
$qe = $q.Replace("'", "''")
$u = Get-ADUser -Filter "SamAccountName -eq '$qe' -or UserPrincipalName -eq '$qe'" -ErrorAction Stop | Select-Object -First 1
if (-not $u) { & $emit "User '$q' not found."; return }
Disable-ADAccount -Identity $u.SamAccountName -ErrorAction Stop
& $emit "Disabled $($u.SamAccountName)."
'@
    Invoke-AdJob -Action $action -Vars @{ userQuery = $q } -OutputBox $adUserOutput -Banner "Disabling '$q'..."
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
    & $emit "No groups found matching '$q'."
    return
}
$first = $true
foreach ($g in $groups) {
    if (-not $first) { & $emit ""; & $emit ("-" * 40) }
    $first = $false
    & $emit ("Name        : " + $g.Name)
    & $emit ("SAM         : " + $g.SamAccountName)
    & $emit ("Scope       : " + $g.GroupScope)
    & $emit ("Category    : " + $g.GroupCategory)
    & $emit ("Description : " + $g.Description)
    & $emit ("Managed by  : " + $g.ManagedBy)
    & $emit ("Members     : " + (@($g.Members).Count))
    & $emit ("DN          : " + $g.DistinguishedName)
}
'@
    Invoke-AdJob -Action $action -Vars @{ groupQuery = $q } -OutputBox $adGroupOutput -Banner "Looking up groups matching '$q'..."
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
if (-not $g) { & $emit "Group '$q' not found."; return }
& $emit ("Members of " + $g.Name + " (recursive):")
& $emit ""
$members = Get-ADGroupMember -Identity $g.SamAccountName -Recursive -ErrorAction Stop |
           Sort-Object objectClass, SamAccountName
if (-not $members) { & $emit "(no members)"; return }
foreach ($m in $members) {
    $kind = $m.objectClass
    & $emit ("  [{0,-8}] {1}  ({2})" -f $kind, $m.Name, $m.SamAccountName)
}
& $emit ""
& $emit ("Total: " + @($members).Count)
'@
    Invoke-AdJob -Action $action -Vars @{ groupQuery = $q } -OutputBox $adGroupOutput -Banner "Listing members of '$q'..."
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
    & $emit "No computers found matching '$q'."
    return
}
$first = $true
foreach ($c in $comps) {
    if (-not $first) { & $emit ""; & $emit ("-" * 40) }
    $first = $false
    & $emit ("Name        : " + $c.Name)
    & $emit ("DNS         : " + $c.DNSHostName)
    & $emit ("IPv4        : " + $c.IPv4Address)
    & $emit ("Enabled     : " + $c.Enabled)
    & $emit ("OS          : " + $c.OperatingSystem)
    & $emit ("OS version  : " + $c.OperatingSystemVersion)
    & $emit ("Last logon  : " + $c.LastLogonDate)
    & $emit ("Description : " + $c.Description)
    & $emit ("DN          : " + $c.DistinguishedName)
}
'@
    Invoke-AdJob -Action $action -Vars @{ computerQuery = $q } -OutputBox $adComputerOutput -Banner "Looking up computers matching '$q'..."
})

$btnAdComputerEnable.Add_Click({
    $q = $adComputerSearchBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) {
        Show-ThemedDialog "Enter a computer name first." "Active Directory" "OK" "Information"
        return
    }
    $action = @'
param($emit)
$q  = $computerQuery
$qe = $q.Replace("'", "''")
$c  = Get-ADComputer -Filter "Name -eq '$qe'" -ErrorAction Stop | Select-Object -First 1
if (-not $c) { & $emit "Computer '$q' not found."; return }
Enable-ADAccount -Identity $c.SamAccountName -ErrorAction Stop
& $emit "Enabled $($c.Name)."
'@
    Invoke-AdJob -Action $action -Vars @{ computerQuery = $q } -OutputBox $adComputerOutput -Banner "Enabling '$q'..."
})

$btnAdComputerDisable.Add_Click({
    $q = $adComputerSearchBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) {
        Show-ThemedDialog "Enter a computer name first." "Active Directory" "OK" "Information"
        return
    }
    $confirm = Show-ThemedDialog "Disable the computer account '$q'?" "Disable computer" "YesNo" "Warning"
    if ($confirm -ne "Yes") { return }
    $action = @'
param($emit)
$q  = $computerQuery
$qe = $q.Replace("'", "''")
$c  = Get-ADComputer -Filter "Name -eq '$qe'" -ErrorAction Stop | Select-Object -First 1
if (-not $c) { & $emit "Computer '$q' not found."; return }
Disable-ADAccount -Identity $c.SamAccountName -ErrorAction Stop
& $emit "Disabled $($c.Name)."
'@
    Invoke-AdJob -Action $action -Vars @{ computerQuery = $q } -OutputBox $adComputerOutput -Banner "Disabling '$q'..."
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
    Invoke-AdJob -Action $action -OutputBox $adOuOutput -Banner "Loading organizational units..."
})

# -- Domain --------------------------------------------------------------------
$btnAdDomainInfo.Add_Click({
    $action = @'
param($emit)
$d = Get-ADDomain -ErrorAction Stop
& $emit ("DNS root            : " + $d.DNSRoot)
& $emit ("NetBIOS name        : " + $d.NetBIOSName)
& $emit ("Domain mode         : " + $d.DomainMode)
& $emit ("PDC emulator        : " + $d.PDCEmulator)
& $emit ("RID master          : " + $d.RIDMaster)
& $emit ("Infrastructure mstr : " + $d.InfrastructureMaster)
& $emit ("Forest              : " + $d.Forest)
& $emit ("Domain SID          : " + $d.DomainSID)
& $emit ("Distinguished name  : " + $d.DistinguishedName)
& $emit ""
& $emit ("Domain controllers  :")
foreach ($dc in (Get-ADDomainController -Filter * -ErrorAction Stop | Sort-Object Name)) {
    & $emit ("  - " + $dc.Name + "  (" + $dc.Site + ")")
}
'@
    Invoke-AdJob -Action $action -OutputBox $adDomainOutput -Banner "Domain info..."
})

$btnAdForestInfo.Add_Click({
    $action = @'
param($emit)
$f = Get-ADForest -ErrorAction Stop
& $emit ("Name              : " + $f.Name)
& $emit ("Forest mode       : " + $f.ForestMode)
& $emit ("Schema master     : " + $f.SchemaMaster)
& $emit ("Naming master     : " + $f.DomainNamingMaster)
& $emit ("Root domain       : " + $f.RootDomain)
& $emit ("Domains           : " + ($f.Domains -join ', '))
& $emit ("Sites             : " + ($f.Sites -join ', '))
& $emit ("Global catalogs   : " + ($f.GlobalCatalogs -join ', '))
& $emit ("UPN suffixes      : " + ($f.UPNSuffixes -join ', '))
'@
    Invoke-AdJob -Action $action -OutputBox $adDomainOutput -Banner "Forest info..."
})

$btnAdDcList.Add_Click({
    $action = @'
param($emit)
$dcs = Get-ADDomainController -Filter * -ErrorAction Stop | Sort-Object Site, Name
& $emit ("Total DCs: " + @($dcs).Count)
& $emit ""
foreach ($dc in $dcs) {
    & $emit ("Name      : " + $dc.Name)
    & $emit ("  Hostname  : " + $dc.HostName)
    & $emit ("  IP        : " + $dc.IPv4Address)
    & $emit ("  Site      : " + $dc.Site)
    & $emit ("  OS        : " + $dc.OperatingSystem)
    & $emit ("  Global cat: " + $dc.IsGlobalCatalog)
    & $emit ("  Read only : " + $dc.IsReadOnly)
    & $emit ""
}
'@
    Invoke-AdJob -Action $action -OutputBox $adDomainOutput -Banner "Listing domain controllers..."
})

$btnAdFsmo.Add_Click({
    $action = @'
param($emit)
$d = Get-ADDomain -ErrorAction Stop
$f = Get-ADForest -ErrorAction Stop
& $emit "Domain-level FSMO roles:"
& $emit ("  PDC emulator        : " + $d.PDCEmulator)
& $emit ("  RID master          : " + $d.RIDMaster)
& $emit ("  Infrastructure mstr : " + $d.InfrastructureMaster)
& $emit ""
& $emit "Forest-level FSMO roles:"
& $emit ("  Schema master       : " + $f.SchemaMaster)
& $emit ("  Domain naming master: " + $f.DomainNamingMaster)
'@
    Invoke-AdJob -Action $action -OutputBox $adDomainOutput -Banner "FSMO roles..."
})

$btnAdWhoami.Add_Click({
    Invoke-AdShellJob -Exe "whoami" -ArgString "/upn /groups /fqdn" -OutputBox $adDomainOutput -Banner "whoami /upn /groups /fqdn"
})

$btnAdKlist.Add_Click({
    Invoke-AdShellJob -Exe "klist" -ArgString "" -OutputBox $adDomainOutput -Banner "klist (kerberos tickets)"
})

$btnAdNltest.Add_Click({
    if ($script:adIsDomainJoined -and $script:adDomainName) {
        $nlArgs = "/dsgetdc:$($script:adDomainName)"
    } else {
        $nlArgs = "/dsgetdc:"
    }
    Invoke-AdShellJob -Exe "nltest" -ArgString $nlArgs -OutputBox $adDomainOutput -Banner "nltest $nlArgs"
})
