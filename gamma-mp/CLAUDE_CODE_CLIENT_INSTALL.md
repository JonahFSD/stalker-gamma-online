# Claude Code Prompt: Install GAMMA MP (Client — No Build Required)

## Context

You're installing GAMMA Multiplayer on a machine that already has STALKER Anomaly + GAMMA installed. You do NOT need to build anything — the host has already compiled the engine and DLLs. You just need to download the pre-built files from the GitHub release and copy them to the right places.

## Prerequisites

- STALKER Anomaly 1.5.3 installed (find it — likely `C:\ANOMALY` or similar)
- GAMMA modpack installed via MO2 (find it — likely `C:\GAMMA` or similar)
- Git installed

## Step 1: Find Install Paths

Find where Anomaly and GAMMA are installed. Check these common locations:

```powershell
# Common Anomaly locations
$anomalyPaths = @("C:\ANOMALY", "D:\ANOMALY", "C:\Games\ANOMALY", "D:\Games\ANOMALY", "C:\Stalker Anomaly", "D:\Stalker Anomaly")
foreach ($p in $anomalyPaths) {
    if (Test-Path "$p\bin\AnomalyDX11.exe") { Write-Host "Found Anomaly: $p"; break }
}

# Common GAMMA locations
$gammaPaths = @("C:\GAMMA", "D:\GAMMA", "C:\Games\GAMMA", "D:\Games\GAMMA")
foreach ($p in $gammaPaths) {
    if (Test-Path "$p\overwrite") { Write-Host "Found GAMMA: $p"; break }
}
```

If not found, ask the user where they installed them. Store the paths:

```powershell
$ANOMALY = "C:\ANOMALY"   # adjust to actual
$GAMMA = "C:\GAMMA"       # adjust to actual
```

Verify both exist before continuing.

## Step 2: Clone the Repo

```powershell
cd $env:USERPROFILE\Documents
git clone https://github.com/JonahFSD/stalker-gamma-online.git
cd stalker-gamma-online
```

## Step 3: Download Pre-Built Files

Download the pre-built engine and DLLs from the GitHub release. These are the compiled binaries — no build needed.

```powershell
# Create a temp directory for downloads
$tempDir = "$env:TEMP\gamma-mp-install"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

# Download the release zip
$releaseUrl = "https://github.com/JonahFSD/stalker-gamma-online/releases/latest/download/gamma-mp-binaries.zip"
Invoke-WebRequest -Uri $releaseUrl -OutFile "$tempDir\gamma-mp-binaries.zip"

# Extract
Expand-Archive -Path "$tempDir\gamma-mp-binaries.zip" -DestinationPath "$tempDir\binaries" -Force
```

**If there is no GitHub release yet**, tell the user:

> The pre-built binaries aren't published as a GitHub release yet. Ask the host (Jonah) to send you these files:
>
> From `C:\ANOMALY\bin\` on the host machine:
> - `AnomalyDX11.exe` (the patched engine — ~24 MB)
> - `gns_bridge.dll`
> - `GameNetworkingSockets.dll`
> - `abseil_dll.dll`
> - `libcrypto-3-x64.dll`
> - `libprotobuf.dll`
>
> Put them all in a folder and tell me where they are.

Store the path to the binaries folder:

```powershell
$binaries = "$tempDir\binaries"  # or wherever the user put them
```

## Step 4: Deploy Engine Files

```powershell
$bin = "$ANOMALY\bin"

# Back up the stock AVX exe first
if (Test-Path "$bin\AnomalyDX11AVX.exe") {
    if (!(Test-Path "$bin\AnomalyDX11AVX_stock.exe")) {
        Copy-Item "$bin\AnomalyDX11AVX.exe" "$bin\AnomalyDX11AVX_stock.exe" -Force
        Write-Host "[OK] Backed up stock AnomalyDX11AVX.exe" -ForegroundColor Green
    } else {
        Write-Host "[OK] Stock backup already exists" -ForegroundColor Green
    }
}

# Copy patched exe into AVX slot (GAMMA defaults to launching AVX)
$exeSource = Get-ChildItem -Path $binaries -Filter "AnomalyDX11.exe" -Recurse | Select-Object -First 1
if ($exeSource) {
    Copy-Item $exeSource.FullName "$bin\AnomalyDX11AVX.exe" -Force
    Write-Host "[OK] Patched exe -> AnomalyDX11AVX.exe" -ForegroundColor Green
} else {
    Write-Host "[ERROR] AnomalyDX11.exe not found in binaries folder" -ForegroundColor Red
}

