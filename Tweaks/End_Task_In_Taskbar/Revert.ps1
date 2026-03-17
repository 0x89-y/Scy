$path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings"
if (Test-Path $path) {
    Set-ItemProperty -Path $path -Name "TaskbarEndTask" -Value 0 -Type DWord
}
