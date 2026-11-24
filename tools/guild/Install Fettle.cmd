@echo off
rem Fettle installer: double-click with WoW closed. No Git or GitHub account needed.
rem Downloads the installer script from the public Fettle release copy and runs it.
title Fettle installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; try { $s = (Invoke-WebRequest -UseBasicParsing ('https://raw.githubusercontent.com/kscarfe/fettle-releases/main/tools/guild/guild-install.ps1?t=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())).Content; & ([scriptblock]::Create($s)) } catch { Write-Host ('Download failed: ' + $_) -ForegroundColor Red }"
echo.
pause
