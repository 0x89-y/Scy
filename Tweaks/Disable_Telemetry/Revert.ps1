$path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
if (Test-Path $path) { Remove-ItemProperty -Path $path -Name "AllowTelemetry" -ErrorAction SilentlyContinue }

$path2 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
if (Test-Path $path2) { Set-ItemProperty -Path $path2 -Name "AllowTelemetry" -Value 1 -Type DWord }
