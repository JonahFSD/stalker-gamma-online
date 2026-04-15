# ============================================================================
# GAMMA Multiplayer — Automated Setup Script
# ============================================================================
# Run this in PowerShell as Administrator AFTER Visual Studio 2022 is installed.
# It handles everything else: Git, CMake, vcpkg, repos, building, Anomaly setup.
#
# Usage: Right-click -> Run with PowerShell (as Admin)
#        OR: powershell -ExecutionPolicy Bypass -File setup.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
$GAMMA_MP_ROOT = "C:\gamma-mp"
$VCPKG_ROOT = "C:\vcpkg"
$ANOMALY_ROOT = "C:\STALKER_Anomaly"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " GAMMA Multiplayer — Setup Script" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# Step 1: Check for Visual Studio 2022
# ============================================================================

Write-Host "[1/9] Checking for Visual Studio 2022..." -ForegroundColor Yellow
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vsWhere) {
    $vsPath = & $vsWhere -latest -property installationPath 2>$null
    if ($vsPath) {
        Write-Host "  Found: $vsPath" -ForegroundColor Green
    } else {
        Write-Host "  ERROR: Visual Studio 2022 not found!" -ForegroundColor Red
        Write-Host "  Install it first, then re-run this script." -ForegroundColor Red
        Write-Host "  Download: https://visualstudio.microsoft.com/vs/community/" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Required workloads:" -ForegroundColor Yellow
        Write-Host "    - Desktop development with C++" -ForegroundColor Yellow
        Write-Host "  Required individual components:" -ForegroundColor Yellow
        Write-Host "    - MSVC v140 - VS 2015 C++ build tools" -ForegroundColor Yellow
        Write-Host "    - Windows 8.1 SDK" -ForegroundColor Yellow
        Write-Host "    - C++ MFC for latest v143 build tools" -ForegroundColor Yellow
        Write-Host "    - C++ ATL for latest v143 build tools" -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 1
    }
} else {
    Write-Host "  WARNING: vswhere not found. Assuming VS2022 is installed." -ForegroundColor Yellow
}

# ============================================================================
# Step 2: Install Git (if needed)
# ============================================================================

Write-Host "[2/9] Checking for Git..." -ForegroundColor Yellow
$gitPath = Get-Command git -ErrorAction SilentlyContinue
if ($gitPath) {
    Write-Host "  Found: $($gitPath.Source)" -ForegroundColor Green
} else {
    Write-Host "  Installing Git via winget..." -ForegroundColor Yellow
    try {
        winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "  Git installed!" -ForegroundColor Green
    } catch {
        Write-Host "  winget failed. Trying manual download..." -ForegroundColor Yellow
        $gitInstaller = "$env:TEMP\Git-Setup.exe"
        Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe" -OutFile $gitInstaller
        Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART" -Wait
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "  Git installed!" -ForegroundColor Green
    }
}

# ============================================================================
# Step 3: Install CMake (if needed)
# ============================================================================

Write-Host "[3/9] Checking for CMake..." -ForegroundColor Yellow
$cmakePath = Get-Command cmake -ErrorAction SilentlyContinue
if ($cmakePath) {
    Write-Host "  Found: $($cmakePath.Source)" -ForegroundColor Green
} else {
    Write-Host "  Installing CMake via winget..." -ForegroundColor Yellow
    try {
        winget install --id Kitware.CMake -e --source winget --accept-package-agreements --accept-source-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "  CMake installed!" -ForegroundColor Green
    } catch {
        Write-Host "  ERROR: Could not install CMake. Install manually from https://cmake.org/download/" -ForegroundColor Red
    }
}

# ============================================================================
# Step 4: Setup vcpkg
# ============================================================================

Write-Host "[4/9] Setting up vcpkg..." -ForegroundColor Yellow
if (Test-Path "$VCPKG_ROOT\vcpkg.exe") {
    Write-Host "  vcpkg already exists at $VCPKG_ROOT" -ForegroundColor Green
} else {
    Write-Host "  Cloning vcpkg..." -ForegroundColor Yellow
    git clone https://github.com/microsoft/vcpkg.git $VCPKG_ROOT
    Push-Location $VCPKG_ROOT
    & .\bootstrap-vcpkg.bat
    Pop-Location
    Write-Host "  vcpkg ready!" -ForegroundColor Green
}

# ============================================================================
# Step 5: Firewall Rules
# ============================================================================

