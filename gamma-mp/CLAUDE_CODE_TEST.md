# GAMMA MP In-Game Test Protocol — Claude Code Prompt

Paste everything below the line into Claude Code on Windows.

---

GAMMA MP is deployed. I need you to help me verify the installation and walk me through the in-game test. You can't launch the game yourself, but you CAN verify files, check logs after I run the game, and diagnose any errors.

## Pre-flight Check

Run this verification before I launch:

```powershell
# Find the Anomaly install
$anomalySearch = @("C:\STALKER_Anomaly", "C:\ANOMALY", "D:\STALKER_Anomaly", "D:\ANOMALY")
$ANOMALY = $null
foreach ($p in $anomalySearch) {
    if (Test-Path "$p\gamedata") { $ANOMALY = $p; break }
}
if (-not $ANOMALY) {
    Get-ChildItem -Path C:\,D:\ -Recurse -Depth 3 -Filter "AnomalyDX11.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object { $ANOMALY = $_.DirectoryName }
}

$binDir = if (Test-Path "$ANOMALY\bin") { "$ANOMALY\bin" } else { $ANOMALY }

Write-Host "=== PRE-FLIGHT CHECK ==="
Write-Host ""

# Check engine exe
$engineExe = Get-ChildItem "$binDir\Anomaly*.exe" -ErrorAction SilentlyContinue
foreach ($e in $engineExe) {
    $sizeMB = [math]::Round($e.Length / 1MB, 1)
    $isOurs = $sizeMB -gt 20  # Our build is ~24MB, stock is different
    Write-Host "[$(if($isOurs){'OK'}else{'??'})] $($e.Name) ($sizeMB MB) $(if($isOurs){'(MP build)'}else{'(stock?)'})"
}

# Check GNS DLLs — all 5 required
$gnsDlls = @("gns_bridge.dll", "GameNetworkingSockets.dll", "abseil_dll.dll", "libcrypto-3-x64.dll", "libprotobuf.dll")
$dllOk = $true
foreach ($dll in $gnsDlls) {
    $path = "$binDir\$dll"
    if (Test-Path $path) {
        Write-Host "[OK] $dll"
    } else {
        Write-Host "[FAIL] $dll MISSING"
        $dllOk = $false
    }
}

# Check Lua scripts — look in multiple possible locations
$scriptLocations = @()
# Direct gamedata
if (Test-Path "$ANOMALY\gamedata\scripts\mp_core.script") {
    $scriptLocations += "$ANOMALY\gamedata\scripts"
}
# MO2 overwrite
$mo2Scripts = Get-ChildItem -Path $ANOMALY -Recurse -Depth 3 -Filter "mp_core.script" -ErrorAction SilentlyContinue
foreach ($s in $mo2Scripts) {
    $scriptLocations += $s.DirectoryName
}

if ($scriptLocations.Count -gt 0) {
    foreach ($loc in $scriptLocations | Select-Object -Unique) {
        Write-Host ""
        Write-Host "Scripts found in: $loc"
        foreach ($s in @("mp_core.script", "mp_protocol.script", "mp_host_events.script", "mp_client_state.script")) {
            if (Test-Path "$loc\$s") {
                Write-Host "[OK] $s"
            } else {
                Write-Host "[FAIL] $s MISSING"
            }
        }
    }
} else {
    Write-Host "[FAIL] NO MP SCRIPTS FOUND ANYWHERE"
}

# Check firewall
$fw = Get-NetFirewallRule -DisplayName "GAMMA MP*" -ErrorAction SilentlyContinue
if ($fw) {
    Write-Host ""
    Write-Host "[OK] Firewall rules set for port 44140"
} else {
    Write-Host ""
    Write-Host "[WARN] No firewall rules for GAMMA MP"
}

Write-Host ""
Write-Host "=== PRE-FLIGHT COMPLETE ==="
```

## In-Game Test Procedure

Tell the user to follow these steps:

### Test 1: Module Loading
```
1. Launch GAMMA normally (through MO2 if using MO2)
2. Start a new game or load a save
3. Open the console with ~ (tilde)
4. Type exactly: mp_core.mp_init()
5. Expected output: [GAMMA MP] v0.1.0-alpha initialized
```

