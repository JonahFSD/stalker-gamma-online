# Deploy GAMMA MP Files — Claude Code Prompt

Paste everything below the line into Claude Code on Windows.

---

I have GAMMA Multiplayer fully built. Now deploy all the files to my Anomaly+GAMMA installation. The Anomaly install and GAMMA are both set up.

## Locate everything first

```powershell
# 1. Find the Anomaly installation
$anomalySearch = @(
    "C:\STALKER_Anomaly",
    "C:\ANOMALY",
    "D:\STALKER_Anomaly",
    "D:\ANOMALY",
    "$env:USERPROFILE\Desktop\ANOMALY",
    "$env:USERPROFILE\Desktop\Anomaly",
    "$env:USERPROFILE\Documents\ANOMALY"
)
$ANOMALY = $null
foreach ($p in $anomalySearch) {
    if (Test-Path "$p\gamedata") {
        $ANOMALY = $p
        break
    }
}
# Also search for AnomalyDX11.exe or AnomalyDX9.exe
if (-not $ANOMALY) {
    $found = Get-ChildItem -Path C:\,D:\ -Recurse -Depth 3 -Filter "AnomalyDX11.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) {
        $found = Get-ChildItem -Path C:\,D:\ -Recurse -Depth 3 -Filter "AnomalyDX9.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($found) { $ANOMALY = $found.DirectoryName }
}

if (-not $ANOMALY) {
    Write-Host "[FAIL] Could not find Anomaly installation. Search for it manually."
    exit 1
}
Write-Host "Anomaly found at: $ANOMALY"
```

```powershell
# 2. Source paths
$GAMMA_MP = "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp"
$ENGINE_BUILD = "$GAMMA_MP\xray-monolith\_build\_game\bin_dbg"
$GNS_BUILD = "$GAMMA_MP\gns-bridge\build\bin\Release"
$LUA_SYNC = "$GAMMA_MP\lua-sync"
```

## Step 1: Build AnomalyDX11 if not already built

```powershell
$dx11 = Get-ChildItem -Recurse -Filter "AnomalyDX11.exe" "$GAMMA_MP\xray-monolith\_build" -ErrorAction SilentlyContinue
if (-not $dx11) {
    Write-Host "AnomalyDX11.exe not found in build output. Attempting build..."
    
    $msbuild = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
    
    if ($msbuild) {
        Push-Location "$GAMMA_MP\xray-monolith"
        & $msbuild engine-vs2022.sln /t:AnomalyDX11 /p:Configuration=Release /p:Platform=x64 /m
        if ($LASTEXITCODE -ne 0) {
            # Try alternate target name
            & $msbuild engine-vs2022.sln /t:Anomaly_DX11 /p:Configuration=Release /p:Platform=x64 /m
        }
        Pop-Location
        
        $dx11 = Get-ChildItem -Recurse -Filter "AnomalyDX11.exe" "$GAMMA_MP\xray-monolith\_build" -ErrorAction SilentlyContinue
    }
}

if ($dx11) {
    Write-Host "[OK] AnomalyDX11.exe found: $($dx11.FullName)"
} else {
    Write-Host "[WARN] AnomalyDX11.exe not built. Will use DX9 if available."
}
```

## Step 2: Detect MO2 (GAMMA uses Mod Organizer 2)

```powershell
# GAMMA uses MO2's virtual filesystem. Scripts should go into the overwrite folder
# so MO2 layers them on top of everything else.
$mo2Exe = Get-ChildItem -Path $ANOMALY -Recurse -Depth 1 -Filter "ModOrganizer.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
$mo2Overwrite = $null

if ($mo2Exe) {
    # MO2's overwrite folder is typically alongside the mods folder
    $mo2Dir = $mo2Exe.DirectoryName
    $candidates = @(
        "$mo2Dir\overwrite",
        "$ANOMALY\overwrite",
        "$ANOMALY\profiles\Default\overwrite"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $mo2Overwrite = $c
            break
        }
    }
    if (-not $mo2Overwrite) {
        # Create it in the standard location
        $mo2Overwrite = "$mo2Dir\overwrite"
        New-Item -ItemType Directory -Force -Path $mo2Overwrite | Out-Null
    }
    Write-Host "MO2 detected. Overwrite folder: $mo2Overwrite"
} else {
    Write-Host "MO2 not detected. Deploying directly to gamedata."
}
```

## Step 3: Determine deployment targets

```powershell
# Where to put executables and DLLs
$binDir = if (Test-Path "$ANOMALY\bin") { "$ANOMALY\bin" } else { $ANOMALY }

# Where to put Lua scripts
if ($mo2Overwrite) {
    $scriptDest = "$mo2Overwrite\gamedata\scripts"
    Write-Host "Scripts will deploy to MO2 overwrite: $scriptDest"
} else {
    $scriptDest = "$ANOMALY\gamedata\scripts"
    Write-Host "Scripts will deploy to: $scriptDest"
}

New-Item -ItemType Directory -Force -Path $scriptDest | Out-Null
Write-Host "Bin dir: $binDir"
```

## Step 4: Deploy engine executable

