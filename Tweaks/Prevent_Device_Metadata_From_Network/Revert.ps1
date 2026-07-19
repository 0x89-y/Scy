$path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata"
if (Test-Path $path) { Remove-ItemProperty -Path $path -Name "PreventDeviceMetadataFromNetwork" -ErrorAction SilentlyContinue }