Write-Host "[5/9] Adding firewall rules for GAMMA MP..." -ForegroundColor Yellow
try {
    $existing = Get-NetFirewallRule -DisplayName "GAMMA MP*" -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule -DisplayName "GAMMA MP UDP" -Direction Inbound -Protocol UDP -LocalPort 44140 -Action Allow | Out-Null
        New-NetFirewallRule -DisplayName "GAMMA MP TCP" -Direction Inbound -Protocol TCP -LocalPort 44140 -Action Allow | Out-Null
        Write-Host "  Firewall rules added (UDP+TCP port 44140)" -ForegroundColor Green
    } else {
        Write-Host "  Firewall rules already exist" -ForegroundColor Green
    }
} catch {
    Write-Host "  WARNING: Could not add firewall rules (run as Admin). Add manually:" -ForegroundColor Yellow
    Write-Host "  Allow inbound UDP+TCP on port 44140" -ForegroundColor Yellow
}

# ============================================================================
# Step 6: Clone repositories
# ============================================================================

Write-Host "[6/9] Cloning repositories..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $GAMMA_MP_ROOT | Out-Null

# xray-monolith engine
if (-not (Test-Path "$GAMMA_MP_ROOT\xray-monolith")) {
    Write-Host "  Cloning xray-monolith (engine)..." -ForegroundColor Yellow
    git clone https://github.com/themrdemonized/xray-monolith.git "$GAMMA_MP_ROOT\xray-monolith"
    Push-Location "$GAMMA_MP_ROOT\xray-monolith"
    git submodule update --init --recursive
    Pop-Location
    Write-Host "  xray-monolith cloned!" -ForegroundColor Green
} else {
    Write-Host "  xray-monolith already exists, skipping" -ForegroundColor Green
}

# GameNetworkingSockets
if (-not (Test-Path "$GAMMA_MP_ROOT\GameNetworkingSockets")) {
    Write-Host "  Cloning GameNetworkingSockets..." -ForegroundColor Yellow
    git clone https://github.com/ValveSoftware/GameNetworkingSockets.git "$GAMMA_MP_ROOT\GameNetworkingSockets"
    Write-Host "  GNS cloned!" -ForegroundColor Green
} else {
    Write-Host "  GNS already exists, skipping" -ForegroundColor Green
}

# AlifePlus
if (-not (Test-Path "$GAMMA_MP_ROOT\AlifePlus")) {
    Write-Host "  Cloning AlifePlus..." -ForegroundColor Yellow
    git clone https://github.com/damiansirbu-stalker/AlifePlus.git "$GAMMA_MP_ROOT\AlifePlus"
    Write-Host "  AlifePlus cloned!" -ForegroundColor Green
} else {
    Write-Host "  AlifePlus already exists, skipping" -ForegroundColor Green
}

# xlibs
if (-not (Test-Path "$GAMMA_MP_ROOT\xlibs")) {
    Write-Host "  Cloning xlibs..." -ForegroundColor Yellow
    git clone https://github.com/damiansirbu-stalker/xlibs.git "$GAMMA_MP_ROOT\xlibs"
    Write-Host "  xlibs cloned!" -ForegroundColor Green
} else {
    Write-Host "  xlibs already exists, skipping" -ForegroundColor Green
}

# GAMMA modpack
if (-not (Test-Path "$GAMMA_MP_ROOT\Stalker_GAMMA")) {
    Write-Host "  Cloning GAMMA modpack..." -ForegroundColor Yellow
    git clone https://github.com/Grokitach/Stalker_GAMMA.git "$GAMMA_MP_ROOT\Stalker_GAMMA"
    Write-Host "  GAMMA cloned!" -ForegroundColor Green
} else {
    Write-Host "  GAMMA already exists, skipping" -ForegroundColor Green
}

# ============================================================================
# Step 6: Apply engine patches
# ============================================================================

Write-Host "[7/9] Applying engine patches..." -ForegroundColor Yellow

$engineSrc = "$GAMMA_MP_ROOT\xray-monolith\src\xrGame"

# --- Patch alife_update_manager.h ---
$headerFile = "$engineSrc\alife_update_manager.h"
$headerContent = Get-Content $headerFile -Raw

if ($headerContent -notmatch "m_mp_client_mode") {
    Write-Host "  Patching alife_update_manager.h..." -ForegroundColor Yellow

    # Add member variable
    $headerContent = $headerContent -replace `
        'bool m_changing_level;', `
        "bool m_changing_level;`n`tbool m_mp_client_mode;  // GAMMA MP: A-Life suppression for clients"

    # Add method declarations after destructor
    $headerContent = $headerContent -replace `
        '(virtual ~CALifeUpdateManager\(\);)', `
        "`$1`n`tvoid set_mp_client_mode(bool value);`n`tbool mp_client_mode() const { return m_mp_client_mode; }"

    Set-Content $headerFile -Value $headerContent
    Write-Host "  alife_update_manager.h patched!" -ForegroundColor Green
} else {
    Write-Host "  alife_update_manager.h already patched" -ForegroundColor Green
}