```powershell
# Prefer DX11, fall back to DX9
$engineExe = Get-ChildItem -Recurse -Filter "AnomalyDX11.exe" "$GAMMA_MP\xray-monolith\_build" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $engineExe) {
    $engineExe = Get-ChildItem -Recurse -Filter "AnomalyDX9.exe" "$GAMMA_MP\xray-monolith\_build" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($engineExe) { Write-Host "WARNING: Only DX9 exe found. Using it." }
}

if ($engineExe) {
    $dest = "$binDir\$($engineExe.Name)"
    # Backup the original
    if (Test-Path $dest) {
        $bakDest = "$dest.vanilla.bak"
        if (-not (Test-Path $bakDest)) {
            Copy-Item $dest $bakDest -Force
            Write-Host "Backed up original: $($engineExe.Name) -> $($engineExe.Name).vanilla.bak"
        }
    }
    Copy-Item $engineExe.FullName $dest -Force
    Write-Host "[OK] Engine: $($engineExe.Name) ($([math]::Round($engineExe.Length / 1MB, 1)) MB)"
} else {
    Write-Host "[FAIL] No engine exe found in build output!"
}
```

## Step 5: Deploy GNS Bridge DLLs

```powershell
$gnsDlls = @(
    "gns_bridge.dll",
    "GameNetworkingSockets.dll",
    "abseil_dll.dll",
    "libcrypto-3-x64.dll",
    "libprotobuf.dll"
)

foreach ($dll in $gnsDlls) {
    $src = "$GNS_BUILD\$dll"
    if (Test-Path $src) {
        Copy-Item $src "$binDir\" -Force
        $sizeMB = [math]::Round((Get-Item $src).Length / 1MB, 1)
        Write-Host "[OK] $dll ($sizeMB MB)"
    } else {
        Write-Host "[FAIL] $dll not found at $src"
    }
}
```

## Step 6: Deploy Lua sync scripts

```powershell
$scripts = @(
    "mp_core.script",
    "mp_protocol.script",
    "mp_host_events.script",
    "mp_client_state.script"
)

foreach ($s in $scripts) {
    $src = "$LUA_SYNC\$s"
    if (Test-Path $src) {
        Copy-Item $src "$scriptDest\" -Force
        Write-Host "[OK] $s"
    } else {
        Write-Host "[FAIL] $s not found at $src"
    }
}
```

## Step 7: Firewall rules

```powershell
try {
    $existing = Get-NetFirewallRule -DisplayName "GAMMA MP*" -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule -DisplayName "GAMMA MP UDP" -Direction Inbound -Protocol UDP -LocalPort 44140 -Action Allow | Out-Null
        New-NetFirewallRule -DisplayName "GAMMA MP TCP" -Direction Inbound -Protocol TCP -LocalPort 44140 -Action Allow | Out-Null
        Write-Host "[OK] Firewall rules added (port 44140 UDP+TCP)"
    } else {
        Write-Host "[OK] Firewall rules already exist"
    }
} catch {
    Write-Host "[WARN] Could not add firewall rules (need Admin). Run as admin or add manually."
}
```

## Step 8: Full Verification

```powershell
Write-Host ""
Write-Host "========================================="
Write-Host " GAMMA MP Deployment Verification"
Write-Host "========================================="
Write-Host ""

$allGood = $true
$results = @()

# Engine exe
$exes = Get-ChildItem "$binDir\Anomaly*.exe" -ErrorAction SilentlyContinue
foreach ($e in $exes) {
    $sizeMB = [math]::Round($e.Length / 1MB, 1)
    $results += "[OK] $($e.Name) ($sizeMB MB)"
}
if (-not $exes) { $results += "[FAIL] No engine exe in $binDir"; $allGood = $false }

# GNS DLLs
foreach ($dll in @("gns_bridge.dll", "GameNetworkingSockets.dll", "abseil_dll.dll", "libcrypto-3-x64.dll", "libprotobuf.dll")) {
    if (Test-Path "$binDir\$dll") {
        $results += "[OK] $dll"
    } else {
        $results += "[FAIL] $dll missing from $binDir"
        $allGood = $false
    }
}

# Lua scripts
foreach ($s in @("mp_core.script", "mp_protocol.script", "mp_host_events.script", "mp_client_state.script")) {
    if (Test-Path "$scriptDest\$s") {
        $results += "[OK] $s"
    } else {
        $results += "[FAIL] $s missing from $scriptDest"
        $allGood = $false
    }
}

# Firewall
$fw = Get-NetFirewallRule -DisplayName "GAMMA MP*" -ErrorAction SilentlyContinue
if ($fw) { $results += "[OK] Firewall rules" } else { $results += "[WARN] Firewall rules not set" }

foreach ($r in $results) { Write-Host $r }

Write-Host ""
if ($allGood) {
    Write-Host "ALL DEPLOYED SUCCESSFULLY" -ForegroundColor Green
    Write-Host ""
    Write-Host "Deployment summary:"
    Write-Host "  Anomaly:  $ANOMALY"
    Write-Host "  Bin dir:  $binDir"
    Write-Host "  Scripts:  $scriptDest"
    Write-Host "  MO2:      $(if ($mo2Overwrite) { 'Yes' } else { 'No' })"
    Write-Host ""
    Write-Host "Next: Launch the game and test with CLAUDE_CODE_TEST.md"
} else {
    Write-Host "SOME ITEMS FAILED — check above" -ForegroundColor Red
}
```

## Report Back

Tell me:
1. Where was Anomaly found?
2. Was MO2 detected? Where did scripts go?
3. Which engine exe was deployed (DX11 or DX9)?
4. Did all 5 GNS DLLs deploy?
5. Did all 4 Lua scripts deploy?
6. Any failures?
