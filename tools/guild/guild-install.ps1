<#
  Fettle installer for guildies: no Git, no GitHub account.
  Started by "Install Fettle.cmd" (double-click it, with WoW closed).

    1. Finds your WoW Forever Interface\AddOns folder (or asks).
    2. Downloads the latest Fettle from the public release copy and installs it.
    3. Adds a hidden scheduled task "Fettle updater" that checks for a new
       version every 15 minutes and when you sign in to Windows, plus an
       "Update Fettle" shortcut on your desktop.

  After an update you get a Windows notification: type /reload in WoW.
  Your Fettle settings live in WTF\...\SavedVariables and are never touched.
#>
param(
  [string]$AddOnsPath,
  [int]$Minutes = 15,
  [string]$Repo = "kscarfe/fettle-releases"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$TaskName = "Fettle updater"
$Home2 = Join-Path $env:LOCALAPPDATA "Fettle"
New-Item -ItemType Directory -Force -Path $Home2 | Out-Null

function Say($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color }

Say "Fettle installer" Cyan
Say ""

if (Get-Process -Name "Wow*" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch "^WowUp" }) {
  Say "WoW looks like it's running. Close the game, then double-click Install Fettle again." Yellow
  return
}

# --- 1. find the AddOns folder ----------------------------------------------------------
function Find-AddOns {
  $roots = @()
  foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null })) {
    foreach ($rel in @("Program Files (x86)\World of Warcraft", "Program Files\World of Warcraft",
                       "World of Warcraft", "Games\World of Warcraft", "Blizzard\World of Warcraft")) {
      $p = Join-Path $drive.Root $rel
      if (Test-Path $p) { $roots += $p }
    }
  }
  $found = @()
  foreach ($r in $roots) {
    foreach ($flavor in (Get-ChildItem -Path $r -Directory -ErrorAction SilentlyContinue)) {
      $i = Join-Path $flavor.FullName "Interface"
      if (Test-Path $i) {
        $a = Join-Path $i "AddOns"
        if (-not (Test-Path $a)) { New-Item -ItemType Directory -Force -Path $a | Out-Null }
        $found += $a
      }
    }
  }
  return $found
}

$configPath = Join-Path $Home2 "config.json"
if (-not $AddOnsPath -and (Test-Path $configPath)) {
  try { $old = Get-Content $configPath -Raw | ConvertFrom-Json; if ($old.AddOnsPath -and (Test-Path $old.AddOnsPath)) { $AddOnsPath = $old.AddOnsPath } } catch { }
}
if (-not $AddOnsPath) {
  $candidates = @(Find-AddOns)
  $forever = @($candidates | Where-Object { $_ -match "forever" })
  if ($forever.Count -eq 1) {
    $AddOnsPath = $forever[0]
  } elseif ($candidates.Count -gt 0) {
    Say "Found these AddOns folders:" Cyan
    for ($i = 0; $i -lt $candidates.Count; $i++) { Say ("  [{0}] {1}" -f ($i + 1), $candidates[$i]) }
    $pick = Read-Host "Type the number of the WoW Forever one (or paste a full path)"
    if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $candidates.Count) { $AddOnsPath = $candidates[[int]$pick - 1] }
    else { $AddOnsPath = $pick.Trim('"') }
  } else {
    Say "Couldn't find WoW automatically." Yellow
    Say "In the Battle.net app: select WoW Forever, click the cog next to Play, Show in Explorer. Then open Interface\AddOns." Yellow
    $AddOnsPath = (Read-Host "Paste the full path of the AddOns folder").Trim('"')
  }
}
if (-not (Test-Path $AddOnsPath)) { Say "Folder not found: $AddOnsPath" Red; return }
$AddOnsPath = (Resolve-Path $AddOnsPath).Path
Say "Using AddOns folder: $AddOnsPath" Green
$Target = Join-Path $AddOnsPath "Fettle"

# A Git checkout means this PC uses the developer updater.
if (Test-Path (Join-Path $Target ".git")) {
  Say "This PC updates Fettle with Git (the developer setup)." Yellow
  $ans = Read-Host "Switch it to the no-account updater instead? (y/n)"
  if ($ans -notmatch '^[yY]') { Say "Nothing changed." Green; return }
}

@{ AddOnsPath = $AddOnsPath; Repo = $Repo } | ConvertTo-Json | Set-Content -Path $configPath -Encoding UTF8

# --- 2. updater script, then run it once to install ------------------------------------------
$updater = Join-Path $Home2 "update.ps1"
$url = "https://raw.githubusercontent.com/$Repo/main/tools/guild/guild-update.ps1?t=" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Say "Downloading the updater..." Cyan
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $updater

Say "Installing the latest Fettle..." Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $updater -Install
if (-not (Test-Path (Join-Path $Target "Fettle.toc"))) {
  Say "The download didn't work. Check your internet connection and try again. Details: $(Join-Path $Home2 'update.log')" Red
  return
}

# --- 3. hidden scheduled task + desktop shortcut --------------------------------------------
$vbs = Join-Path $Home2 "run-hidden.vbs"
@"
' Runs the Fettle updater with no window. Any arguments are passed on (e.g. -Manual).
args = ""
For Each a In WScript.Arguments : args = args & " " & a : Next
CreateObject("Wscript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$updater""" & args, 0, False
"@ | Set-Content -Path $vbs -Encoding ASCII

$action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$vbs`""
$every = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes $Minutes)
$logon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($every, $logon) -Settings $settings `
  -Description "Keeps the Fettle WoW addon up to date (no GitHub account needed)." | Out-Null

try {
  $desktop = [Environment]::GetFolderPath("Desktop")
  $shell = New-Object -ComObject WScript.Shell
  $lnk = $shell.CreateShortcut((Join-Path $desktop "Update Fettle.lnk"))
  $lnk.TargetPath = "wscript.exe"
  $lnk.Arguments = "`"$vbs`" -Manual"
  $lnk.Description = "Check for a new version of Fettle now"
  $icon = Join-Path $Target "Media\icon.ico"
  if (Test-Path $icon) { $lnk.IconLocation = $icon }
  $lnk.Save()
} catch { Say "Couldn't add the desktop shortcut (not a problem)." Yellow }

$ver = (Select-String -Path (Join-Path $Target "Fettle.toc") -Pattern '^## Version:\s*(.+)$' | Select-Object -First 1).Matches[0].Groups[1].Value.Trim()
Say ""
Say "Done! Fettle $ver is installed." Green
Say "It checks for updates every $Minutes minutes and when you sign in to Windows."
Say "When one arrives you'll get a notification: type /reload in WoW."
Say "To check right now, double-click 'Update Fettle' on your desktop."
