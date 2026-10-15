# Registry policy: hide AI components page + disable Notepad AI features
$explorer = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
if (-not (Test-Path $explorer)) { New-Item -Path $explorer -Force | Out-Null }
Set-ItemProperty -Path $explorer -Name "SettingsPageVisibility" -Value "hide:aicomponents" -Type String

$notepad = "HKLM:\SOFTWARE\Policies\WindowsNotepad"
if (-not (Test-Path $notepad)) { New-Item -Path $notepad -Force | Out-Null }
Set-ItemProperty -Path $notepad -Name "DisableAIFeatures" -Value 1 -Type DWord

# Remove Copilot / CoreAI packages and disable AI services/features
$Appx = (Get-AppxPackage MicrosoftWindows.Client.CoreAI).PackageFullName
# Current user's SID straight from the token: Get-LocalUser fails for domain /
# Microsoft accounts.
$Sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value

if ($Appx) {
    # Marks the package end-of-life so Windows doesn't reinstall it
    New-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife\$Sid\$Appx" -Force | Out-Null
}

Get-AppxPackage -AllUsers "*Copilot*" | Remove-AppxPackage -AllUsers
winget uninstall -e --name "Copilot" --silent --force --accept-source-agreements 2>$null
Get-AppxPackage -AllUsers Microsoft.MicrosoftOfficeHub | Remove-AppxPackage -AllUsers

if ($Appx) {
    Remove-AppxPackage $Appx
}

# Not every Windows build has these; skip what isn't there instead of failing
if (Get-Service -Name WSAIFabricSvc -ErrorAction SilentlyContinue) {
    Set-Service -Name WSAIFabricSvc -StartupType Disabled
}
if (Get-WindowsOptionalFeature -Online -FeatureName Recall -ErrorAction SilentlyContinue) {
    Disable-WindowsOptionalFeature -FeatureName Recall -Online -NoRestart | Out-Null
}

Write-Host "Windows AI Disabled"
