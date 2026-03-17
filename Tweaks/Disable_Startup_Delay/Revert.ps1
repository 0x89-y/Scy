$path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"
if (Test-Path $path) {
    Remove-ItemProperty -Path $path -Name "StartupDelayInMSec" -ErrorAction SilentlyContinue
}
