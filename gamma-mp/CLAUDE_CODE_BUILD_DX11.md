# Build DX11 + Install Anomaly + GAMMA + Deploy — Claude Code Prompt

Paste everything below the line into Claude Code on Windows.

---

I have an xray-monolith engine fork at `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\xray-monolith` with all multiplayer patches applied. AnomalyDX9.exe already built successfully (all 31 projects compiled). I need you to: build the DX11 exe, install Anomaly + GAMMA, and deploy the multiplayer files.

## Step 1: Build AnomalyDX11

Find MSBuild:
```powershell
$msbuild = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
```

Build the DX11 target (dependencies are already built, so this should be fast):
```powershell
cd "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\xray-monolith"
& $msbuild engine-vs2022.sln /t:AnomalyDX11 /p:Configuration=Release /p:Platform=x64 /m
```

If `AnomalyDX11` isn't a valid target name, try these in order:
1. `/t:Anomaly_DX11`
2. Full rebuild: `& $msbuild engine-vs2022.sln /p:Configuration=Release /p:Platform=x64 /m` (skips already-built projects)
3. `batch_build.bat` in the xray-monolith root

Verify:
```powershell
Get-ChildItem -Recurse -Filter "Anomaly*" "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\xray-monolith\_build" | Where-Object { $_.Extension -eq '.exe' }
```

## Step 2: Install STALKER Anomaly 1.5.3

Anomaly is a free standalone game (~9GB). It's distributed as a torrent or direct download from moddb.

**Option A — Direct download (preferred):**
Go to https://www.moddb.com/mods/stalker-anomaly/downloads and find "STALKER Anomaly 1.5.3" (it's usually split into multiple parts). The download links are on moddb.

Since downloading 9GB through the terminal is painful, here's what to do:
1. Check if I already downloaded it somewhere:
```powershell
# Search for existing Anomaly installations or downloads
$searchDirs = @("C:\", "D:\", "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents")
foreach ($dir in $searchDirs) {
    Get-ChildItem -Path $dir -Recurse -Depth 3 -Filter "AnomalyDX11.exe" -ErrorAction SilentlyContinue | Select-Object FullName
    Get-ChildItem -Path $dir -Recurse -Depth 3 -Filter "Anomaly-*" -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.7z','.zip','.exe' } | Select-Object FullName
}
# Also check for any folder named Anomaly
Get-ChildItem -Path C:\,D:\ -Recurse -Depth 2 -Directory -Filter "*Anomaly*" -ErrorAction SilentlyContinue | Select-Object FullName
```

2. If not found anywhere, tell me to download it manually. Give me this message:
> **I need you to download STALKER Anomaly 1.5.3:**
> 1. Go to https://www.moddb.com/mods/stalker-anomaly/downloads
> 2. Download all parts of "Anomaly 1.5.3"
> 3. Extract to `C:\STALKER_Anomaly`
> 4. Re-run this prompt after extraction

3. If found, note the path as `$ANOMALY` and continue.

The Anomaly folder structure should look like:
```
STALKER_Anomaly/
├── bin/                 ← engine executables go here
├── gamedata/
│   └── scripts/         ← Lua scripts go here
├── db/                  ← game databases
└── AnomalyDX11.exe     ← or in bin/, depends on version
```

Find where the stock `AnomalyDX11.exe` lives (could be root or bin/):
```powershell
Get-ChildItem -Recurse -Filter "AnomalyDX11*" $ANOMALY | Select-Object FullName
```

## Step 3: Install GAMMA Modpack

The GAMMA repo is already cloned at:
`C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\Stalker_GAMMA`

The GAMMA installer is at:
```
Stalker_GAMMA\.Grok's Modpack Installer\G.A.M.M.A. Launcher.exe
```

**IMPORTANT:** The GAMMA installer is a GUI application that downloads 400+ mods. It takes 20-40 minutes and needs user interaction. You cannot run it silently.

Tell me:
> **Run the GAMMA installer:**
> 1. Open: `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\Stalker_GAMMA\.Grok's Modpack Installer\G.A.M.M.A. Launcher.exe`
> 2. Point it at your Anomaly installation (`C:\STALKER_Anomaly` or wherever you extracted it)
> 3. Let it download all mods (20-40 min)
> 4. When done, tell me and I'll deploy the multiplayer files

If GAMMA is already installed (check for MO2 or a `MODS` folder inside the Anomaly directory), skip this step.

Check:
```powershell
# Check if GAMMA/MO2 is already set up
$gammaIndicators = @(
    "$ANOMALY\MODS",
    "$ANOMALY\ModOrganizer.exe", 
    "$env:LOCALAPPDATA\GAMMA",
    "$ANOMALY\profiles"
)
$gammaInstalled = $false
foreach ($p in $gammaIndicators) {
    if (Test-Path $p) { 
        Write-Host "GAMMA indicator found: $p"
        $gammaInstalled = $true
    }
}
if (-not $gammaInstalled) {
    Write-Host "GAMMA does not appear to be installed yet"
}
```

## Step 4: Deploy Multiplayer Files

Once Anomaly + GAMMA are installed, deploy our files.