# Copy DLLs
$dlls = @("gns_bridge.dll", "GameNetworkingSockets.dll", "abseil_dll.dll", "libcrypto-3-x64.dll", "libprotobuf.dll")
foreach ($dll in $dlls) {
    $dllSource = Get-ChildItem -Path $binaries -Filter $dll -Recurse | Select-Object -First 1
    if ($dllSource) {
        Copy-Item $dllSource.FullName "$bin\$dll" -Force
        Write-Host "[OK] $dll" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] $dll not found in binaries folder" -ForegroundColor Red
    }
}
```

## Step 5: Deploy Lua Scripts + UI

```powershell
$repoRoot = "$env:USERPROFILE\Documents\stalker-gamma-online"
$gammaScripts = "$GAMMA\overwrite\gamedata\scripts"
$gammaUI = "$GAMMA\overwrite\gamedata\configs\ui"

# Create dirs if needed
New-Item -ItemType Directory -Force -Path $gammaScripts | Out-Null
New-Item -ItemType Directory -Force -Path $gammaUI | Out-Null

# Copy scripts from repo (these are always up to date in the repo)
$scripts = @("mp_core.script", "mp_protocol.script", "mp_host_events.script", "mp_client_state.script", "mp_alife_guard.script", "mp_ui.script")
foreach ($s in $scripts) {
    $src = "$repoRoot\gamma-mp\lua-sync\$s"
    if (Test-Path $src) {
        Copy-Item $src "$gammaScripts\$s" -Force
        Write-Host "[OK] $s" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] $s not found in repo" -ForegroundColor Red
    }
}

# Copy UI XML
$xmlSrc = "$repoRoot\gamma-mp\lua-sync\ui\ui_mp_menu.xml"
if (Test-Path $xmlSrc) {
    Copy-Item $xmlSrc "$gammaUI\ui_mp_menu.xml" -Force
    Write-Host "[OK] ui_mp_menu.xml" -ForegroundColor Green
} else {
    Write-Host "[ERROR] ui_mp_menu.xml not found in repo" -ForegroundColor Red
}
```

## Step 6: Verify

```powershell
Write-Host "`n=== Verification ===" -ForegroundColor Cyan

# Check exe
$exe = "$ANOMALY\bin\AnomalyDX11AVX.exe"
if (Test-Path $exe) {
    $size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
    Write-Host "[OK] AnomalyDX11AVX.exe ($size MB)" -ForegroundColor Green
} else {
    Write-Host "[FAIL] AnomalyDX11AVX.exe missing" -ForegroundColor Red
}

# Check DLLs
foreach ($dll in $dlls) {
    if (Test-Path "$ANOMALY\bin\$dll") {
        Write-Host "[OK] $dll" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $dll missing" -ForegroundColor Red
    }
}

# Check scripts
foreach ($s in $scripts) {
    if (Test-Path "$gammaScripts\$s") {
        Write-Host "[OK] $s" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $s missing" -ForegroundColor Red
    }
}

# Check UI
if (Test-Path "$gammaUI\ui_mp_menu.xml") {
    Write-Host "[OK] ui_mp_menu.xml" -ForegroundColor Green
} else {
    Write-Host "[FAIL] ui_mp_menu.xml missing" -ForegroundColor Red
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
Write-Host "Launch GAMMA through MO2 (use the AVX launcher)."
Write-Host "Press F10 in-game to open the MP menu."
Write-Host "Enter the host's IP address, click Connect."
```

## What NOT To Do

- Do NOT build the engine or DLLs — use the pre-built ones
- Do NOT modify any .script files
- Do NOT change MO2 settings — just use the default AVX launcher
- Do NOT open port 44140 — only the HOST needs that

## Reverting to Stock

```powershell
Copy-Item "$ANOMALY\bin\AnomalyDX11AVX_stock.exe" "$ANOMALY\bin\AnomalyDX11AVX.exe" -Force
Remove-Item "$GAMMA\overwrite\gamedata\scripts\mp_*.script" -Force
Remove-Item "$GAMMA\overwrite\gamedata\configs\ui\ui_mp_menu.xml" -Force
Write-Host "Reverted to stock GAMMA. Restart the game."
```
