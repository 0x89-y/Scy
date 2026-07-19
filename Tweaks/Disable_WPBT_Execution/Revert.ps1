$path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
if (Test-Path $path) { Remove-ItemProperty -Path $path -Name "DisableWpbtExecution" -ErrorAction SilentlyContinue }
