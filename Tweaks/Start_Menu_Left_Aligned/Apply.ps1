$key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty -Path $key -Name "TaskbarAl" -Value 0 -Force
Stop-Process -Name explorer -Force
