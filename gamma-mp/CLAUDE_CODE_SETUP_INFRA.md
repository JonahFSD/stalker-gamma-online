# Claude Code Prompt: Set Up GAMMA MP Development Infrastructure

## Context

You're setting up infrastructure for the GAMMA Multiplayer project. The codebase already exists and compiles. This prompt sets up the AGENT TOOLING — the files that make future Claude Code sessions efficient instead of blind.

## What Already Exists

- Source code: `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\`
- Compiled engine: `C:\ANOMALY\bin\AnomalyDX11AVX.exe` (patched)
- Compiled DLLs: `C:\ANOMALY\bin\gns_bridge.dll` + dependencies
- Lua scripts: `C:\GAMMA\overwrite\gamedata\scripts\mp_*.script`
- UI: `C:\GAMMA\overwrite\gamedata\configs\ui\ui_mp_menu.xml`

## What You're Creating/Verifying

### 1. CLAUDE.md (Agent Context Pin)

Location: `stalker-gamma-online/.claude/CLAUDE.md`

This file should already exist. Verify it's present and contains:
- Architecture overview
- PIN (file map with every file, its purpose, key functions, key state)
- Cross-file call map
- Entity ID mapping flow
- Client sync state machine
- Message types table
- Callback registrations table
- Technical notes

If it doesn't exist or is incomplete, create it. Reference the existing CLAUDE.md as the template. Every field must be populated from actual code — read the files, don't guess.

### 2. BUG_TRACKER.md

Location: `stalker-gamma-online/gamma-mp/BUG_TRACKER.md`

This file should already exist. Verify it contains entries for all 15 identified bugs:
- Bugs #1, #2, #4, #13: FIXED
- Bug #5: CONFIRMED_SAFE
- Bugs #3, #6, #7, #8, #9, #10, #11, #12, #14, #15: OPEN

Each entry must have: severity, file location, problem description, and proposed fix.

If any bug entries are missing or incomplete, read the actual code and fill them in.

### 3. Verify Deployment State

Run these checks silently. Report only failures:

```powershell
# Check engine exe is patched (should be our build, not stock)
$exe = "C:\ANOMALY\bin\AnomalyDX11AVX.exe"
if (Test-Path $exe) {
    $size = (Get-Item $exe).Length
    Write-Host "AnomalyDX11AVX.exe: $($size / 1MB) MB"
    # Our patched build is ~24MB. Stock is different.
}

# Check DLLs are present
$dlls = @("gns_bridge.dll", "GameNetworkingSockets.dll")
foreach ($dll in $dlls) {
    if (!(Test-Path "C:\ANOMALY\bin\$dll")) {
        Write-Host "MISSING: C:\ANOMALY\bin\$dll"
    }
}

# Check Lua scripts are deployed
$scripts = @("mp_core.script", "mp_protocol.script", "mp_host_events.script", "mp_client_state.script", "mp_ui.script")
foreach ($s in $scripts) {
    $deployed = "C:\GAMMA\overwrite\gamedata\scripts\$s"
    $source = "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\lua-sync\$s"
    if (!(Test-Path $deployed)) {
        Write-Host "NOT DEPLOYED: $s"
    } elseif ((Get-FileHash $deployed).Hash -ne (Get-FileHash $source).Hash) {
        Write-Host "OUT OF DATE: $s (source != deployed)"
    }
}

# Check UI XML
$xml_deployed = "C:\GAMMA\overwrite\gamedata\configs\ui\ui_mp_menu.xml"
$xml_source = "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\lua-sync\ui\ui_mp_menu.xml"
if (!(Test-Path $xml_deployed)) {
    Write-Host "NOT DEPLOYED: ui_mp_menu.xml"
} elseif ((Get-FileHash $xml_deployed).Hash -ne (Get-FileHash $xml_source).Hash) {
    Write-Host "OUT OF DATE: ui_mp_menu.xml"
}
```

### 4. Deploy Script

Create `gamma-mp/deploy.ps1` if it doesn't exist:

```powershell
# deploy.ps1 — Copy all MP files from source to GAMMA
# Run from repo root: .\gamma-mp\deploy.ps1

$ErrorActionPreference = "Stop"
$source = Split-Path $PSScriptRoot -Parent
$gammaScripts = "C:\GAMMA\overwrite\gamedata\scripts"
$gammaUI = "C:\GAMMA\overwrite\gamedata\configs\ui"
$anomalyBin = "C:\ANOMALY\bin"

Write-Host "Deploying GAMMA MP files..." -ForegroundColor Cyan

# Lua scripts
$scripts = @("mp_core.script", "mp_protocol.script", "mp_host_events.script", "mp_client_state.script", "mp_ui.script")
foreach ($s in $scripts) {
    Copy-Item "$source\gamma-mp\lua-sync\$s" "$gammaScripts\$s" -Force
    Write-Host "  [OK] $s" -ForegroundColor Green
}

# UI XML
Copy-Item "$source\gamma-mp\lua-sync\ui\ui_mp_menu.xml" "$gammaUI\ui_mp_menu.xml" -Force
Write-Host "  [OK] ui_mp_menu.xml" -ForegroundColor Green

Write-Host "`nDeploy complete. Restart the game to pick up changes." -ForegroundColor Cyan
```

### 5. Quick-Test Checklist File

Create `gamma-mp/TEST_CHECKLIST.md` if it doesn't exist:

```markdown
# GAMMA MP Quick Test Checklist

Run after every code change + deploy.

## Pre-Flight
- [ ] `deploy.ps1` ran clean (no errors)
- [ ] Launch GAMMA through MO2

## Basic Startup
- [ ] Game loads without crash
- [ ] Console shows `[GAMMA MP] Core module loaded`
- [ ] F10 opens MP menu
- [ ] ESC closes MP menu
- [ ] Menu shows version and "Idle — not connected" status

## Host Mode
- [ ] Click Host → status shows "Hosting on port 44140"
- [ ] Click Status → shows "0 clients, N entities tracked"
- [ ] Click Stop Host → status shows "Hosting stopped"

## Client Mode (requires second instance or second machine)
- [ ] Enter host IP, click Connect
- [ ] Status shows "Connecting to IP:44140..."
- [ ] On success: "Connected — cleaning" → "syncing" → "active"
- [ ] Status shows entity count and ID mappings
- [ ] Click Disconnect → "Disconnected"

## Regression Checks
- [ ] F5 (quicksave) shows "Save disabled" message when connected
- [ ] Game doesn't crash on disconnect
- [ ] Game doesn't crash on reconnect
- [ ] Host can stop hosting cleanly
- [ ] Shutdown button cleans up everything
```

## What NOT To Do

- Do NOT rebuild the engine or DLLs
- Do NOT modify any C++ files
- Do NOT modify .script files (this prompt is infrastructure only)
- Do NOT push to git (just verify/create files locally)

## Output

When done, report:
1. CLAUDE.md status (created / verified / updated)
2. BUG_TRACKER.md status
3. Deployment state (all files current / list of out-of-date files)
4. deploy.ps1 status (created / already existed)
5. TEST_CHECKLIST.md status
