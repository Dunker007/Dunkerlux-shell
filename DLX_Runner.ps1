# DLX_Runner.ps1
# GitHub Actions runner installer for Kamerta with Dataverse heartbeat and auto-repair

$Owner      = 'Dunker007'
$Repo       = 'dunkerlux-shell'
$RunnerName = "$env:COMPUTERNAME-kamerta"
$Labels     = 'kamerta,windows,x64,dlx'
$Ephemeral  = $false
$Root       = 'C:\DLXStudios\.runner'

# Ensure runner directory exists
New-Item -ItemType Directory -Force -Path $Root | Out-Null

# Download latest runner release
$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/actions/runner/releases/latest'
$asset = $release.assets | Where-Object { $_.name -like 'actions-runner-win-x64-*.zip' } | Select-Object -First 1
if (-not $asset) { throw "Could not locate Windows x64 asset in latest release." }
$zip = Join-Path $env:TEMP $asset.name
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip
Expand-Archive -Path $zip -DestinationPath $Root -Force
Remove-Item $zip -Force

# Stop/uninstall if already present
Push-Location $Root
try {
  try { & .\svc.cmd stop | Out-Null } catch {}
  try { & .\svc.cmd uninstall | Out-Null } catch {}

  # Token from env or prompt
  $token = $env:RUNNER_TOKEN
  if (-not $token) {
    Write-Host "Open runner token page to generate a token quickly…"
    Start-Process "https://github.com/$Owner/$Repo/settings/actions/runners/new?arch=x64&os=windows"
    $token = Read-Host -Prompt 'Paste the GitHub RUNNER registration token'
  }

  $args = @(
    '--url',    "https://github.com/$Owner/$Repo",
    '--token',  $token,
    '--name',   $RunnerName,
    '--labels', $Labels,
    '--unattended'
  )
  if ($Ephemeral) { $args += '--ephemeral' }

  Write-Host "Configuring runner '$RunnerName' for $Owner/$Repo with labels [$Labels]…"
  & .\config.cmd @args

  Write-Host "Installing service…"
  & .\svc.cmd install
  Write-Host "Starting service…"
  & .\svc.cmd start

  Write-Host "== Runner installed and running =="
  Write-Host "Verify: https://github.com/$Owner/$Repo/settings/actions/runners"
}
finally { Pop-Location }

# Log heartbeat to Dataverse
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$body = @{
  host = $env:COMPUTERNAME
  status = 'online'
  ts = $ts
  seq = [guid]::NewGuid().ToString()
  note = 'Runner installed and running'
}
$headers = @{ Authorization = "Bearer $env:DV_TOKEN" }
Invoke-RestMethod -Uri "$env:DV_URL/heartbeat" -Method Post -Headers $headers -Body ($body | ConvertTo-Json -Depth 3)
