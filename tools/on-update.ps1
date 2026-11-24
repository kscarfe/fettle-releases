<#
  Run by the Fettle updater right after it installs a new version.
  Shows a Windows notification so you know to /reload in WoW.
  Lives in the repo, so it updates itself along with Fettle.
#>
param([string]$Old = "?", [string]$New = "?", [string]$Target = "")

# One-time move: the repo's branch is now "master" (was "main").
try {
  $u = Join-Path $env:LOCALAPPDATA 'Fettle\update.ps1'
  if (Test-Path $u) {
    $t = Get-Content $u -Raw
    if ($t -match 'origin/main') { ($t -replace 'origin/main', 'origin/master') | Set-Content -Path $u -Encoding UTF8 }
  }
} catch { }

$title = "Fettle $New installed"
$body = "Type /reload in WoW to use it."
if ($Old -eq $New) { $title = "Fettle updated"; }

# 1. A Windows toast notification (Windows 10/11)
try {
  [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
  [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
  $esc = [System.Security.SecurityElement]
  $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
  $xml.LoadXml("<toast><visual><binding template=`"ToastGeneric`"><text>$($esc::Escape($title))</text><text>$($esc::Escape($body))</text></binding></visual></toast>")
  $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
  # Windows PowerShell's own app id, so no registration is needed
  $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
  return
} catch { }

# 2. Fallback: a tray balloon
try {
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $icon = New-Object System.Windows.Forms.NotifyIcon
  $icon.Icon = [System.Drawing.SystemIcons]::Information
  $icon.Visible = $true
  $icon.ShowBalloonTip(10000, $title, $body, [System.Windows.Forms.ToolTipIcon]::Info)
  Start-Sleep -Seconds 12
  $icon.Dispose()
} catch { }
