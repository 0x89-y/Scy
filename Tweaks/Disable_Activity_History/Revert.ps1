$path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
if (Test-Path $path) {
    Remove-ItemProperty -Path $path -Name "EnableActivityFeed" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $path -Name "PublishUserActivities" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $path -Name "UploadUserActivities" -ErrorAction SilentlyContinue
}
