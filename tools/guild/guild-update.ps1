<#
  Fettle updater for guildies (installed by guild-install.ps1 to
  %LOCALAPPDATA%\Fettle\update.ps1). Checks the public release copy's version
  and, when it's newer, downloads the zip and swaps the AddOns\Fettle folder.
  No Git or GitHub account needed.

    -Install   install even if a copy is already there
    -Manual    started from the desktop shortcut: always say what happened
#>
param([switch]$Install, [switch]$Manual)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$Home2 = Join-Path $env:LOCALAPPDATA "Fettle"
$log = Join-Path $Home2 "update.log"
function Log($msg) { Add-Content -Path $log -Value ((Get-Date -Format s) + "  " + $msg) }

function Notify($title, $body) {
  try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
    $esc = [System.Security.SecurityElement]
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml("<toast><visual><binding template=`"ToastGeneric`"><text>$($esc::Escape($title))</text><text>$($esc::Escape($body))</text></binding></visual></toast>")
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
  } catch { }
}

function Get-Version($tocText) {
  $m = [regex]::Match($tocText, '(?m)^## Version:\s*(\S+)')
  if ($m.Success) { return $m.Groups[1].Value.Trim() }
  return $null
}

function Is-Newer($a, $b) {
  # true if version a is newer than b
  try { return ([version]$a) -gt ([version]$b) } catch { return $a -ne $b }
}

try {
  $cfg = Get-Content (Join-Path $Home2 "config.json") -Raw | ConvertFrom-Json
  $addons = $cfg.AddOnsPath
  $repo = $cfg.Repo
  $target = Join-Path $addons "Fettle"
  $bust = "?t=" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

  $remoteToc = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 -Uri "https://raw.githubusercontent.com/$repo/main/Fettle.toc$bust").Content
  $remote = Get-Version $remoteToc
  if (-not $remote) { throw "couldn't read the online version" }

  $local = $null
  $localToc = Join-Path $target "Fettle.toc"
  if (Test-Path $localToc) { $local = Get-Version (Get-Content $localToc -Raw) }

  if (-not $Install -and $local -and -not (Is-Newer $remote $local)) {
    if ($Manual) { Notify "Fettle is up to date" "You have the latest version ($local)." }
    return
  }

  # download and unpack
  $tmp = Join-Path $env:TEMP ("fettle-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $zip = Join-Path $tmp "fettle.zip"
  Invoke-WebRequest -UseBasicParsing -TimeoutSec 120 -Uri "https://codeload.github.com/$repo/zip/refs/heads/main" -OutFile $zip
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  $src = Get-ChildItem -Path $tmp -Directory | Where-Object { Test-Path (Join-Path $_.FullName "Fettle.toc") } | Select-Object -First 1
  if (-not $src) { throw "the download doesn't look like Fettle" }

  # swap folders; keep the previous version for one update in case of trouble
  $prev = Join-Path $Home2 "previous"
  if (Test-Path $prev) { Remove-Item -Recurse -Force $prev }
  $staged = Join-Path $addons "Fettle.new"
  if (Test-Path $staged) { Remove-Item -Recurse -Force $staged }
  Copy-Item -Recurse -Path $src.FullName -Destination $staged
  if (Test-Path $target) { Move-Item -Path $target -Destination $prev }
  try { Move-Item -Path $staged -Destination $target }
  catch {
    # put the old version back so Fettle is never left missing
    if ((-not (Test-Path $target)) -and (Test-Path $prev)) { Move-Item -Path $prev -Destination $target }
    throw
  }
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

  $old = if ($local) { $local } else { "none" }
  Log "$old -> $remote"

  # keep this updater current too
  $newMe = Join-Path $target "tools\guild\guild-update.ps1"
  if (Test-Path $newMe) { Copy-Item -Path $newMe -Destination (Join-Path $Home2 "update.ps1") -Force }

  if (-not $Install) { Notify "Fettle $remote installed" "Type /reload in WoW to use it." }
} catch {
  Log ("ERROR " + $_)
  if ($Manual) { Notify "Fettle couldn't update" "Check your internet connection. Details in $log" }
} finally {
  if ((Test-Path $log) -and (Get-Item $log).Length -gt 200KB) { Get-Content $log -Tail 200 | Set-Content $log }
}
