@echo off
rem Stops automatic Fettle updates. The addon stays installed: delete Interface\AddOns\Fettle yourself if you want it gone.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Unregister-ScheduledTask -TaskName 'Fettle updater' -Confirm:$false -ErrorAction SilentlyContinue; Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Update Fettle.lnk'); Write-Host 'Fettle updater removed.' -ForegroundColor Green"
pause
