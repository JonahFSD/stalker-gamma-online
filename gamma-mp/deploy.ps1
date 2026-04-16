# deploy.ps1 — Copy all MP files from source to GAMMA
# Run from repo root: .\gamma-mp\deploy.ps1

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$gammaScripts = "C:\GAMMA\overwrite\gamedata\scripts"
$gammaUI = "C:\GAMMA\overwrite\gamedata\configs\ui"

Write-Host "Deploying GAMMA MP files..." -ForegroundColor Cyan
Write-Host "  Source: $repoRoot\gamma-mp\" -ForegroundColor DarkGray

# Ensure target dirs exist
New-Item -ItemType Directory -Path $gammaScripts -Force | Out-Null
New-Item -ItemType Directory -Path $gammaUI -Force | Out-Null

# Lua scripts
$scripts = @("mp_core.script", "mp_protocol.script", "mp_host_events.script", "mp_client_state.script", "mp_alife_guard.script", "mp_puppet.script", "mp_ui.script")
foreach ($s in $scripts) {
    $src = "$repoRoot\gamma-mp\lua-sync\$s"
    $dst = "$gammaScripts\$s"
    if (!(Test-Path $src)) {
        Write-Host "  [SKIP] $s (not found in source)" -ForegroundColor Yellow
        continue
    }
    Copy-Item $src $dst -Force
    Write-Host "  [OK] $s" -ForegroundColor Green
}

# UI XML
$xmlSrc = "$repoRoot\gamma-mp\lua-sync\ui\ui_mp_menu.xml"
$xmlDst = "$gammaUI\ui_mp_menu.xml"
if (Test-Path $xmlSrc) {
    Copy-Item $xmlSrc $xmlDst -Force
    Write-Host "  [OK] ui_mp_menu.xml" -ForegroundColor Green
} else {
    Write-Host "  [SKIP] ui_mp_menu.xml (not found)" -ForegroundColor Yellow
}

Write-Host "`nDeploy complete. Restart the game to pick up changes." -ForegroundColor Cyan
