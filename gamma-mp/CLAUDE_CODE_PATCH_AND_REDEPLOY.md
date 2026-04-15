# Patch GAMMA Mods + Redeploy MP Files — Claude Code Prompt

Paste everything below the line into Claude Code on Windows.

---

The mod audit found 25 CRITICAL conflicts. I've already fixed our own scripts (save blocker, ZCP source tag filtering, global helpers). Now I need you to:

1. Patch `_g.script` (the global wrapper file from Log spam remover) to block alife calls on the MP client — this single fix neutralizes ~50 mod conflicts
2. Redeploy all MP files to the correct GAMMA installation at `C:\GAMMA`

## Paths

```
$ANOMALY = "C:\ANOMALY"          # Base Anomaly install (engine exe + DLLs go here)
$GAMMA = "C:\GAMMA"              # GAMMA/MO2 install (scripts go into MO2 overwrite)
$GAMMA_MP = "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp"
$ENGINE_BUILD = "$GAMMA_MP\xray-monolith\_build\_game\bin_dbg"
$GNS_BUILD = "$GAMMA_MP\gns-bridge\build\bin\Release"
$LUA_SYNC = "$GAMMA_MP\lua-sync"
```

## Step 1: Find the MO2 overwrite folder in GAMMA

```powershell
$GAMMA = "C:\GAMMA"

# MO2 overwrite is where we put scripts so they layer on top of all mods
$overwrite = $null
$candidates = @(
    "$GAMMA\overwrite",
    "$GAMMA\ModOrganizer\overwrite",
    "$GAMMA\MO2\overwrite"
)
foreach ($c in $candidates) {
    if (Test-Path $c) { $overwrite = $c; break }
}

# If not found, search for it
if (-not $overwrite) {
    $found = Get-ChildItem -Path $GAMMA -Recurse -Depth 3 -Directory -Filter "overwrite" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $overwrite = $found.FullName }
}

# If still not found, look for MO2 portable structure
if (-not $overwrite) {
    $mo2 = Get-ChildItem -Path $GAMMA -Depth 1 -Filter "ModOrganizer.exe" -ErrorAction SilentlyContinue
    if ($mo2) {
        $overwrite = Join-Path $mo2.DirectoryName "overwrite"
        New-Item -ItemType Directory -Force -Path $overwrite | Out-Null
    }
}

if (-not $overwrite) {
    Write-Host "[FAIL] Cannot find MO2 overwrite folder in $GAMMA"
    Write-Host "List the GAMMA directory contents and find it manually."
    exit 1
}

$scriptDest = "$overwrite\gamedata\scripts"
New-Item -ItemType Directory -Force -Path $scriptDest | Out-Null
Write-Host "MO2 overwrite: $overwrite"
Write-Host "Scripts destination: $scriptDest"
```

## Step 2: Find and patch _g.script

The `_g.script` file from the "Log spam remover" mod defines global wrappers for `alife_create`, `alife_release`, `alife_release_id`, and `TeleportObject`. Almost every GAMMA mod calls these wrappers instead of calling `alife()` directly. By adding MP client guards inside these wrappers, we block ~50 mod conflicts in one place.

```powershell
# Find _g.script — it could be in the base Anomaly gamedata or in a mod folder
$gScript = $null

# Check MO2 mods folder first (higher priority in load order)
$modsDir = Get-ChildItem -Path $GAMMA -Depth 1 -Directory -Filter "mods" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($modsDir) {
    $gScript = Get-ChildItem -Path $modsDir.FullName -Recurse -Filter "_g.script" -ErrorAction SilentlyContinue | Select-Object -First 1
}

# Then check Anomaly base
if (-not $gScript) {
    $gScript = Get-ChildItem -Path "C:\ANOMALY\gamedata\scripts" -Filter "_g.script" -ErrorAction SilentlyContinue | Select-Object -First 1
}

# Then check overwrite
if (-not $gScript) {
    $gScript = Get-ChildItem -Path $overwrite -Recurse -Filter "_g.script" -ErrorAction SilentlyContinue | Select-Object -First 1
}

if ($gScript) {
    Write-Host "Found _g.script at: $($gScript.FullName)"
} else {
    Write-Host "[WARN] _g.script not found. Will create MP wrapper in overwrite."
}
```

Now read `_g.script` and find the `alife_create`, `alife_release`, `alife_release_id`, and `TeleportObject` functions. These are the global wrappers.

**For each wrapper function**, add this guard at the very top of the function body:

```lua
-- GAMMA MP: Block entity lifecycle calls on client (A-Life is suppressed)
if is_mp_client and is_mp_client() then
    printf("[GAMMA MP] %s blocked on client", "function_name_here")
    return nil
end
```

**IMPORTANT:** 
- The check is `if is_mp_client and is_mp_client() then` — the first `is_mp_client` (without parens) checks if the global function EXISTS (it won't exist if MP isn't loaded). The second `is_mp_client()` (with parens) actually calls it.
- `alife_create` should return `nil` (callers check for nil).
- `alife_release` and `alife_release_id` should just `return` (void).
- `TeleportObject` should just `return` (void).

If `_g.script` is in a mod folder (read-only for MO2), copy it to the overwrite folder first, then patch the copy:

```powershell
if ($gScript -and $gScript.FullName -notlike "*overwrite*") {
    $destGScript = "$scriptDest\_g.script"
    Copy-Item $gScript.FullName $destGScript -Force
    Write-Host "Copied _g.script to overwrite for patching"
    $gScript = Get-Item $destGScript
}
```

