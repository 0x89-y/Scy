# ── BIOS / UEFI Info Panel ────────────────────────────────────────
$firmwareInfoPanel        = Find "FirmwareInfoPanel"
$firmwareSecurityPanel    = Find "FirmwareSecurityPanel"
$firmwareFeaturesPanel    = Find "FirmwareFeaturesPanel"
$firmwareMotherboardPanel = Find "FirmwareMotherboardPanel"

function Populate-FirmwareInfo {
    Set-BusyStatus "Gathering firmware info..."

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()

    $rs.SessionStateProxy.SetVariable("_win",       $window)
    $rs.SessionStateProxy.SetVariable("_fwPanel",   $firmwareInfoPanel)
    $rs.SessionStateProxy.SetVariable("_secPanel",  $firmwareSecurityPanel)
    $rs.SessionStateProxy.SetVariable("_featPanel", $firmwareFeaturesPanel)
    $rs.SessionStateProxy.SetVariable("_mbPanel",   $firmwareMotherboardPanel)
    $rs.SessionStateProxy.SetVariable("_si",        (Find "StatusIndicator"))
    $rs.SessionStateProxy.SetVariable("_fs",        (Find "FooterStatus"))

    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    $ps.AddScript({
        # ── Inline row builder (same pattern as other tabs) ──
        function _MakeRow {
            param([string]$Label, [string]$Value, [string]$BrushKey = "FgBrush", [bool]$Alt = $false)
            $border = New-Object System.Windows.Controls.Border
            $border.Background  = if ($Alt) { $_win.Resources["SurfaceBrush"] } else { $_win.Resources["InputBgBrush"] }
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

        # ── Gather BIOS data ─────────────────────────────────────
        $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
        $biosName    = if ($bios.Name) { $bios.Name.Trim() } else { "Unknown" }
        $biosVer     = if ($bios.SMBIOSBIOSVersion) { $bios.SMBIOSBIOSVersion } else { "Unknown" }
        $biosDate    = if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString("yyyy-MM-dd") } else { "Unknown" }
        $biosMfr     = if ($bios.Manufacturer) { $bios.Manufacturer.Trim() } else { "Unknown" }
        $smbiosVer   = if ($bios.SMBIOSMajorVersion) { "$($bios.SMBIOSMajorVersion).$($bios.SMBIOSMinorVersion)" } else { "Unknown" }
        $serialNum   = if ($bios.SerialNumber) { $bios.SerialNumber.Trim() } else { "N/A" }

        # UEFI or Legacy BIOS
        try {
            $fwType = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -ErrorAction Stop)
            $isUEFI = $true
        } catch {
            # Check via bcdedit or environment
            try {
                $env = [System.Environment]::GetEnvironmentVariable("firmware_type", "Machine")
                $isUEFI = ($env -eq "UEFI")
            } catch {
                # Fallback: check if EFI system partition exists
                $isUEFI = $null -ne (Get-Partition -ErrorAction SilentlyContinue | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' })
            }
        }
        $fwTypeStr = if ($isUEFI) { "UEFI" } else { "Legacy BIOS" }

        # ── Secure Boot ──────────────────────────────────────────
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

        # ── TPM ──────────────────────────────────────────────────
        $tpmVersion   = "Not Detected"
        $tpmReady     = "Unknown"
        $tpmMfr       = "Unknown"
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

        # ── Virtualization ───────────────────────────────────────
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        $virtFirmware = if ($cpu.VirtualizationFirmwareEnabled) { "Enabled" } else { "Disabled" }

        # Hyper-V status
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

        # Device Guard / VBS
        $vbs = "Not Running"
        try {
            $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace "root\Microsoft\Windows\DeviceGuard" -ErrorAction Stop
            if ($dg.VirtualizationBasedSecurityStatus -eq 2) { $vbs = "Running" }
            elseif ($dg.VirtualizationBasedSecurityStatus -eq 1) { $vbs = "Enabled (Not Running)" }
        } catch { }

        # WSL check
        $wslStatus = "Not Installed"
        try {
            $wslFeature = Get-CimInstance Win32_OptionalFeature -ErrorAction SilentlyContinue |
                          Where-Object { $_.Name -eq "Microsoft-Windows-Subsystem-Linux" }
            if ($wslFeature -and $wslFeature.InstallState -eq 1) { $wslStatus = "Enabled" }
        } catch { }

        # ── Motherboard ──────────────────────────────────────────
        $board = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
        $mbMfr     = if ($board.Manufacturer) { $board.Manufacturer.Trim() } else { "Unknown" }
        $mbProduct = if ($board.Product) { $board.Product.Trim() } else { "Unknown" }
        $mbSerial  = if ($board.SerialNumber -and $board.SerialNumber.Trim() -ne "") { $board.SerialNumber.Trim() } else { "N/A" }
        $mbVersion = if ($board.Version -and $board.Version.Trim() -ne "") { $board.Version.Trim() } else { "N/A" }

        $sys = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $sysModel = if ($sys.Model) { $sys.Model.Trim() } else { "Unknown" }
        $sysMfr   = if ($sys.Manufacturer) { $sys.Manufacturer.Trim() } else { "Unknown" }

        # ── Marshal to UI ────────────────────────────────────────
        $_win.Dispatcher.Invoke([action]{

            # ── Firmware card ──
            $_fwPanel.Children.Clear()
            $alt = $false
            $_fwPanel.Children.Add((_MakeRow "Firmware Type"     $fwTypeStr "AccentBrush" $alt)) | Out-Null; $alt = -not $alt
            $_fwPanel.Children.Add((_MakeRow "BIOS Version"      $biosVer "FgBrush" $alt)) | Out-Null; $alt = -not $alt
            $_fwPanel.Children.Add((_MakeRow "BIOS Name"         $biosName "FgBrush" $alt)) | Out-Null; $alt = -not $alt
            $_fwPanel.Children.Add((_MakeRow "Manufacturer"      $biosMfr "FgBrush" $alt)) | Out-Null; $alt = -not $alt
            $_fwPanel.Children.Add((_MakeRow "Release Date"      $biosDate "FgBrush" $alt)) | Out-Null; $alt = -not $alt
            $_fwPanel.Children.Add((_MakeRow "SMBIOS Version"    $smbiosVer "FgBrush" $alt)) | Out-Null; $alt = -not $alt
            $_fwPanel.Children.Add((_MakeRow "Serial Number"     $serialNum "MutedText" $alt)) | Out-Null

            # ── Security card ──
            $_secPanel.Children.Clear()
            $alt = $false

            $sbBrush = if ($secureBoot -eq "Enabled") { "SuccessBrush" } else { "WarningBrush" }
            $_secPanel.Children.Add((_MakeRow "Secure Boot"      $secureBoot $sbBrush $alt)) | Out-Null; $alt = -not $alt

            $tpmBrush = if ($tpmVersion -ne "Not Detected") { "SuccessBrush" } else { "DangerBrush" }
            $_secPanel.Children.Add((_MakeRow "TPM"              $tpmVersion $tpmBrush $alt)) | Out-Null; $alt = -not $alt

            $tpmReadyBrush = if ($tpmReady -eq "Ready") { "SuccessBrush" } else { "WarningBrush" }
            $_secPanel.Children.Add((_MakeRow "TPM Status"       $tpmReady $tpmReadyBrush $alt)) | Out-Null; $alt = -not $alt
            $_secPanel.Children.Add((_MakeRow "TPM Manufacturer" $tpmMfr "FgBrush" $alt)) | Out-Null; $alt = -not $alt

            $vbsBrush = if ($vbs -eq "Running") { "SuccessBrush" } else { "MutedText" }
            $_secPanel.Children.Add((_MakeRow "VBS (Device Guard)" $vbs $vbsBrush $alt)) | Out-Null

            # ── Features card ──
            $_featPanel.Children.Clear()
            $alt = $false

            $virtBrush = if ($virtFirmware -eq "Enabled") { "SuccessBrush" } else { "WarningBrush" }
            $_featPanel.Children.Add((_MakeRow "CPU Virtualization"  $virtFirmware $virtBrush $alt)) | Out-Null; $alt = -not $alt

            $hvBrush = if ($hyperV -eq "Enabled") { "SuccessBrush" } elseif ($hyperV -eq "Disabled") { "WarningBrush" } else { "MutedText" }
            $_featPanel.Children.Add((_MakeRow "Hyper-V"             $hyperV $hvBrush $alt)) | Out-Null; $alt = -not $alt

            $wslBrush = if ($wslStatus -eq "Enabled") { "SuccessBrush" } else { "MutedText" }
            $_featPanel.Children.Add((_MakeRow "WSL"                 $wslStatus $wslBrush $alt)) | Out-Null

            # ── Motherboard card ──
            $_mbPanel.Children.Clear()
            $alt = $false
            $_mbPanel.Children.Add((_MakeRow "System Manufacturer" $sysMfr "FgBrush" $alt)) | Out-Null; $alt = -not $alt
            $_mbPanel.Children.Add((_MakeRow "System Model"        $sysModel "FgBrush" $alt)) | Out-Null; $alt = -not $alt
            $_mbPanel.Children.Add((_MakeRow "Board Manufacturer"  $mbMfr "FgBrush" $alt)) | Out-Null; $alt = -not $alt
            $_mbPanel.Children.Add((_MakeRow "Board Name"          $mbProduct "FgBrush" $alt)) | Out-Null; $alt = -not $alt
            $_mbPanel.Children.Add((_MakeRow "Board Version"       $mbVersion "FgBrush" $alt)) | Out-Null; $alt = -not $alt
            $_mbPanel.Children.Add((_MakeRow "Board Serial"        $mbSerial "MutedText" $alt)) | Out-Null

            # Done
            $_si.Text = "Ready"; $_si.Foreground = $_win.Resources["SuccessBrush"]; $_fs.Text = "Ready"
        }, [System.Windows.Threading.DispatcherPriority]::Normal)
    }) | Out-Null

    $ps.BeginInvoke() | Out-Null
}

(Find "BtnFirmwareRefresh").Add_Click({ Populate-FirmwareInfo })
