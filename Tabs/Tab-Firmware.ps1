# ── BIOS / UEFI Info Panel ────────────────────────────────────────
$firmwareInfoPanel        = Find "FirmwareInfoPanel"
$firmwareSecurityPanel    = Find "FirmwareSecurityPanel"
$firmwareFeaturesPanel    = Find "FirmwareFeaturesPanel"
$firmwareMotherboardPanel = Find "FirmwareMotherboardPanel"

function Populate-FirmwareInfo {
    Set-BusyStatus "Gathering firmware info..."

    Start-ScyJob `
        -Work {
            param($emit)

            $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
            $biosName  = if ($bios.Name) { $bios.Name.Trim() } else { "Unknown" }
            $biosVer   = if ($bios.SMBIOSBIOSVersion) { $bios.SMBIOSBIOSVersion } else { "Unknown" }
            $biosDate  = if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString("yyyy-MM-dd") } else { "Unknown" }
            $biosMfr   = if ($bios.Manufacturer) { $bios.Manufacturer.Trim() } else { "Unknown" }
            $smbiosVer = if ($bios.SMBIOSMajorVersion) { "$($bios.SMBIOSMajorVersion).$($bios.SMBIOSMinorVersion)" } else { "Unknown" }
            $serialNum = if ($bios.SerialNumber) { $bios.SerialNumber.Trim() } else { "N/A" }

            try {
                Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -ErrorAction Stop | Out-Null
                $isUEFI = $true
            } catch {
                try {
                    $envFw  = [System.Environment]::GetEnvironmentVariable("firmware_type", "Machine")
                    $isUEFI = ($envFw -eq "UEFI")
                } catch {
                    $isUEFI = $null -ne (Get-Partition -ErrorAction SilentlyContinue | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' })
                }
            }
            $fwTypeStr = if ($isUEFI) { "UEFI" } else { "Legacy BIOS" }

            $secureBoot = "Unknown"
            try {
                $sbState = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -ErrorAction Stop).UEFISecureBootEnabled
                $secureBoot = if ($sbState -eq 1) { "Enabled" } else { "Disabled" }
            } catch {
                try {
                    $sb = Confirm-SecureBootUEFI -ErrorAction Stop
                    $secureBoot = if ($sb) { "Enabled" } else { "Disabled" }
                } catch {
                    $secureBoot = "Not Supported / Unknown"
                }
            }

            $tpmVersion = "Not Detected"
            $tpmReady   = "Unknown"
            $tpmMfr     = "Unknown"
            try {
                $tpm = Get-CimInstance -Namespace "root\cimv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ErrorAction Stop
                if ($tpm) {
                    $specVer = $tpm.SpecVersion
                    if ($specVer) {
                        $tpmVersion = ($specVer -split ',')[0].Trim()
                        $tpmVersion = "TPM $tpmVersion"
                    }
                    $tpmReady = if ($tpm.IsActivated_InitialValue) { "Ready" } else { "Not Ready" }
                    $tpmMfr   = if ($tpm.ManufacturerIdTxt) { $tpm.ManufacturerIdTxt } else { "Unknown" }
                }
            } catch { }

            $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
            $virtFirmware = if ($cpu.VirtualizationFirmwareEnabled) { "Enabled" } else { "Disabled" }

            $hyperV = "Not Installed"
            try {
                $hvFeature = Get-CimInstance Win32_OptionalFeature -ErrorAction SilentlyContinue |
                             Where-Object { $_.Name -eq "Microsoft-Hyper-V" }
                if ($hvFeature) {
                    $hyperV = switch ($hvFeature.InstallState) {
                        1 { "Enabled" }; 2 { "Disabled" }; default { "Unknown" }
                    }
                }
            } catch { }

            $vbs = "Not Running"
            try {
                $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace "root\Microsoft\Windows\DeviceGuard" -ErrorAction Stop
                if ($dg.VirtualizationBasedSecurityStatus -eq 2) { $vbs = "Running" }
                elseif ($dg.VirtualizationBasedSecurityStatus -eq 1) { $vbs = "Enabled (Not Running)" }
            } catch { }

            $wslStatus = "Not Installed"
            try {
                $wslFeature = Get-CimInstance Win32_OptionalFeature -ErrorAction SilentlyContinue |
                              Where-Object { $_.Name -eq "Microsoft-Windows-Subsystem-Linux" }
                if ($wslFeature -and $wslFeature.InstallState -eq 1) { $wslStatus = "Enabled" }
            } catch { }

            $board = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
            $mbMfr     = if ($board.Manufacturer) { $board.Manufacturer.Trim() } else { "Unknown" }
            $mbProduct = if ($board.Product) { $board.Product.Trim() } else { "Unknown" }
            $mbSerial  = if ($board.SerialNumber -and $board.SerialNumber.Trim() -ne "") { $board.SerialNumber.Trim() } else { "N/A" }
            $mbVersion = if ($board.Version -and $board.Version.Trim() -ne "") { $board.Version.Trim() } else { "N/A" }

            $sys = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
            $sysModel = if ($sys.Model) { $sys.Model.Trim() } else { "Unknown" }
            $sysMfr   = if ($sys.Manufacturer) { $sys.Manufacturer.Trim() } else { "Unknown" }

            return @{
                BiosName     = $biosName;    BiosVer      = $biosVer
                BiosDate     = $biosDate;    BiosMfr      = $biosMfr
                SmbiosVer    = $smbiosVer;   SerialNum    = $serialNum
                FwTypeStr    = $fwTypeStr
                SecureBoot   = $secureBoot
                TpmVersion   = $tpmVersion;  TpmReady     = $tpmReady;  TpmMfr = $tpmMfr
                VirtFirmware = $virtFirmware
                HyperV       = $hyperV
                Vbs          = $vbs
                WslStatus    = $wslStatus
                MbMfr        = $mbMfr;       MbProduct    = $mbProduct
                MbSerial     = $mbSerial;    MbVersion    = $mbVersion
                SysModel     = $sysModel;    SysMfr       = $sysMfr
            }
        } `
        -OnComplete {
            param($d, $err, $ctx)
            if ($err) {
                Set-ReadyStatus
                return
            }

            function _MakeRow {
                param([string]$Label, [string]$Value, [string]$BrushKey = "FgBrush", [bool]$Alt = $false)
                $border = New-Object System.Windows.Controls.Border
                $border.Background   = if ($Alt) { $window.Resources["SurfaceBrush"] } else { $window.Resources["InputBgBrush"] }
                $border.CornerRadius = [System.Windows.CornerRadius]::new(4)
                $border.Padding      = [System.Windows.Thickness]::new(10, 6, 10, 6)
                $border.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 3)

                $grid = New-Object System.Windows.Controls.Grid
                $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::Auto
                $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
                $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1)

                $lbl = New-Object System.Windows.Controls.TextBlock
                $lbl.Text = $Label; $lbl.FontSize = 12; $lbl.MinWidth = 160
                $lbl.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MutedText")
                [System.Windows.Controls.Grid]::SetColumn($lbl, 0)

                $val = New-Object System.Windows.Controls.TextBlock
                $val.Text = $Value; $val.FontSize = 12
                $val.HorizontalAlignment = "Right"; $val.TextAlignment = "Right"; $val.TextWrapping = "Wrap"
                $val.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $BrushKey)
                [System.Windows.Controls.Grid]::SetColumn($val, 1)

                $grid.Children.Add($lbl) | Out-Null; $grid.Children.Add($val) | Out-Null
                $border.Child = $grid
                return $border
            }

            $firmwareInfoPanel.Children.Clear()
            $alt = $false
            $firmwareInfoPanel.Children.Add((_MakeRow "Firmware Type"  $d.FwTypeStr "AccentBrush" $alt)) | Out-Null; $alt = -not $alt
            $firmwareInfoPanel.Children.Add((_MakeRow "BIOS Version"   $d.BiosVer   "FgBrush"     $alt)) | Out-Null; $alt = -not $alt
            $firmwareInfoPanel.Children.Add((_MakeRow "BIOS Name"      $d.BiosName  "FgBrush"     $alt)) | Out-Null; $alt = -not $alt
            $firmwareInfoPanel.Children.Add((_MakeRow "Manufacturer"   $d.BiosMfr   "FgBrush"     $alt)) | Out-Null; $alt = -not $alt
            $firmwareInfoPanel.Children.Add((_MakeRow "Release Date"   $d.BiosDate  "FgBrush"     $alt)) | Out-Null; $alt = -not $alt
            $firmwareInfoPanel.Children.Add((_MakeRow "SMBIOS Version" $d.SmbiosVer "FgBrush"     $alt)) | Out-Null; $alt = -not $alt
            $firmwareInfoPanel.Children.Add((_MakeRow "Serial Number"  $d.SerialNum "MutedText"   $alt)) | Out-Null

            $firmwareSecurityPanel.Children.Clear()
            $alt = $false
            $sbBrush = if ($d.SecureBoot -eq "Enabled") { "SuccessBrush" } else { "WarningBrush" }
            $firmwareSecurityPanel.Children.Add((_MakeRow "Secure Boot" $d.SecureBoot $sbBrush $alt)) | Out-Null; $alt = -not $alt

            $tpmBrush = if ($d.TpmVersion -ne "Not Detected") { "SuccessBrush" } else { "DangerBrush" }
            $firmwareSecurityPanel.Children.Add((_MakeRow "TPM" $d.TpmVersion $tpmBrush $alt)) | Out-Null; $alt = -not $alt

            $tpmReadyBrush = if ($d.TpmReady -eq "Ready") { "SuccessBrush" } else { "WarningBrush" }
            $firmwareSecurityPanel.Children.Add((_MakeRow "TPM Status" $d.TpmReady $tpmReadyBrush $alt)) | Out-Null; $alt = -not $alt
            $firmwareSecurityPanel.Children.Add((_MakeRow "TPM Manufacturer" $d.TpmMfr "FgBrush" $alt)) | Out-Null; $alt = -not $alt

            $vbsBrush = if ($d.Vbs -eq "Running") { "SuccessBrush" } else { "MutedText" }
            $firmwareSecurityPanel.Children.Add((_MakeRow "VBS (Device Guard)" $d.Vbs $vbsBrush $alt)) | Out-Null

            $firmwareFeaturesPanel.Children.Clear()
            $alt = $false
            $virtBrush = if ($d.VirtFirmware -eq "Enabled") { "SuccessBrush" } else { "WarningBrush" }
            $firmwareFeaturesPanel.Children.Add((_MakeRow "CPU Virtualization" $d.VirtFirmware $virtBrush $alt)) | Out-Null; $alt = -not $alt

            $hvBrush = if ($d.HyperV -eq "Enabled") { "SuccessBrush" } elseif ($d.HyperV -eq "Disabled") { "WarningBrush" } else { "MutedText" }
            $firmwareFeaturesPanel.Children.Add((_MakeRow "Hyper-V" $d.HyperV $hvBrush $alt)) | Out-Null; $alt = -not $alt

            $wslBrush = if ($d.WslStatus -eq "Enabled") { "SuccessBrush" } else { "MutedText" }
            $firmwareFeaturesPanel.Children.Add((_MakeRow "WSL" $d.WslStatus $wslBrush $alt)) | Out-Null

            $firmwareMotherboardPanel.Children.Clear()
            $alt = $false
            $firmwareMotherboardPanel.Children.Add((_MakeRow "System Manufacturer" $d.SysMfr    "FgBrush"   $alt)) | Out-Null; $alt = -not $alt
            $firmwareMotherboardPanel.Children.Add((_MakeRow "System Model"        $d.SysModel  "FgBrush"   $alt)) | Out-Null; $alt = -not $alt
            $firmwareMotherboardPanel.Children.Add((_MakeRow "Board Manufacturer"  $d.MbMfr     "FgBrush"   $alt)) | Out-Null; $alt = -not $alt
            $firmwareMotherboardPanel.Children.Add((_MakeRow "Board Name"          $d.MbProduct "FgBrush"   $alt)) | Out-Null; $alt = -not $alt
            $firmwareMotherboardPanel.Children.Add((_MakeRow "Board Version"       $d.MbVersion "FgBrush"   $alt)) | Out-Null; $alt = -not $alt
            $firmwareMotherboardPanel.Children.Add((_MakeRow "Board Serial"        $d.MbSerial  "MutedText" $alt)) | Out-Null

            Set-ReadyStatus
        } | Out-Null
}

(Find "BtnFirmwareRefresh").Add_Click({ Populate-FirmwareInfo })
