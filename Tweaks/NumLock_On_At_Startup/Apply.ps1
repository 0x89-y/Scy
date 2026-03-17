$path = "Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard"
Set-ItemProperty -Path $path -Name "InitialKeyboardIndicators" -Value "2" -Type String
