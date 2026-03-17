Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 1 -Type DWord
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
