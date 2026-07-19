# Best-effort revert. winutil ships no undo for this tweak: removed Copilot /
# CoreAI / Office Hub packages cannot be restored here and must be reinstalled
# from the Store or winget. This only undoes the policy + service/feature changes.
$explorer = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
if (Test-Path $explorer) { Remove-ItemProperty -Path $explorer -Name "SettingsPageVisibility" -ErrorAction SilentlyContinue }

$notepad = "HKLM:\SOFTWARE\Policies\WindowsNotepad"
if (Test-Path $notepad) { Remove-ItemProperty -Path $notepad -Name "DisableAIFeatures" -ErrorAction SilentlyContinue }

Set-Service -Name WSAIFabricSvc -StartupType Manual -ErrorAction SilentlyContinue
Enable-WindowsOptionalFeature -FeatureName Recall -Online -NoRestart -ErrorAction SilentlyContinue

Write-Host "Windows AI policy reverted (removed packages must be reinstalled manually)"
