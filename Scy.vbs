Dim shell, script
Set shell  = WScript.CreateObject("WScript.Shell")
script = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\")) & "Scy.ps1"
shell.Run "powershell.exe -ExecutionPolicy Bypass -File """ & script & """", 0, False