```powershell
$ANOMALY = "C:\STALKER_Anomaly"  # UPDATE THIS to actual path
$GAMMA_MP = "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp"
$ENGINE_BUILD = "$GAMMA_MP\xray-monolith\_build"
$GNS_BUILD = "$GAMMA_MP\gns-bridge\build\bin\Release"
$LUA_SYNC = "$GAMMA_MP\lua-sync"

# Find the bin folder (could be $ANOMALY\bin or just $ANOMALY depending on setup)
$binDir = if (Test-Path "$ANOMALY\bin") { "$ANOMALY\bin" } else { $ANOMALY }

# Find the scripts folder
# If GAMMA uses MO2, scripts should go into the MO2 overwrite folder instead
$mo2Overwrite = Get-ChildItem -Path $ANOMALY -Recurse -Depth 2 -Directory -Filter "overwrite" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($mo2Overwrite) {
    $scriptDest = "$($mo2Overwrite.FullName)\gamedata\scripts"
    Write-Host "MO2 detected — deploying scripts to overwrite folder: $scriptDest"
} else {
    $scriptDest = "$ANOMALY\gamedata\scripts"
}

New-Item -ItemType Directory -Force -Path $scriptDest | Out-Null

# --- Deploy engine exe ---
$engineExe = Get-ChildItem -Recurse -Filter "AnomalyDX11.exe" $ENGINE_BUILD -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $engineExe) {
    $engineExe = Get-ChildItem -Recurse -Filter "AnomalyDX9.exe" $ENGINE_BUILD -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($engineExe) { Write-Host "WARNING: Only DX9 exe found. Using it for now." }
}

if ($engineExe) {
    $dest = "$binDir\$($engineExe.Name)"
    if (Test-Path $dest) {
        Copy-Item $dest "$dest.bak" -Force
        Write-Host "Backed up: $($engineExe.Name) -> $($engineExe.Name).bak"
    }
    Copy-Item $engineExe.FullName $dest -Force
    Write-Host "[OK] Engine exe deployed: $dest"
} else {
    Write-Host "[FAIL] No engine exe found in build output!"
}

# --- Deploy GNS bridge DLLs ---
$gnsDlls = @("gns_bridge.dll", "GameNetworkingSockets.dll", "abseil_dll.dll", "libcrypto-3-x64.dll", "libprotobuf.dll")
foreach ($dll in $gnsDlls) {
    $src = "$GNS_BUILD\$dll"
    if (Test-Path $src) {
        Copy-Item $src "$binDir\" -Force
        Write-Host "[OK] $dll"
    } else {
        Write-Host "[WARN] $dll not found"
    }
}

# --- Deploy Lua sync scripts ---
$scripts = @("mp_core.script", "mp_protocol.script", "mp_host_events.script", "mp_client_state.script")
foreach ($s in $scripts) {
    $src = "$LUA_SYNC\$s"
    if (Test-Path $src) {
        Copy-Item $src "$scriptDest\" -Force
        Write-Host "[OK] $s"
    } else {
        Write-Host "[FAIL] $s not found at $src"
    }
}

# --- Add firewall rule ---
try {
    $existing = Get-NetFirewallRule -DisplayName "GAMMA MP*" -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule -DisplayName "GAMMA MP UDP" -Direction Inbound -Protocol UDP -LocalPort 44140 -Action Allow | Out-Null
        New-NetFirewallRule -DisplayName "GAMMA MP TCP" -Direction Inbound -Protocol TCP -LocalPort 44140 -Action Allow | Out-Null
        Write-Host "[OK] Firewall rules added (port 44140)"
    } else {
        Write-Host "[OK] Firewall rules already exist"
    }
} catch {
    Write-Host "[WARN] Could not add firewall rules (need Admin)"
}
```

## Step 5: Verify Everything

```powershell
Write-Host ""
Write-Host "========================================="
Write-Host " GAMMA MP Deployment Verification"
Write-Host "========================================="
Write-Host ""

$allGood = $true

# Engine exe
$exes = Get-ChildItem "$binDir\Anomaly*.exe" -ErrorAction SilentlyContinue
foreach ($e in $exes) {
    $sizeMB = [math]::Round($e.Length / 1MB, 1)
    Write-Host "[OK] $($e.Name) ($sizeMB MB)"
}
if (-not $exes) { Write-Host "[FAIL] No engine exe"; $allGood = $false }

# GNS DLLs
foreach ($dll in @("gns_bridge.dll", "GameNetworkingSockets.dll")) {
    if (Test-Path "$binDir\$dll") {
        Write-Host "[OK] $dll"
    } else {
        Write-Host "[FAIL] $dll missing"; $allGood = $false
    }
}

# Lua scripts
foreach ($s in @("mp_core.script", "mp_protocol.script", "mp_host_events.script", "mp_client_state.script")) {
    if (Test-Path "$scriptDest\$s") {
        Write-Host "[OK] $s"
    } else {
        Write-Host "[FAIL] $s missing"; $allGood = $false
    }
}

Write-Host ""
if ($allGood) {
    Write-Host "ALL GOOD. Ready to test!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Test procedure:"
    Write-Host "  1. Launch GAMMA normally"
    Write-Host "  2. Load a save or start new game"
    Write-Host "  3. Open console (~) and type: mp_core.mp_init()"
    Write-Host "  4. Should print: [GAMMA MP] v0.1.0-alpha initialized"
    Write-Host "  5. Then: mp_core.mp_status()"
    Write-Host "  6. Then test A-Life suppression: alife():set_mp_client_mode(true)"
    Write-Host "  7. NPCs should freeze. Then: alife():set_mp_client_mode(false)"
    Write-Host "  8. NPCs should resume. No crashes = Phase 0 PASSED"
} else {
    Write-Host "Some items failed — check above" -ForegroundColor Red
}
```

## Step 6: Report Back

Tell me:
1. Did AnomalyDX11.exe build? If only DX9, what error for DX11?
2. Was Anomaly found or does it need to be downloaded?
3. Is GAMMA installed or does the installer need to be run?
4. Deployment results — what passed, what failed?
5. If everything deployed, did the game launch?

## Key paths on this machine:
- Engine source: `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\xray-monolith`
- GNS bridge build: `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\gns-bridge\build\bin\Release`
- Lua scripts: `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\lua-sync`
- GAMMA repo: `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\Stalker_GAMMA`
