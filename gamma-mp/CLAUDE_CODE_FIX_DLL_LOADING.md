# Fix GNS Bridge DLL Loading + Rebuild Engine — Claude Code Prompt

Paste everything below the line into Claude Code on Windows.

---

## Problem

`LoadLibraryA("gns_bridge.dll")` in `gns_bridge_luabind.cpp` uses a bare filename. When MO2 launches the game, the working directory is NOT `C:\ANOMALY\bin\` (where the DLLs live), so Windows can't find the DLL. Result: `gns` Lua namespace registers but `gns.init()` fails, causing `attempt to index global 'gns' (a nil value)` in mp_core.script.

## Fix Already Applied

The fix has already been applied to the source file. Verify it's there:

```
File: C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\xray-monolith\src\xrGame\gns_bridge_luabind.cpp
```

The `LoadGnsBridge()` function should now:
1. Call `GetModuleFileNameA(NULL, ...)` to get the exe's full path
2. Strip the exe filename to get the directory (e.g. `C:\ANOMALY\bin\`)
3. Append `gns_bridge.dll` to build the full path
4. Try `LoadLibraryA` with the full path first
5. Fall back to bare filename if that fails (for direct launches where cwd IS bin/)

**Verify** the function starts with this pattern:
```cpp
static bool LoadGnsBridge()
{
    if (g_hGnsDll)
        return true;

    // Build absolute path to gns_bridge.dll based on the running exe's directory.
    char exe_path[MAX_PATH] = {0};
    DWORD len = GetModuleFileNameA(NULL, exe_path, MAX_PATH);
    ...
```

If the fix is NOT present (still shows bare `LoadLibraryA("gns_bridge.dll")`), apply it manually using the pattern above.

## Rebuild

Only xrGame needs to rebuild (the changed file is in the xrGame project).

```powershell
$ENGINE = "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\xray-monolith"
$SLN = "$ENGINE\xray-16.sln"

# Find MSBuild
$msbuild = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe | Select-Object -First 1

if (-not $msbuild) {
    Write-Host "[FAIL] MSBuild not found"
    exit 1
}

Write-Host "MSBuild: $msbuild"
Write-Host "Rebuilding xrGame (Release|x64)..."

# Build just xrGame — it's the only project with changes
& $msbuild $SLN /t:xrGame /p:Configuration=Release /p:Platform=x64 /m /v:minimal

if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] xrGame build failed"
    exit 1
}

Write-Host "[OK] xrGame rebuilt"
```

If the targeted xrGame build fails (MSBuild can't resolve the target name), fall back to full solution rebuild:

```powershell
& $msbuild $SLN /p:Configuration=Release /p:Platform=x64 /m /v:minimal
```

## Redeploy Engine Exe

The build outputs go to `_build\_game\bin_dbg\`. Copy the new exe to `C:\ANOMALY\bin\`:

```powershell
$BUILD_BIN = "$ENGINE\_build\_game\bin_dbg"

# Find the built exe(s)
$exes = Get-ChildItem "$BUILD_BIN\Anomaly*.exe" -ErrorAction SilentlyContinue
foreach ($e in $exes) {
    $dest = "C:\ANOMALY\bin\$($e.Name)"
    Copy-Item $e.FullName $dest -Force
    $sizeMB = [math]::Round($e.Length / 1MB, 1)
    Write-Host "[OK] $($e.Name) ($sizeMB MB) -> C:\ANOMALY\bin\"
}

if (-not $exes) {
    Write-Host "[FAIL] No exe found in $BUILD_BIN"
    exit 1
}
```

## Verify

```powershell
Write-Host ""
Write-Host "========================================="
Write-Host " DLL Loading Fix Verification"
Write-Host "========================================="

# 1. Exe deployed
$dx11 = Get-Item "C:\ANOMALY\bin\AnomalyDX11.exe" -ErrorAction SilentlyContinue
if ($dx11) {
    $sizeMB = [math]::Round($dx11.Length / 1MB, 1)
    Write-Host "[OK] AnomalyDX11.exe ($sizeMB MB) — last modified: $($dx11.LastWriteTime)"
} else {
    Write-Host "[FAIL] AnomalyDX11.exe not found"
}

# 2. GNS DLLs still present
foreach ($dll in @("gns_bridge.dll", "GameNetworkingSockets.dll", "abseil_dll.dll", "libcrypto-3-x64.dll", "libprotobuf.dll")) {
    if (Test-Path "C:\ANOMALY\bin\$dll") {
        Write-Host "[OK] $dll"
    } else {
        Write-Host "[FAIL] $dll missing from C:\ANOMALY\bin\"
    }
}

# 3. Source file has the fix
$src = Get-Content "$ENGINE\src\xrGame\gns_bridge_luabind.cpp" -Raw
if ($src -match "GetModuleFileNameA") {
    Write-Host "[OK] gns_bridge_luabind.cpp has absolute path fix"
} else {
    Write-Host "[FAIL] Fix not present in source!"
}

Write-Host ""
Write-Host "Ready to test. Launch GAMMA through MO2, press F10 in-game."
Write-Host "Expected: 'GAMMA MP hosting on port 44140' tip on screen."
Write-Host "If gns_bridge.dll still fails, check the engine log for:"
Write-Host "  [GAMMA MP] Loaded gns_bridge.dll from: C:\ANOMALY\bin\gns_bridge.dll"
Write-Host "  — or —"
Write-Host "  [GAMMA MP] Failed to load gns_bridge.dll (tried exe dir + cwd)"
```

## Report

Tell me:
1. Did xrGame rebuild clean?
2. What's the exe size + timestamp?
3. Did all GNS DLLs verify?
4. Is the source fix confirmed?
