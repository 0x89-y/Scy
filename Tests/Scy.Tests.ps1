# Pester 5 tests. Run all checks (analyzer + tests) with Tests\Invoke-ScyChecks.ps1.
# Targets Windows PowerShell 5.1, like Scy itself.

BeforeDiscovery {
    $root      = Split-Path $PSScriptRoot -Parent
    $psFiles   = @(Get-ChildItem $root -Recurse -Filter *.ps1 | Where-Object { $_.FullName -notlike '*\.git\*' } |
                   ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($root.Length + 1) } })
    $tweakDirs = @(Get-ChildItem (Join-Path $root 'Tweaks') -Directory | ForEach-Object { @{ Path = $_.FullName; Name = $_.Name } })
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $Root = Split-Path $PSScriptRoot -Parent
}

Describe 'Project files' {
    It 'parses: <Name>' -ForEach $psFiles {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'Scy.xaml is well-formed XML' {
        { [xml](Get-Content (Join-Path $Root 'Scy.xaml') -Raw -Encoding UTF8) } | Should -Not -Throw
    }

    It 'every control the scripts look up by name exists in Scy.xaml' {
        $xaml    = Get-Content (Join-Path $Root 'Scy.xaml') -Raw -Encoding UTF8
        $defined = @([regex]::Matches($xaml, 'x:Name="([A-Za-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value })
        $used = Get-ChildItem $Root -Recurse -Filter *.ps1 | Where-Object { $_.FullName -notlike '*\.git\*' -and $_.FullName -notlike '*\Tests\*' } |
            ForEach-Object { [regex]::Matches((Get-Content $_.FullName -Raw), '(?:\bFind|FindName\()\s*"([A-Za-z0-9_]+)"') } |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        @($used | Where-Object { $defined -notcontains $_ }) | Should -BeNullOrEmpty
    }

    It 'changelog.json has an entry for the version in version.json' {
        $version   = (Get-Content (Join-Path $Root 'version.json') -Raw | ConvertFrom-Json).version
        $changelog = Get-Content (Join-Path $Root 'changelog.json') -Raw | ConvertFrom-Json
        @($changelog | ForEach-Object { $_.version }) | Should -Contain $version
    }

    It 'the passphrase word list is complete' {
        $words = @(Get-Content (Join-Path $Root 'Assets\eff_large_wordlist.txt') | ForEach-Object { ($_ -split "`t")[1] } | Where-Object { $_ })
        $words.Count | Should -Be 7776
        @($words | Sort-Object -Unique).Count | Should -Be 7776
    }
}

Describe 'Tweak definitions' {
    It '<Name> has Apply.ps1 and a valid tweak.json' -ForEach $tweakDirs {
        Join-Path $Path 'Apply.ps1' | Should -Exist
        $meta = Get-Content (Join-Path $Path 'tweak.json') -Raw | ConvertFrom-Json
        $meta.description | Should -Not -BeNullOrEmpty
        @($meta.check).Count | Should -BeGreaterThan 0
        foreach ($c in @($meta.check)) {
            $c.path | Should -Match '^(HKCU:|HKLM:|Registry::)'
            $c.name | Should -Not -BeNullOrEmpty
            $c.PSObject.Properties.Name | Should -Contain 'value'
        }
    }
}

Describe 'Get-WingetResult' {
    BeforeAll {
        . ([scriptblock]::Create((Get-ScySource 'Scy.ps1' -Variable '$script:wingetExitCodes' -Function 'Get-WingetResult')))
    }
    It 'treats exit code 0 as success' {
        (Get-WingetResult 0).Ok | Should -BeTrue
    }
    It 'maps a known failure (0x8A150014, no package found)' {
        $r = Get-WingetResult -1978335212
        $r.Ok   | Should -BeFalse
        $r.Text | Should -Match 'No package found'
    }
    It 'counts "already up to date" (0x8A15002B) as success' {
        (Get-WingetResult -1978335189).Ok | Should -BeTrue
    }
    It 'shows unknown codes as hex' {
        (Get-WingetResult 12345).Text | Should -Be 'winget exit code 0x00003039'
    }
}

Describe 'Test-ScyAccessDenied' {
    BeforeAll {
        . ([scriptblock]::Create((Get-ScySource 'Scy.ps1' -Function 'Test-ScyAccessDenied')))
        function New-TestError($Exception, [System.Management.Automation.ErrorCategory]$Category = 'NotSpecified') {
            New-Object System.Management.Automation.ErrorRecord($Exception, 'test', $Category, $null)
        }
    }
    It 'recognises <Case>' -ForEach @(
        @{ Case = 'UnauthorizedAccessException';   Make = { New-TestError ([System.UnauthorizedAccessException]::new('x')) } }
        @{ Case = 'category PermissionDenied (CIM)'; Make = { New-TestError ([System.Exception]::new('x')) 'PermissionDenied' } }
        @{ Case = 'SecurityException (registry)';  Make = { New-TestError ([System.Security.SecurityException]::new('x')) } }
        @{ Case = 'HResult 0x80070005';            Make = { New-TestError ([System.IO.IOException]::new('x', -2147024891)) } }
        @{ Case = 'Win32 error 740';               Make = { New-TestError ([System.ComponentModel.Win32Exception]::new(740)) } }
        @{ Case = 'wrapped in an inner exception'; Make = { New-TestError ([System.Exception]::new('outer', [System.UnauthorizedAccessException]::new('inner'))) } }
    ) {
        Test-ScyAccessDenied (& $Make) | Should -BeTrue
    }
    It 'ignores <Case>' -ForEach @(
        @{ Case = 'file not found';  Make = { New-TestError ([System.IO.FileNotFoundException]::new('x')) 'ObjectNotFound' } }
        @{ Case = 'a parse error';   Make = { New-TestError ([System.FormatException]::new('x')) 'InvalidData' } }
    ) {
        Test-ScyAccessDenied (& $Make) | Should -BeFalse
    }
}

Describe 'ConvertFrom-WingetUpgradeOutput' {
    BeforeAll {
        . ([scriptblock]::Create((Get-ScySource 'Tabs\Tab-Updates.ps1' -Function 'ConvertFrom-WingetUpgradeOutput')))
        $sep = '^[-' + [char]0x2500 + ']{5,}'
    }

    It 'reads both tables of English output, including a narrow one with single-space gaps' {
        $lines = @('   - ') +
            (New-WingetTable @(26, 28, 14, 14) @('Name', 'Id', 'Version', 'Available', 'Source') @(
                , @('Mozilla Firefox', 'Mozilla.Firefox', '120.0', '121.0', 'winget')
                , @('Ubisoft Connect', 'Ubisoft.Connect', '< 174.2.0', '174.2.0', 'winget'))) +
            @('2 upgrades available.', '',
              'The following packages have an upgrade available, but require explicit targeting for upgrade:') +
            (New-WingetTable @(15, 21, 8, 11) @('Name', 'Id', 'Version', 'Available', 'Source') @(
                , @('Android Studio', 'Google.AndroidStudio', '2026.1', '2026.2.1.8', 'winget'))) +
            @('At least 1 package has a version number that cannot be determined. Use --include-unknown to see all results.',
              '1 package(s) have pins that prevent upgrade.')

        $r = ConvertFrom-WingetUpgradeOutput -Lines $lines -SeparatorPattern $sep
        @($r.Packages).Count | Should -Be 3
        $r.Summary           | Should -Be 2
        $ff = $r.Packages | Where-Object Id -eq 'Mozilla.Firefox'
        $ff.Name, $ff.Version, $ff.Available | Should -Be @('Mozilla Firefox', '120.0', '121.0')
        ($r.Packages | Where-Object Id -eq 'Ubisoft.Connect').Version | Should -Be '< 174.2.0'
        $as = $r.Packages | Where-Object Id -eq 'Google.AndroidStudio'
        $as.Version, $as.Available | Should -Be @('2026.1', '2026.2.1.8')
    }

    It 'reads localized (German) output and takes the count from the line right after the table' {
        $lines = (New-WingetTable @(22, 26, 12, 12) @('Name', 'ID', 'Version', 'Verfuegbar', 'Quelle') @(
                     , @('Element', 'Element.Element', '1.12.31', '1.12.32', 'winget')
                     , @('PowerShell 7.6.6.0-x64', 'Microsoft.PowerShell', '7.6.6.0', '7.6.7.0', 'winget')
                     , @('Unity Hub 3.22.2', 'Unity.UnityHub', '3.22.2.655', '3.22.3.655', 'winget'))) +
                 @('3 Aktualisierungen verfuegbar.', '2 Pakete verfuegen ueber Pins, die ein Upgrade verhindern.')
        $r = ConvertFrom-WingetUpgradeOutput -Lines $lines -SeparatorPattern $sep
        @($r.Packages | ForEach-Object Id) | Should -Be @('Element.Element', 'Microsoft.PowerShell', 'Unity.UnityHub')
        $r.Summary | Should -Be 3
    }

    It 'returns nothing when there are no updates' {
        $r = ConvertFrom-WingetUpgradeOutput -Lines @('No installed package found matching input criteria.') -SeparatorPattern $sep
        @($r.Packages).Count | Should -Be 0
        $r.Summary           | Should -Be 0
    }
}

Describe 'Get-WingetRows (winget search table)' {
    BeforeAll {
        . ([scriptblock]::Create((Get-ScySource 'Tabs\Tab-Installs.ps1' -Function 'Get-WingetRows')))
    }
    It 'splits rows at the header columns' {
        $lines = New-WingetTable @(20, 24, 10, 12) @('Name', 'Id', 'Version', 'Match', 'Source') @(
            , @('Notepad++', 'Notepad++.Notepad++', '8.9.8', '', 'winget')
            , @('Visual Studio Code', 'Microsoft.VisualStudioCode', '1.99.0', 'Tag: code', 'winget'))
        $rows = @(Get-WingetRows $lines)
        $rows.Count | Should -Be 2
        $rows[0][0].Trim() | Should -Be 'Notepad++'
        $rows[0][1].Trim() | Should -Be 'Notepad++.Notepad++'
        $rows[1][0].Trim() | Should -Be 'Visual Studio Code'
    }
}

Describe 'Hosts file' {
    BeforeAll {
        . ([scriptblock]::Create((Get-ScySource 'Tabs\Tab-Hosts.ps1' -Function 'Test-HostsIp', 'Read-HostsFile', 'ConvertTo-HostsFileLines')))
        $hostsPath = Join-Path $TestDrive 'hosts'
        $sample = @(
            '# Copyright (c) 1993-2009 Microsoft Corp.',
            '#',
            '#      102.54.94.97     rhino.acme.com          # source server',
            '',
            '0.0.0.0 ads.example.com tracker.example.com',
            '127.0.0.1   dev.local   # my dev box',
            'not-an-ip   something'
        )
    }
    BeforeEach { [System.IO.File]::WriteAllLines($hostsPath, [string[]]$sample) }

    It 'Test-HostsIp: <Value> -> <Expected>' -ForEach @(
        @{ Value = '127.0.0.1'; Expected = $true }, @{ Value = '::1'; Expected = $true }, @{ Value = 'fe80::1'; Expected = $true }
        @{ Value = '999.1.1.1'; Expected = $false }, @{ Value = '1'; Expected = $false }, @{ Value = 'localhost'; Expected = $false }
    ) {
        Test-HostsIp $Value | Should -Be $Expected
    }

    It 'reads entries, including disabled ones and lines with several hostnames' {
        # Read-HostsFile returns its List as one object (",$lines"); parenthesize to enumerate it
        $entries = @((Read-HostsFile) | Where-Object { $_.IsEntry })
        $entries.Count | Should -Be 3
        ($entries | Where-Object IP -eq '0.0.0.0').Host | Should -Be 'ads.example.com tracker.example.com'
        ($entries | Where-Object Host -eq 'rhino.acme.com').Enabled | Should -BeFalse
        ($entries | Where-Object Host -eq 'dev.local').Comment | Should -Be 'my dev box'
    }

    It 'writes an unchanged file back exactly as it was' {
        ConvertTo-HostsFileLines (Read-HostsFile) | Should -Be $sample
    }

    It 'only rewrites the entries that changed, and appends new ones' {
        $lines = Read-HostsFile
        ($lines | Where-Object { $_.IsEntry -and $_.Host -eq 'dev.local' }).Enabled = $false
        $lines.Add(@{ Raw = $null; IsEntry = $true; IP = '10.0.0.5'; Host = 'nas.lan'; Comment = ''; Enabled = $true; OrigEnabled = $true })
        $out = @(ConvertTo-HostsFileLines $lines)
        $out[0..4] | Should -Be $sample[0..4]
        $out[5] | Should -Match '^# 127\.0\.0\.1\s+dev\.local\s+# my dev box$'
        $out[6] | Should -Be 'not-an-ip   something'
        $out[7] | Should -Match '^10\.0\.0\.5\s+nas\.lan$'
    }
}

Describe 'Self-update version comparison' {
    BeforeAll {
        . ([scriptblock]::Create((Get-ScySource 'Tabs\Tab-Settings.ps1' -Function 'ConvertTo-ScyVersion', 'Test-ScyVersionNewer')))
    }
    It '<Remote> is newer than <Local>: <Expected>' -ForEach @(
        @{ Remote = '0.13.0';        Local = '0.12.0';        Expected = $true }
        @{ Remote = 'v0.12.1';       Local = '0.12.0';        Expected = $true }
        @{ Remote = '0.12.0';        Local = '0.12.0';        Expected = $false }
        @{ Remote = '0.11.9';        Local = '0.12.0';        Expected = $false }
        @{ Remote = '0.13.0-beta.1'; Local = '0.12.0';        Expected = $true }
        @{ Remote = '0.13.0';        Local = '0.13.0-beta.1'; Expected = $true }
        @{ Remote = '0.13.0-beta.2'; Local = '0.13.0';        Expected = $false }
        @{ Remote = 'garbage';       Local = '0.12.0';        Expected = $false }
    ) {
        Test-ScyVersionNewer $Remote $Local | Should -Be $Expected
    }
}

Describe 'Tweak state, backup and restore' {
    BeforeAll {
        . ([scriptblock]::Create((Get-ScySource 'Tabs\Tab-Tweaks.ps1' -Function 'Get-TweakRegValue', 'Get-TweakState', 'Get-TweakBackupPath', 'Save-TweakBackup', 'Restore-TweakBackup')))
        $script:tweakBackupDir = Join-Path $TestDrive 'tweak-backups'
        $base = 'HKCU:\Software\ScyPesterTest'

        function Get-RegSnapshot {
            @(Get-ChildItem $base -Recurse | ForEach-Object {
                $k = $_
                ($k.Name -replace '^.*ScyPesterTest', '') + '{' + (($k.GetValueNames() | Sort-Object | ForEach-Object { "$_=$($k.GetValue($_))" }) -join ',') + '}'
            }) -join ' '
        }
    }
    BeforeEach {
        Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $script:tweakBackupDir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item "$base\A" -Force | Out-Null
        New-ItemProperty "$base\A" -Name X -Value 5 -PropertyType DWord | Out-Null
        New-ItemProperty "$base\A" -Name Keep -Value 'stays' -PropertyType String | Out-Null
    }
    AfterAll { Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue }

    It 'reports Applied / Partial / NotApplied from the registry' {
        $checks = @([pscustomobject]@{ path = "$base\A"; name = 'X'; value = 1 }, [pscustomobject]@{ path = "$base\A"; name = 'Keep'; value = 'stays' })
        Get-TweakState $checks | Should -Be 'Partial'
        Set-ItemProperty "$base\A" -Name X -Value 1
        Get-TweakState $checks | Should -Be 'Applied'
        Get-TweakState @([pscustomobject]@{ path = "$base\Missing"; name = 'X'; value = 1 }) | Should -Be 'NotApplied'
        Get-TweakState @() | Should -BeNullOrEmpty
    }

    It 'restores changed values, added values and created keys exactly' {
        $before = Get-RegSnapshot
        $row = @{ FolderName = 'Test'; Snapshot = $true; Checks = @(
            [pscustomobject]@{ path = "$base\A"; name = 'X'; value = 1 }                      # existing value changed
            [pscustomobject]@{ path = "$base\A"; name = 'Y'; value = 1 }                      # value added
            [pscustomobject]@{ path = "$base\B\Inproc"; name = '(Default)'; value = '' }      # keys created + default value
        ) }
        Save-TweakBackup $row | Should -BeTrue
        Save-TweakBackup $row | Should -BeFalse   # an existing backup (the original values) is kept

        # "apply"
        Set-ItemProperty "$base\A" -Name X -Value 1 -Type DWord
        Set-ItemProperty "$base\A" -Name Y -Value 1 -Type DWord
        New-Item "$base\B\Inproc" -Force | Out-Null
        Set-ItemProperty "$base\B\Inproc" -Name '(Default)' -Value ''
        Get-TweakState $row.Checks | Should -Be 'Applied'

        # Loaded exactly as Invoke-TweakChanges does (this used to arrive as one nested entry)
        $json    = Get-Content (Get-TweakBackupPath 'Test') -Raw | ConvertFrom-Json
        $entries = @($json | ForEach-Object { $_ })
        $entries.Count | Should -Be 3
        Restore-TweakBackup -Entries $entries
        Get-RegSnapshot | Should -Be $before
    }

    It 'restores even when the entries arrive as one nested array' {
        $before = Get-RegSnapshot
        $row = @{ FolderName = 'Nested'; Snapshot = $true; Checks = @(
            [pscustomobject]@{ path = "$base\A"; name = 'X'; value = 1 }
            [pscustomobject]@{ path = "$base\A"; name = 'Y'; value = 1 }
        ) }
        Save-TweakBackup $row | Should -BeTrue
        Set-ItemProperty "$base\A" -Name X -Value 1 -Type DWord
        Set-ItemProperty "$base\A" -Name Y -Value 1 -Type DWord
        Restore-TweakBackup -Entries @(Get-Content (Get-TweakBackupPath 'Nested') -Raw | ConvertFrom-Json)
        Get-RegSnapshot | Should -Be $before
    }
}

Describe 'Passwords' {
    BeforeAll {
        . ([scriptblock]::Create((Get-ScySource 'Tabs\Tab-PasswordGen.ps1' -Function 'Get-PwdRandomIndex', 'New-RandomCharPassword', 'New-Passphrase', 'Get-PasswordStrength')))
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    }
    AfterAll { $rng.Dispose() }

    It 'random indexes stay in range' {
        foreach ($max in 1, 2, 7, 10, 88, 7776) {
            1..200 | ForEach-Object { Get-PwdRandomIndex $rng $max } | Where-Object { $_ -lt 0 -or $_ -ge $max } | Should -BeNullOrEmpty
        }
    }

    It 'every selected character type appears, even in the shortest password' {
        $sets = @('ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz', '0123456789', '!@#$%')
        1..100 | ForEach-Object {
            $pw = New-RandomCharPassword -Rng $rng -Length 4 -Charset (-join $sets) -RequiredSets $sets
            foreach ($s in $sets) { $pw.IndexOfAny($s.ToCharArray()) | Should -BeGreaterOrEqual 0 }
        }
    }

    It 'passphrases have the requested words, capitals and one digit' {
        $words = @('alpha', 'bravo', 'charlie', 'delta')
        $p = New-Passphrase -Rng $rng -Words 5 -WordList $words -Separator '.' -Capitalize $true -AddNumber $true
        $parts = $p -split '\.'
        $parts.Count | Should -Be 5
        $parts | ForEach-Object { $_ | Should -MatchExactly '^[A-Z][a-z]+\d?$' }
        ([regex]::Matches($p, '\d')).Count | Should -Be 1
    }

    It 'strength follows entropy: <Bits> bits -> <Label>' -ForEach @(
        @{ Bits = 30; Label = 'Weak' }, @{ Bits = 50; Label = 'Fair' }, @{ Bits = 70; Label = 'Strong' }, @{ Bits = 100; Label = 'Very strong' }
    ) {
        (Get-PasswordStrength $Bits).Label | Should -Be $Label
    }
}

Describe 'Input validation' {
    BeforeAll {
        . ([scriptblock]::Create((Get-ScySource 'Tabs\Tab-Network.ps1' -Function 'Test-DnsServerAddress')))
    }
    It 'DNS server <Value> valid: <Expected>' -ForEach @(
        @{ Value = '1.1.1.1'; Expected = $true }, @{ Value = '255.255.255.255'; Expected = $true }
        @{ Value = '2606:4700:4700::1111'; Expected = $true }, @{ Value = '999.1.1.1'; Expected = $false }
        @{ Value = '1.2.3'; Expected = $false }, @{ Value = 'dns.google'; Expected = $false }
    ) {
        Test-DnsServerAddress $Value | Should -Be $Expected
    }
}

Describe 'Ping and traceroute output' {
    BeforeAll {
        . ([scriptblock]::Create((Get-ScySource 'Tabs\Tab-Network.ps1' -Function 'ConvertTo-PingStatusText', 'Format-PingReply', 'Get-PingStats', 'Get-PingSummary', 'Format-TraceHop')))
    }
    It 'formats a reply with time and TTL' {
        Format-PingReply -Status 'Success' -Address '1.1.1.1' -Time 11 -Ttl 58 | Should -Be 'Reply from 1.1.1.1: 11 ms, TTL 58'
    }
    It 'leaves out a missing TTL (IPv6 replies have none)' {
        Format-PingReply -Status 'Success' -Address '::1' -Time 0 -Ttl 0 | Should -Be 'Reply from ::1: 0 ms'
    }
    It 'reports a timeout' {
        Format-PingReply -Status 'TimedOut' -Address '0.0.0.0' | Should -Be 'Request timed out'
    }
    It 'spells out other statuses, naming the router that answered' {
        Format-PingReply -Status 'DestinationHostUnreachable' -Address '192.168.1.1' | Should -Be 'Reply from 192.168.1.1: destination host unreachable'
        Format-PingReply -Status 'DestinationNetworkUnreachable' -Address '0.0.0.0' | Should -Be 'Destination network unreachable'
    }
    It 'summarizes loss and times' {
        $s = Get-PingSummary -Sent 4 -Times @(7, 10, 13)
        $s[0] | Should -Be 'Sent 4, received 3, lost 1 (25% loss)'
        $s[1] | Should -Be 'Min 7 ms, avg 10 ms, max 13 ms'
    }
    It 'computes the numbers behind the stats line' {
        $s = Get-PingStats -Sent 4 -Times @(7, 10, 14)
        $s.Received | Should -Be 3
        $s.Lost     | Should -Be 1
        $s.Loss     | Should -Be 25
        $s.Min      | Should -Be 7
        $s.Avg      | Should -Be 10
        $s.Max      | Should -Be 14
        (Get-PingStats -Sent 0).Loss | Should -Be 0
        (Get-PingStats -Sent 2).Min  | Should -BeNullOrEmpty
    }
    It 'summarizes a run without replies in one line' {
        $s = Get-PingSummary -Sent 4 -Times @()
        @($s).Count | Should -Be 1
        $s[0] | Should -Be 'Sent 4, received 0, lost 4 (100% loss)'
    }
    It 'formats a hop with answered and missing probes' {
        Format-TraceHop -Hop 3 -Times @(12, $null, 10) -Address '79.127.195.209' |
            Should -Be '  3   12 ms       *   10 ms    79.127.195.209'
    }
    It 'formats a hop that never answered' {
        Format-TraceHop -Hop 12 -Times @($null, $null, $null) -Address $null |
            Should -Be ' 12       *       *       *    Request timed out'
    }
}

Describe 'Speed test' {
    BeforeAll {
        . ([scriptblock]::Create((Get-ScySource 'Tabs\Tab-Network.ps1' -Function 'ConvertTo-PingStatusText', 'ConvertTo-SpeedErrorText', 'Format-SpeedMbps')))
    }
    It 'explains <Code> as "<Expected>"' -ForEach @(
        @{ Code = 'HTTP 404';              Expected = "the test file wasn't found (HTTP 404)" }
        @{ Code = 'HTTP 503';              Expected = 'the server answered with HTTP 503' }
        @{ Code = 'Timeout';               Expected = 'the connection timed out' }
        @{ Code = 'NameResolutionFailure'; Expected = "the server name couldn't be found" }
        @{ Code = 'ProtocolError';         Expected = 'protocol error' }
        @{ Code = '';                      Expected = 'unknown error' }
    ) {
        ConvertTo-SpeedErrorText $Code | Should -Be $Expected
    }
    It 'formats <Mbps> Mbps as <Expected> (always with a dot)' -ForEach @(
        @{ Mbps = 8.44;   Expected = '8.4' }
        @{ Mbps = 0;      Expected = '0.0' }
        @{ Mbps = 94.6;   Expected = '95' }
        @{ Mbps = 940.2;  Expected = '940' }
    ) {
        Format-SpeedMbps $Mbps | Should -Be $Expected
    }
}

Describe 'NSLookup records' {
    BeforeAll {
        . ([scriptblock]::Create((Get-ScySource 'Tabs\Tab-Network.ps1' -Function 'ConvertTo-NSRecordRow')))
    }
    It 'shows an A record as its address' {
        $r = ConvertTo-NSRecordRow ([pscustomobject]@{ IPAddress = '168.119.60.252'; TTL = 600 }) 'A'
        $r.Value  | Should -Be '168.119.60.252'
        $r.Detail | Should -Be ''
        $r.Ttl    | Should -Be 600
    }
    It 'shows an MX record with its priority' {
        $r = ConvertTo-NSRecordRow ([pscustomobject]@{ NameExchange = 'mx1.example.com'; Preference = 10; TTL = 300 }) 'MX'
        $r.Value  | Should -Be 'mx1.example.com'
        $r.Detail | Should -Be 'Priority 10'
    }
    It 'joins the strings of a long TXT record' {
        $r = ConvertTo-NSRecordRow ([pscustomobject]@{ Strings = @('v=spf1 include:a.example ', '-all'); TTL = 60 }) 'TXT'
        $r.Value | Should -Be 'v=spf1 include:a.example -all'
    }
    It 'shows an SRV record as target:port with priority and weight' {
        $r = ConvertTo-NSRecordRow ([pscustomobject]@{ NameTarget = 'sip.example.com'; Port = 5061; Priority = 1; Weight = 5; TTL = 60 }) 'SRV'
        $r.Value  | Should -Be 'sip.example.com:5061'
        $r.Detail | Should -Be 'Priority 1, weight 5'
    }
}

Describe 'QR helpers' {
    BeforeAll {
        Add-Type -AssemblyName PresentationCore
        . ([scriptblock]::Create((Get-ScySource 'Tabs\Tab-QRCode.ps1' -Function 'script:Format-VcardValue', 'script:Get-QRContrast')))
        $color = { param($hex) [System.Windows.Media.ColorConverter]::ConvertFromString($hex) }
    }
    It 'escapes vCard values' {
        script:Format-VcardValue 'Acme, Inc.; Dept\X' | Should -Be 'Acme\, Inc.\; Dept\\X'
    }
    It 'measures contrast (black on white is 21:1, identical colors 1:1)' {
        [Math]::Round((script:Get-QRContrast (& $color '#000000') (& $color '#FFFFFF')), 1) | Should -Be 21
        [Math]::Round((script:Get-QRContrast (& $color '#777777') (& $color '#777777')), 1) | Should -Be 1
    }
}

Describe 'Note names' {
    BeforeAll {
        . ([scriptblock]::Create((Get-ScySource 'Tabs\Tab-Notes.ps1' -Function 'Get-NoteNames', 'Resolve-NoteName')))
        $script:notesDir = Join-Path $TestDrive 'notes'
        New-Item -ItemType Directory $script:notesDir -Force | Out-Null
        Set-Content (Join-Path $script:notesDir 'Notes.md') ''
    }
    It 'cleans "<Raw>" to "<Expected>"' -ForEach @(
        @{ Raw = 'Shopping list'; Expected = 'Shopping list' }
        @{ Raw = 'Notes';         Expected = 'Notes (2)' }
        @{ Raw = 'a/b:c*?';       Expected = 'abc' }
        @{ Raw = '   ...  ';      Expected = $null }
    ) {
        Resolve-NoteName $Raw | Should -Be $Expected
    }
    It 'lets a note keep its own name when renaming' {
        Resolve-NoteName 'Notes' -Except 'Notes' | Should -Be 'Notes'
    }
}