If `_g.script` doesn't define these wrapper functions (some versions don't), create a new file `mp_g_patches.script` in the overwrite scripts folder that overrides the globals:

```lua
--- mp_g_patches.script: MP client guards for global entity lifecycle wrappers
--- Loaded after _g.script via alphabetical order (mp_ > _g)

local _original_alife_create = alife_create
local _original_alife_release = alife_release
local _original_alife_release_id = alife_release_id
local _original_TeleportObject = TeleportObject

if _original_alife_create then
    alife_create = function(...)
        if is_mp_client and is_mp_client() then
            return nil
        end
        return _original_alife_create(...)
    end
end

if _original_alife_release then
    alife_release = function(...)
        if is_mp_client and is_mp_client() then
            return
        end
        return _original_alife_release(...)
    end
end

if _original_alife_release_id then
    alife_release_id = function(...)
        if is_mp_client and is_mp_client() then
            return
        end
        return _original_alife_release_id(...)
    end
end

if _original_TeleportObject then
    TeleportObject = function(...)
        if is_mp_client and is_mp_client() then
            return
        end
        return _original_TeleportObject(...)
    end
end
```

**Decision logic:** Read `_g.script`. If it defines `alife_create` etc as global functions, patch them in-place (in the overwrite copy). If it doesn't, create `mp_g_patches.script` as a separate file that wraps whatever globals exist at load time.

## Step 3: Redeploy Lua scripts to MO2 overwrite

```powershell
$LUA_SYNC = "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\lua-sync"

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
        Write-Host "[OK] $s -> $scriptDest"
    } else {
        Write-Host "[FAIL] $s not found at $src"
    }
}
```

## Step 4: Verify engine exe + DLLs are still in C:\ANOMALY

The DX11 build already deployed to `C:\ANOMALY\bin\`. Just verify nothing got overwritten:

```powershell
$binDir = "C:\ANOMALY\bin"

# Check engine exes
$exes = Get-ChildItem "$binDir\Anomaly*.exe" -ErrorAction SilentlyContinue
foreach ($e in $exes) {
    $sizeMB = [math]::Round($e.Length / 1MB, 1)
    Write-Host "[OK] $($e.Name) ($sizeMB MB)"
}

# Check GNS DLLs
foreach ($dll in @("gns_bridge.dll", "GameNetworkingSockets.dll", "abseil_dll.dll", "libcrypto-3-x64.dll", "libprotobuf.dll")) {
    if (Test-Path "$binDir\$dll") {
        Write-Host "[OK] $dll"
    } else {
        Write-Host "[MISSING] $dll — need to redeploy from gns-bridge build"
        $src = "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\gns-bridge\build\bin\Release\$dll"
        if (Test-Path $src) {
            Copy-Item $src "$binDir\" -Force
            Write-Host "[FIXED] $dll redeployed"
        }
    }
}
```

## Step 5: Final verification

```powershell
Write-Host ""
Write-Host "========================================="
Write-Host " GAMMA MP Patch + Redeploy Verification"
Write-Host "========================================="
Write-Host ""

$allGood = $true

# Engine exe in C:\ANOMALY\bin
$dx11 = Test-Path "C:\ANOMALY\bin\AnomalyDX11.exe"
$dx9 = Test-Path "C:\ANOMALY\bin\AnomalyDX9.exe"
if ($dx11) { Write-Host "[OK] AnomalyDX11.exe" }
elseif ($dx9) { Write-Host "[OK] AnomalyDX9.exe (DX11 not available)" }
else { Write-Host "[FAIL] No engine exe"; $allGood = $false }

# GNS DLLs
foreach ($dll in @("gns_bridge.dll", "GameNetworkingSockets.dll")) {
    if (Test-Path "C:\ANOMALY\bin\$dll") { Write-Host "[OK] $dll" }
    else { Write-Host "[FAIL] $dll"; $allGood = $false }
}

# MP scripts in MO2 overwrite
foreach ($s in @("mp_core.script", "mp_protocol.script", "mp_host_events.script", "mp_client_state.script")) {
    if (Test-Path "$scriptDest\$s") { Write-Host "[OK] $s (in MO2 overwrite)" }
    else { Write-Host "[FAIL] $s missing"; $allGood = $false }
}

# _g.script patch or mp_g_patches.script
if (Test-Path "$scriptDest\mp_g_patches.script") {
    Write-Host "[OK] mp_g_patches.script (global alife guards)"
} elseif (Test-Path "$scriptDest\_g.script") {
    Write-Host "[OK] _g.script (patched in overwrite)"
} else {
    Write-Host "[WARN] No global alife guard patch found"
}

Write-Host ""
if ($allGood) {
    Write-Host "ALL GOOD — Ready to test!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Launch GAMMA through MO2, open console (~), and run:"
    Write-Host "  mp_core.mp_init()"
    Write-Host "  mp_core.mp_host()"
    Write-Host "  mp_core.mp_status()"
    Write-Host "  alife():set_mp_client_mode(true)   -- NPCs should freeze"
    Write-Host "  alife():set_mp_client_mode(false)  -- NPCs should resume"
} else {
    Write-Host "ISSUES FOUND — check above" -ForegroundColor Red
}
```

## Report

Tell me:
1. Where was the MO2 overwrite folder?
2. Was `_g.script` found? Was it patched in-place or did you create `mp_g_patches.script`?
3. Did all 4 MP scripts deploy to overwrite?
4. Are engine exe + DLLs still in `C:\ANOMALY\bin`?
5. Any issues?
