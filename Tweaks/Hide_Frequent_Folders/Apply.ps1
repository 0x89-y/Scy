Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent" -Value 0 -Type DWord
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
