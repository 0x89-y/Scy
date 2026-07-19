# Registry policy: hide AI components page + disable Notepad AI features
$explorer = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
if (-not (Test-Path $explorer)) { New-Item -Path $explorer -Force | Out-Null }
Set-ItemProperty -Path $explorer -Name "SettingsPageVisibility" -Value "hide:aicomponents" -Type String

$notepad = "HKLM:\SOFTWARE\Policies\WindowsNotepad"
if (-not (Test-Path $notepad)) { New-Item -Path $notepad -Force | Out-Null }
Set-ItemProperty -Path $notepad -Name "DisableAIFeatures" -Value 1 -Type DWord

# Remove Copilot / CoreAI packages and disable AI services/features
$Appx = (Get-AppxPackage MicrosoftWindows.Client.CoreAI).PackageFullName
$Sid = (Get-LocalUser $Env:UserName).Sid.Value

New-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife\$Sid\$Appx" -Force

Get-AppxPackage -AllUsers "*Copilot*" | Remove-AppxPackage -AllUsers
winget uninstall -e --name "Copilot" --silent --force --accept-source-agreements 2>$null
Get-AppxPackage -AllUsers Microsoft.MicrosoftOfficeHub | Remove-AppxPackage -AllUsers

if ($Appx) {
    Remove-AppxPackage $Appx
}

Set-Service -Name WSAIFabricSvc -StartupType Disabled
Disable-WindowsOptionalFeature -FeatureName Recall -Online -NoRestart

Write-Host "Windows AI Disabled"
