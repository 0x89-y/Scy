$path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
Set-ItemProperty -Path $path -Name "RotatingLockScreenOverlayEnabled" -Value 1 -Type DWord
Set-ItemProperty -Path $path -Name "SubscribedContent-338387Enabled" -Value 1 -Type DWord
Set-ItemProperty -Path $path -Name "SubscribedContent-338388Enabled" -Value 1 -Type DWord
Set-ItemProperty -Path $path -Name "SubscribedContent-338389Enabled" -Value 1 -Type DWord
