@echo off
setlocal
cd /d "%~dp0"
set LUA=lua51\lua.exe

echo === GAMMA MP Test Suite ===
echo.

set PASS=0
set FAIL=0

for %%F in (test_sanity.lua test_loader.lua test_protocol.lua test_alife_guard.lua test_host_events.lua test_client_state.lua test_puppet.lua test_integration.lua) do (
    if exist %%F (
        echo --- Running %%F ---
        "%LUA%" %%F
        if errorlevel 1 (
            echo [FAIL] %%F
            set /a FAIL+=1
        ) else (
            echo [PASS] %%F
            set /a PASS+=1
        )
        echo.
    )
)

echo ===========================
echo Test files passed: %PASS%
echo Test files failed: %FAIL%
if %FAIL% GTR 0 (
    echo OVERALL: FAIL
    exit /b 1
) else (
    echo OVERALL: PASS
    exit /b 0
)
