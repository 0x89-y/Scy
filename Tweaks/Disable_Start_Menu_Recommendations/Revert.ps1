# Re-enable cloud-based recommendations
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_IrisRecommendations" -Value 1 -Type DWord

# Re-enable "Show recently added apps"
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -Value 1 -Type DWord

# Re-enable "Show recently opened items"
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackDocs" -Value 1 -Type DWord

# Remove the policy hiding the Recommended section
$policyPath = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
if (Test-Path $policyPath) {
    Remove-ItemProperty -Path $policyPath -Name "HideRecommendedSection" -ErrorAction SilentlyContinue
}