If it prints the version string, the GNS bridge DLL loaded, Lua bindings work, and the script loaded correctly.

If it errors with "attempt to index a nil value" on `gns`, the DLL didn't load. Check:
- Is `gns_bridge.dll` in the bin folder?
- Are ALL 5 dependency DLLs present? (Missing even one = crash)
- Was the engine exe replaced with our MP build?

### Test 2: Hosting
```
6. Type: mp_core.mp_host()
7. Expected: [GAMMA MP] Hosting on port 44140
8. Type: mp_core.mp_status()
9. Expected: Shows Host: true, Port: 44140, Clients: 0, Tracked entities: [some number]
```

The tracked entity count should be in the thousands (typical GAMMA world has 3000-8000 entities).

### Test 3: A-Life Suppression (Client Mode Simulation)
```
10. Type: alife():set_mp_client_mode(true)
11. Expected: * [GAMMA MP] A-Life client mode ENABLED
12. Watch NPCs — they should FREEZE (stop moving, stop fighting)
13. Wait 10 seconds
14. Type: alife():set_mp_client_mode(false)
15. Expected: * [GAMMA MP] A-Life client mode DISABLED
16. NPCs should RESUME normal behavior
```

If A-Life suppression works without crashing, Phase 0 core functionality is confirmed.

### Test 4: Stop and Cleanup
```
17. Type: mp_core.mp_stop_host()
18. Expected: [GAMMA MP] Stopped hosting
19. Type: mp_core.mp_shutdown()
20. Expected: [GAMMA MP] Shutdown complete
```

## Post-Test Log Analysis

After the user runs the tests and exits the game, check the log:

```powershell
# Find the most recent log file
$logPaths = @(
    "$ANOMALY\appdata\logs",
    "$ANOMALY\logs",
    "$env:LOCALAPPDATA\STALKER-Anomaly\logs",
    "$env:APPDATA\STALKER-Anomaly\logs"
)

$logFile = $null
foreach ($lp in $logPaths) {
    if (Test-Path $lp) {
        $logFile = Get-ChildItem -Path $lp -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($logFile) { break }
    }
}

if ($logFile) {
    Write-Host "Latest log: $($logFile.FullName)"
    Write-Host "Modified: $($logFile.LastWriteTime)"
    Write-Host ""
    
    # Extract GAMMA MP lines
    $mpLines = Get-Content $logFile.FullName | Select-String -Pattern "GAMMA MP|gns_bridge|gns\.init|mp_core"
    if ($mpLines) {
        Write-Host "=== GAMMA MP Log Entries ==="
        foreach ($line in $mpLines) {
            Write-Host $line.Line
        }
    } else {
        Write-Host "No GAMMA MP entries found in log. Scripts may not have loaded."
    }
    
    # Check for errors/crashes
    $errors = Get-Content $logFile.FullName | Select-String -Pattern "FATAL|crash|SCRIPT ERROR|LUA error|stack trace"
    if ($errors) {
        Write-Host ""
        Write-Host "=== ERRORS FOUND ==="
        foreach ($e in $errors) {
            Write-Host $e.Line
        }
    }
} else {
    Write-Host "No log file found. Check paths manually."
}
```

## Common Failure Modes

| Symptom | Cause | Fix |
|---|---|---|
| `mp_core` is nil | Script not loaded by engine | Check script is in correct gamedata/scripts path, check MO2 overwrite |
| `gns` is nil | DLL not loaded | Check gns_bridge.dll + all 5 deps in bin/, check engine exe is MP build |
| Game crashes on mp_init() | DLL version mismatch | Rebuild gns_bridge.dll, ensure all DLLs from same build |
| `set_mp_client_mode` not found | Engine not patched | Engine exe is stock, not our build. Redeploy from _build output |
| NPCs don't freeze | A-Life suppression not working | Check log for the ENABLED message, ensure correct engine exe |
| Entity count is 0 | Registry not built | Host callbacks didn't register, check for errors in log |

## Report

Tell me:
1. Did mp_init() succeed? What was the output?
2. Did hosting work? How many entities tracked?
3. Did A-Life suppression work? Did NPCs freeze and resume?
4. Any errors in the log?
5. Any crashes?
