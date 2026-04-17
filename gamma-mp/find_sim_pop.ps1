# Find and dump sim_pop.script lines 1290-1320
# Run: powershell -ExecutionPolicy Bypass -File find_sim_pop.ps1

$ErrorActionPreference = "SilentlyContinue"

$locations = @(
    "C:\ANOMALY\gamedata\scripts",
    "C:\GAMMA\overwrite\gamedata\scripts",
    "C:\GAMMA\mods"
)

# Also search .db extraction - MO2 might have unpacked it
$locations += Get-ChildItem "C:\GAMMA\mods" -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }

$found = $false
foreach ($loc in $locations) {
    $files = Get-ChildItem -Recurse $loc -Filter "sim_pop.script" -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        Write-Host "FOUND: $($f.FullName)" -ForegroundColor Green
        Write-Host "--- Lines 1285-1315 ---" -ForegroundColor Yellow
        $lines = Get-Content $f.FullName -ErrorAction SilentlyContinue
        if ($lines) {
            for ($i = 1284; $i -lt [math]::Min(1315, $lines.Count); $i++) {
                Write-Host ("{0,4}: {1}" -f ($i+1), $lines[$i])
            }
        }
        Write-Host ""
        $found = $true
    }
}

if (-not $found) {
    Write-Host "Not found in mods or scripts folders. Checking ALL of C:\ANOMALY and C:\GAMMA..." -ForegroundColor Yellow
    $allFiles = @()
    $allFiles += Get-ChildItem -Recurse "C:\ANOMALY" -Filter "sim_pop.script" -ErrorAction SilentlyContinue
    $allFiles += Get-ChildItem -Recurse "C:\GAMMA" -Filter "sim_pop.script" -ErrorAction SilentlyContinue

    if ($allFiles.Count -eq 0) {
        Write-Host "NOT FOUND ANYWHERE. It's inside a .db archive." -ForegroundColor Red
        Write-Host "Trying to extract from .db files..." -ForegroundColor Yellow

        # Check if the game has an unpacker
        $dbFiles = Get-ChildItem "C:\ANOMALY\gamedata" -Filter "*.db*" -ErrorAction SilentlyContinue
        if ($dbFiles) {
            Write-Host "Found .db archives in C:\ANOMALY\gamedata:" -ForegroundColor Cyan
            $dbFiles | ForEach-Object { Write-Host "  $($_.Name) ($([math]::Round($_.Length/1MB,1)) MB)" }
        }

        Write-Host ""
        Write-Host "The file is packed inside a .db archive. To extract:" -ForegroundColor Yellow
        Write-Host '  1. Open MO2, right panel -> "Data" tab' -ForegroundColor DarkGray
        Write-Host '  2. Navigate to scripts\sim_pop.script' -ForegroundColor DarkGray
        Write-Host '  3. Right-click -> "Open"' -ForegroundColor DarkGray
        Write-Host '  OR use the Anomaly DB unpacker tool' -ForegroundColor DarkGray
    } else {
        foreach ($f in $allFiles) {
            Write-Host "FOUND: $($f.FullName)" -ForegroundColor Green
            $lines = Get-Content $f.FullName -ErrorAction SilentlyContinue
            if ($lines) {
                Write-Host "--- Lines 1285-1315 ---" -ForegroundColor Yellow
                for ($i = 1284; $i -lt [math]::Min(1315, $lines.Count); $i++) {
                    Write-Host ("{0,4}: {1}" -f ($i+1), $lines[$i])
                }
            }
        }
    }
}

Write-Host ""
Write-Host "Press any key..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
