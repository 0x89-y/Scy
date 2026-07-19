$path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata"
if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
Set-ItemProperty -Path $path -Name "PreventDeviceMetadataFromNetwork" -Value 1 -Type DWord
