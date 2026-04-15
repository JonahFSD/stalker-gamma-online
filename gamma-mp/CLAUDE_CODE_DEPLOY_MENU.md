# Deploy MP Menu + Updated Scripts — Claude Code Prompt

Paste everything below the line into Claude Code on Windows.

---

## What Changed

- **mp_ui.script** (NEW): In-game multiplayer menu with Host/Connect/Disconnect/Status/Shutdown buttons and IP/port input fields. Opens on F10.
- **ui_mp_menu.xml** (NEW): XML layout for the MP menu UI.
- **mp_core.script** (UPDATED): F10 now opens the menu instead of cycling through states.

## Paths

```
$GAMMA = "C:\GAMMA"
$LUA_SYNC = "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\lua-sync"
```

## Step 1: Find MO2 overwrite

```powershell
$GAMMA = "C:\GAMMA"

$overwrite = $null
$candidates = @(
    "$GAMMA\overwrite",
    "$GAMMA\ModOrganizer\overwrite",
    "$GAMMA\MO2\overwrite"
)
foreach ($c in $candidates) {
    if (Test-Path $c) { $overwrite = $c; break }
}
if (-not $overwrite) {
    $found = Get-ChildItem -Path $GAMMA -Recurse -Depth 3 -Directory -Filter "overwrite" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $overwrite = $found.FullName }
}
if (-not $overwrite) {
    Write-Host "[FAIL] Cannot find MO2 overwrite folder"
    exit 1
}

$scriptDest = "$overwrite\gamedata\scripts"
$uiDest = "$overwrite\gamedata\configs\ui"
New-Item -ItemType Directory -Force -Path $scriptDest | Out-Null
New-Item -ItemType Directory -Force -Path $uiDest | Out-Null

Write-Host "Scripts: $scriptDest"
Write-Host "UI XML:  $uiDest"
```

## Step 2: Deploy scripts

```powershell
$LUA_SYNC = "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\lua-sync"

# Lua scripts -> gamedata\scripts\
$scripts = @(
    "mp_core.script",
    "mp_protocol.script",
    "mp_host_events.script",
    "mp_client_state.script",
    "mp_ui.script"
)

foreach ($s in $scripts) {
    $src = "$LUA_SYNC\$s"
    if (Test-Path $src) {
        Copy-Item $src "$scriptDest\$s" -Force
        Write-Host "[OK] $s -> scripts\"
    } else {
        Write-Host "[FAIL] $s not found at $src"
    }
}

# XML layout -> gamedata\configs\ui\
$xmlSrc = "$LUA_SYNC\ui\ui_mp_menu.xml"
if (Test-Path $xmlSrc) {
    Copy-Item $xmlSrc "$uiDest\ui_mp_menu.xml" -Force
    Write-Host "[OK] ui_mp_menu.xml -> configs\ui\"
} else {
    Write-Host "[FAIL] ui_mp_menu.xml not found at $xmlSrc"
}
```

## Step 3: Verify

```powershell
Write-Host ""
Write-Host "========================================="
Write-Host " MP Menu Deploy Verification"
Write-Host "========================================="

$allGood = $true

foreach ($s in @("mp_core.script", "mp_protocol.script", "mp_host_events.script", "mp_client_state.script", "mp_ui.script")) {
    if (Test-Path "$scriptDest\$s") { Write-Host "[OK] $s" }
    else { Write-Host "[FAIL] $s"; $allGood = $false }
}

if (Test-Path "$uiDest\ui_mp_menu.xml") { Write-Host "[OK] ui_mp_menu.xml" }
else { Write-Host "[FAIL] ui_mp_menu.xml"; $allGood = $false }

Write-Host ""
if ($allGood) {
    Write-Host "ALL GOOD — Launch GAMMA, press F10 to open the MP menu." -ForegroundColor Green
} else {
    Write-Host "ISSUES FOUND" -ForegroundColor Red
}
```
