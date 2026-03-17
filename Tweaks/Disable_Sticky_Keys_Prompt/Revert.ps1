$path = "HKCU:\Control Panel\Accessibility\StickyKeys"
Set-ItemProperty -Path $path -Name "Flags" -Value "510" -Type String

$path2 = "HKCU:\Control Panel\Accessibility\ToggleKeys"
Set-ItemProperty -Path $path2 -Name "Flags" -Value "62" -Type String

$path3 = "HKCU:\Control Panel\Accessibility\Keyboard Response"
Set-ItemProperty -Path $path3 -Name "Flags" -Value "126" -Type String
