@echo off
rem Fettle installer: double-click with WoW closed. No Git or GitHub account needed.
rem Downloads the installer script from the public Fettle release copy and runs it.
title Fettle installer
echo Fettle installer: downloading the setup script (this can take a minute)...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; $p = 'kscarfe/fettle-releases'; $f = 'tools/guild/guild-install.ps1'; $t = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); $urls = @(('https://raw.githubusercontent.com/' + $p + '/main/' + $f + '?t=' + $t), ('https://api.github.com/repos/' + $p + '/contents/' + $f + '?ref=main'), ('https://cdn.jsdelivr.net/gh/' + $p + '@main/' + $f)); $s = $null; foreach ($u in $urls) { if (-not $s) { try { $c = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 20 -Uri $u -Headers @{ Accept = 'application/vnd.github.raw' }).Content; if ($c -is [byte[]]) { $c = [Text.Encoding]::UTF8.GetString($c) }; $s = $c } catch { Write-Host ('  ' + $u.Split('/')[2] + ': ' + $_.Exception.Message) -ForegroundColor DarkGray } } }; if ($s) { & ([scriptblock]::Create($s)) } else { Write-Host 'Download failed: none of the GitHub addresses answered.' -ForegroundColor Red; Write-Host 'Check your internet connection, or try again with your antivirus or VPN paused.' -ForegroundColor Yellow }"
echo.
pause
