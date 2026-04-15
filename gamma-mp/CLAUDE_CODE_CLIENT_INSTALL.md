# Claude Code Prompt: Install GAMMA MP (Client)

## Context

You're installing GAMMA Multiplayer on a machine that already has STALKER Anomaly + GAMMA installed. Everything is pre-built — just clone and run the installer.

## Prerequisites

- STALKER Anomaly 1.5.3 installed
- GAMMA modpack installed via MO2
- Git installed

## Step 1: Clone the Release Repo

```powershell
cd $env:USERPROFILE\Documents
git clone https://github.com/JonahFSD/gamma-mp-release.git
cd gamma-mp-release
```

## Step 2: Run the Installer

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

The installer will:
- Ask where Anomaly and GAMMA are installed (defaults: `C:\ANOMALY`, `C:\GAMMA`)
- Back up the stock engine exe
- Copy the patched engine + networking DLLs to Anomaly
- Copy the Lua scripts + UI to GAMMA's MO2 overwrite folder
- Verify everything landed correctly

## Step 3: Play

1. Launch GAMMA through MO2 as normal
2. Press **F10** in-game to open the MP menu
3. Enter the host's IP address, click **Connect**

## What NOT To Do

- Do NOT build anything — everything is pre-built
- Do NOT modify any .script files
- Do NOT change MO2 settings — just use the default AVX launcher
- Do NOT open port 44140 — only the HOST needs that

## Reverting to Stock

Run `uninstall.ps1` from the release repo folder, or:

```powershell
cd $env:USERPROFILE\Documents\gamma-mp-release
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```
