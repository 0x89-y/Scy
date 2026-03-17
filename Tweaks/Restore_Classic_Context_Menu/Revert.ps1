$key = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
Stop-Process -Name explorer -Force