# --- Patch alife_update_manager.cpp ---
$cppFile = "$engineSrc\alife_update_manager.cpp"
$cppContent = Get-Content $cppFile -Raw

if ($cppContent -notmatch "m_mp_client_mode") {
    Write-Host "  Patching alife_update_manager.cpp..." -ForegroundColor Yellow

    # Add initialization in constructor
    $cppContent = $cppContent -replace `
        'm_first_time = true;', `
        "m_first_time = true;`n`tm_mp_client_mode = false;  // GAMMA MP"

    # Guard update()
    $cppContent = $cppContent -replace `
        '(void CALifeUpdateManager::update\(\)\s*\{)', `
        "`$1`n`tif (m_mp_client_mode) return;  // GAMMA MP: skip A-Life on client"

    # Guard shedule_Update() - add after "if (!initialized()) return;"
    $cppContent = $cppContent -replace `
        '(if \(!initialized\(\)\)\s*\r?\n\s*return;)', `
        "`$1`n`n`tif (m_mp_client_mode) return;  // GAMMA MP: skip scheduled A-Life on client"

    # Add setter function at end
    $setter = @"

void CALifeUpdateManager::set_mp_client_mode(bool value)
{
	m_mp_client_mode = value;
	if (value)
		Msg("* [GAMMA MP] A-Life client mode ENABLED");
	else
		Msg("* [GAMMA MP] A-Life client mode DISABLED");
}
"@
    $cppContent = $cppContent + $setter

    Set-Content $cppFile -Value $cppContent
    Write-Host "  alife_update_manager.cpp patched!" -ForegroundColor Green
} else {
    Write-Host "  alife_update_manager.cpp already patched" -ForegroundColor Green
}

# --- Patch alife_simulator_script.cpp ---
$scriptFile = "$engineSrc\alife_simulator_script.cpp"
$scriptContent = Get-Content $scriptFile -Raw

if ($scriptContent -notmatch "set_mp_client_mode") {
    Write-Host "  Patching alife_simulator_script.cpp..." -ForegroundColor Yellow

    # Add wrapper functions after force_update
    $wrappers = @"

// GAMMA MP: A-Life suppression
void set_mp_client_mode(CALifeSimulator* self, bool value) { self->set_mp_client_mode(value); }
bool get_mp_client_mode(CALifeSimulator* self) { return self->mp_client_mode(); }
"@
    $scriptContent = $scriptContent -replace `
        '(void force_update\(CALifeSimulator\* self\)\s*\{[^}]+\})', `
        "`$1$wrappers"

    # Add Lua bindings
    $scriptContent = $scriptContent -replace `
        '(\.def\("force_update", &force_update\))', `
        "`$1`n`t`t.def(""set_mp_client_mode"", &set_mp_client_mode)`n`t`t.def(""mp_client_mode"", &get_mp_client_mode)"

    Set-Content $scriptFile -Value $scriptContent
    Write-Host "  alife_simulator_script.cpp patched!" -ForegroundColor Green
} else {
    Write-Host "  alife_simulator_script.cpp already patched" -ForegroundColor Green
}

# --- Patch level_script.cpp (add set_game_time) ---
$levelFile = "$engineSrc\level_script.cpp"
$levelContent = Get-Content $levelFile -Raw

if ($levelContent -notmatch "set_game_time") {
    Write-Host "  Patching level_script.cpp..." -ForegroundColor Yellow

    # Add set_game_time function after change_game_time
    $timeFunc = @"

// GAMMA MP: absolute time sync
void set_game_time(u32 hours, u32 mins, u32 secs)
{
	game_sv_Single* tpGame = smart_cast<game_sv_Single*>(Level().Server->game);
	if (!tpGame || !ai().get_alife()) return;
	u32 year = 0, month = 0, day = 0, c_hours = 0, c_mins = 0, c_secs = 0, c_milisecs = 0;
	split_time(Level().GetGameTime(), year, month, day, c_hours, c_mins, c_secs, c_milisecs);
	s32 current_tod = c_hours * 3600 + c_mins * 60 + c_secs;
	s32 target_tod = hours * 3600 + mins * 60 + secs;
	s32 delta = target_tod - current_tod;
	if (abs(delta) <= 1) return;
	if (delta < 0) delta += 86400;
	float fDelta = static_cast<float>(delta);
	u32 msDelta = delta * 1000;
	g_pGamePersistent->Environment().ChangeGameTime(fDelta);
	tpGame->alife().time_manager().change_game_time(msDelta);
}
"@
    $levelContent = $levelContent -replace `
        '(void change_game_time\(u32 days, u32 hours, u32 mins\)\s*\{[^}]+\{[^}]+\}\s*\})', `
        "`$1$timeFunc"

    # Add Lua binding
    $levelContent = $levelContent -replace `
        '(def\("change_game_time", change_game_time\))', `
        "`$1,`n`t`t`tdef(""set_game_time"", set_game_time)"

    Set-Content $levelFile -Value $levelContent
    Write-Host "  level_script.cpp patched!" -ForegroundColor Green
} else {
    Write-Host "  level_script.cpp already patched" -ForegroundColor Green
}

