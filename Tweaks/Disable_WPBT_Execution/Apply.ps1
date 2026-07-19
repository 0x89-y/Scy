$path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
Set-ItemProperty -Path $path -Name "DisableWpbtExecution" -Value 1 -Type DWord
