$path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
Set-ItemProperty -Path $path -Name "EnableActivityFeed" -Value 0 -Type DWord
Set-ItemProperty -Path $path -Name "PublishUserActivities" -Value 0 -Type DWord
Set-ItemProperty -Path $path -Name "UploadUserActivities" -Value 0 -Type DWord