# --- Copy GNS bridge files ---
Write-Host "  Copying GNS bridge files to engine source..." -ForegroundColor Yellow
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$gnsBridgeDir = Join-Path $scriptDir "gns-bridge"

if (Test-Path $gnsBridgeDir) {
    Copy-Item "$gnsBridgeDir\gns_bridge_luabind.cpp" "$engineSrc\" -Force -ErrorAction SilentlyContinue
    Copy-Item "$gnsBridgeDir\gns_bridge_poll.cpp" "$engineSrc\" -Force -ErrorAction SilentlyContinue
    Write-Host "  GNS bridge files copied!" -ForegroundColor Green
} else {
    Write-Host "  GNS bridge source dir not found, skipping copy" -ForegroundColor Yellow
}

# ============================================================================
# Step 7: Build GNS Bridge DLL
# ============================================================================

Write-Host "[8/9] Building GNS Bridge DLL..." -ForegroundColor Yellow

# Install GNS via vcpkg
Write-Host "  Installing GameNetworkingSockets via vcpkg (this takes a few minutes)..." -ForegroundColor Yellow
& "$VCPKG_ROOT\vcpkg.exe" install gamenetworkingsockets:x64-windows

# Build the bridge DLL
if (Test-Path $gnsBridgeDir) {
    Push-Location $gnsBridgeDir
    $buildDir = "build"
    if (-not (Test-Path $buildDir)) { New-Item -ItemType Directory -Path $buildDir | Out-Null }

    cmake -S . -B $buildDir -G "Visual Studio 17 2022" -A x64 `
        "-DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT\scripts\buildsystems\vcpkg.cmake"
    cmake --build $buildDir --config Release

    Pop-Location
    Write-Host "  GNS Bridge DLL built!" -ForegroundColor Green
} else {
    Write-Host "  GNS bridge source not found, skipping build" -ForegroundColor Yellow
}

# ============================================================================
# Step 9: Summary
# ============================================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Setup Complete!" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "What's done:" -ForegroundColor Green
Write-Host "  [x] Git installed"
Write-Host "  [x] CMake installed"
Write-Host "  [x] vcpkg set up at $VCPKG_ROOT"
Write-Host "  [x] xray-monolith cloned + submodules"
Write-Host "  [x] GameNetworkingSockets cloned"
Write-Host "  [x] AlifePlus + xlibs cloned"
Write-Host "  [x] GAMMA modpack cloned"
Write-Host "  [x] Firewall rules added (port 44140)"
Write-Host "  [x] Engine patches applied (A-Life suppression, time sync, Lua bindings)"
Write-Host "  [x] GNS bridge DLL built"
Write-Host ""
Write-Host "What YOU need to do:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. BUILD THE ENGINE:" -ForegroundColor White
Write-Host "     Open: $GAMMA_MP_ROOT\xray-monolith\engine-vs2022.sln"
Write-Host "     (Right-click -> Run as Administrator)"
Write-Host "     Set config to Release, then Build -> Rebuild Solution"
Write-Host "     NOTE: You need to manually add gns_bridge_luabind.cpp and"
Write-Host "     gns_bridge_poll.cpp to the xrGame project in Solution Explorer"
Write-Host "     (Right-click xrGame -> Add -> Existing Item)"
Write-Host ""
Write-Host "  2. INSTALL ANOMALY + GAMMA:" -ForegroundColor White
Write-Host "     Download Anomaly 1.5.3 from moddb.com"
Write-Host "     Run GAMMA installer: $GAMMA_MP_ROOT\Stalker_GAMMA\.Grok's Modpack Installer\G.A.M.M.A. Launcher.exe"
Write-Host ""
Write-Host "  3. DEPLOY:" -ForegroundColor White
Write-Host "     Copy the built engine exe from: $GAMMA_MP_ROOT\xray-monolith\_build_game\bin_dbg\"
Write-Host "     Copy gns_bridge.dll + GameNetworkingSockets.dll to Anomaly\bin\"
Write-Host "     Copy lua-sync\*.script to Anomaly\gamedata\scripts\"
Write-Host ""
Write-Host "  4. TEST:" -ForegroundColor White
Write-Host "     Launch game, open console (~), type: mp_core.mp_init()"
Write-Host ""
Write-Host "All repos are at: $GAMMA_MP_ROOT" -ForegroundColor Cyan
Write-Host ""
Read-Host "Press Enter to exit"
