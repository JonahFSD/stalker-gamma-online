# Rebuild xrGame + Deploy — Claude Code Prompt

Paste everything below the line into Claude Code on Windows.

---

The SetBodyYaw engine patch has been applied to 3 files in xrGame (script_game_object.h, script_game_object3.cpp, script_game_object_script3.cpp). Only xrGame needs to rebuild — the other 30 projects haven't changed. Rebuild, deploy to my local game, and update the release repo so my friend can pull the new binaries.

## Step 1: Rebuild xrGame → AnomalyDX11.exe

```powershell
$msbuild = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
cd "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\xray-monolith"
& $msbuild engine-vs2022.sln /t:AnomalyDX11 /p:Configuration=Release /p:Platform=x64 /m
```

If `AnomalyDX11` isn't a valid target name, try `/t:Anomaly_DX11`. If that fails too, just do a full solution build — MSBuild skips up-to-date projects:
```powershell
& $msbuild engine-vs2022.sln /p:Configuration=Release /p:Platform=x64 /m
```

Verify the exe was rebuilt (timestamp should be within the last few minutes):
```powershell
$exe = Get-ChildItem -Recurse -Filter "AnomalyDX11.exe" "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\xray-monolith\_build"
Write-Host "Built: $($exe.FullName) — $($exe.LastWriteTime) — $([math]::Round($exe.Length / 1MB, 1)) MB"
```

## Step 2: Deploy to C:\ANOMALY\bin

GAMMA runs `AnomalyDX11AVX.exe` — our patched build goes into that slot.

```powershell
$src = (Get-ChildItem -Recurse -Filter "AnomalyDX11.exe" "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\xray-monolith\_build").FullName
$dest = "C:\ANOMALY\bin\AnomalyDX11AVX.exe"

# Backup current
if (Test-Path $dest) {
    Copy-Item $dest "$dest.bak" -Force
    Write-Host "Backed up existing exe"
}

Copy-Item $src $dest -Force
Write-Host "[OK] Deployed to $dest"

# Verify
$deployed = Get-Item $dest
Write-Host "Deployed: $($deployed.LastWriteTime) — $([math]::Round($deployed.Length / 1MB, 1)) MB"
```

## Step 3: Verify set_body_yaw binding exists

Quick sanity check — grep the built exe for the string:
```powershell
$bytes = [System.IO.File]::ReadAllBytes("C:\ANOMALY\bin\AnomalyDX11AVX.exe")
$text = [System.Text.Encoding]::ASCII.GetString($bytes)
if ($text.Contains("set_body_yaw")) {
    Write-Host "[OK] set_body_yaw binding found in exe"
} else {
    Write-Host "[FAIL] set_body_yaw NOT found — check build"
}
```

## Step 4: Update release repo

The release repo (`gamma-mp-release`) contains pre-built binaries that other players pull to play. Find it and figure out how it's structured, then update it with the new exe.

```powershell
# Find the release repo
$searchPaths = @(
    "C:\Users\jonah\Documents\GitHub\gamma-mp-release",
    "C:\Users\jonah\Documents\GitHub\stalker-gamma-online-release",
    "C:\Users\jonah\Documents\GitHub\gamma-mp-release"
)

$releaseRepo = $null
foreach ($p in $searchPaths) {
    if (Test-Path $p) { $releaseRepo = $p; break }
}

# If not found at known paths, search GitHub folder
if (-not $releaseRepo) {
    $found = Get-ChildItem "C:\Users\jonah\Documents\GitHub" -Directory | Where-Object { $_.Name -match "release|gamma-mp-rel" } | Select-Object -First 1
    if ($found) { $releaseRepo = $found.FullName }
}

if (-not $releaseRepo) {
    Write-Host "[FAIL] Cannot find release repo. List what's in the GitHub folder:"
    Get-ChildItem "C:\Users\jonah\Documents\GitHub" -Directory | ForEach-Object { Write-Host "  $_" }
    Write-Host "Tell Jonah you couldn't find it and ask which one it is."
    exit
}

Write-Host "Found release repo at: $releaseRepo"
```

Now figure out the structure — is it raw files, a zip, or something else?

```powershell
Write-Host "`nRelease repo structure:"
Get-ChildItem $releaseRepo -Recurse -Depth 2 | ForEach-Object {
    $rel = $_.FullName.Replace($releaseRepo, "").TrimStart("\")
    if ($_.PSIsContainer) { Write-Host "  [DIR] $rel" } else { 
        $sizeMB = [math]::Round($_.Length / 1MB, 2)
        Write-Host "  $rel ($sizeMB MB)" 
    }
}
```

Based on what you find:

**If binaries are loose files** (e.g. `bin/AnomalyDX11AVX.exe` or similar):
- Copy the new exe to the matching location
- `git add` the file, commit, push

**If binaries are in a zip/7z archive** (e.g. `gamma-mp.zip`, `binaries.zip`):
- Extract the existing archive to a temp folder
- Replace the exe inside with the new one
- Re-archive with the same name and compression format
- For .zip: `Compress-Archive -Path "$tempDir\*" -DestinationPath "$archivePath" -Force`
- For .7z: use 7z.exe if available, otherwise fall back to zip
- `git add` the archive, commit, push

**If there's an installer script** (e.g. `install.ps1`, `setup.ps1`):
- The exe still needs to be updated wherever it lives in the repo
- Don't modify the installer script unless the filename changed (it didn't)

Commit message: `engine: add set_body_yaw binding for Phase 1 puppet heading sync`

```powershell
cd $releaseRepo
git add -A
git status
git commit -m "engine: add set_body_yaw binding for Phase 1 puppet heading sync"
git push
Write-Host "[OK] Release repo updated and pushed"
```

## Summary

After all steps complete, report:
1. Did xrGame rebuild cleanly? Any warnings?
2. Is `set_body_yaw` confirmed in the binary?
3. What was the release repo structure and how did you update it?
4. Did the push succeed?

Phase 0 is completely unaffected — set_body_yaw is a new function that nothing calls yet. It's inert until Phase 1 puppet Lua code uses it.
