$key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty -Path $key -Name "ShowTaskViewButton" -Value 1 -Force
Stop-Process -Name explorer -Force
