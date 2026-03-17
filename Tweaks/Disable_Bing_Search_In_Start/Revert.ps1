$path = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
if (Test-Path $path) {
    Remove-ItemProperty -Path $path -Name "DisableSearchBoxSuggestions" -ErrorAction SilentlyContinue
}
