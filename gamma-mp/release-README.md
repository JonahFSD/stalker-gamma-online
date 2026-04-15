# GAMMA Multiplayer

Co-op multiplayer for S.T.A.L.K.E.R. Anomaly GAMMA. Two players in the same Zone — the host runs the game normally, and the client sees the host's world (NPCs, mutants, squads, weather, time) in real time.

---

## Full Setup Guide (from zero)

If you already have Anomaly + GAMMA installed and working, skip to [Step 3](#step-3-download-this-repo).

### Step 1: Install S.T.A.L.K.E.R. Anomaly 1.5.3

Anomaly is a free standalone mod — you don't need to own any STALKER game.

1. Download Anomaly 1.5.3 from one of these:
   - **ModDB:** https://www.moddb.com/mods/stalker-anomaly/downloads/stalker-anomaly-153
   - **Torrent (faster):** https://tinyurl.com/StalkerAnomalyTorrent
2. Create a folder for it. **Do NOT use `C:\Program Files\`** — Windows permissions will break things. Use something like `C:\ANOMALY` or `D:\Games\ANOMALY`.
3. Extract the downloaded archive into that folder using [7-Zip](https://7-zip.org/) (WinRAR sometimes corrupts the extraction — use 7-Zip).
4. You should now have `AnomalyLauncher.exe` inside your folder.
5. **Run the game once:** Double-click `AnomalyLauncher.exe`, click **Play**, wait until you reach the main menu, then exit. This generates config files that GAMMA needs.

### Step 2: Install GAMMA

GAMMA is a 400+ mod modpack that overhauls everything. It has its own installer.

1. Download the GAMMA installer (RC3):
   - **Gofile:** https://gofile.io/d/Y8NnGS
   - **Mediafire:** https://www.mediafire.com/file_premium/xgldcs2qbzpcz20/GAMMA_RC3.7z/file
2. Create a folder for GAMMA. Again, not in Program Files. Something like `C:\GAMMA` or `D:\Games\GAMMA`.
3. Extract the GAMMA RC3 archive into your GAMMA folder using 7-Zip.
4. Open the `.Grok's Modpack Installer` folder inside your GAMMA folder.
5. Run **G.A.M.M.A. Launcher.exe** (it should say v8.3 or newer at the top).
6. Click **"First Install Initialization"** (you only do this once).
7. Mod Organizer 2 will pop up and ask you to select a game. **Navigate to your Anomaly folder** (the one with `AnomalyLauncher.exe` in it) and select it. Close the MO2 window after.
8. Back in the GAMMA Launcher, leave all settings on default and click **"Install / Update GAMMA"**.
9. Wait. It downloads 400+ mods. This takes a while depending on your internet. Go make coffee.
10. When the green launcher says **"Installation finished"**, click **Play** to open Mod Organizer 2.
11. In MO2, make sure the dropdown at the top-right says **"Anomaly (DX11-AVX)"** and click **Run**.
12. The game should launch. Get to the main menu, make sure it works, then close it.

You now have a working GAMMA install.

### Step 3: Download This Repo

You need [Git](https://git-scm.com/downloads) installed. If you don't have it, download and install it (all defaults are fine).

Open PowerShell (press Win+X → "Windows PowerShell" or "Terminal") and run:

```powershell
cd $env:USERPROFILE\Documents
git clone https://github.com/JonahFSD/gamma-mp-release.git
cd gamma-mp-release
```

Or just click the green **"Code"** button on this GitHub page → **"Download ZIP"**, and extract it somewhere.

### Step 4: Run the Installer

In the `gamma-mp-release` folder, right-click **`install.ps1`** → **"Run with PowerShell"**.

If that doesn't work (execution policy), open PowerShell, `cd` to the folder, and run:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

The installer will:
- Ask where Anomaly is installed (just press Enter if it's `C:\ANOMALY`)
- Ask where GAMMA is installed (just press Enter if it's `C:\GAMMA`)
- Back up your stock engine exe (so you can revert later)
- Copy the multiplayer engine + scripts into the right folders
- Print OK/FAIL for every file so you know it worked

### Step 5: Play

1. Launch GAMMA through Mod Organizer 2 like you normally would.
2. Load any save or start a new game.
3. Press **F10** to open the Multiplayer menu.
4. Type the **host's IP address** in the IP field.
5. Click **Connect**.
6. You should see "Connecting..." then "Connected" on screen. The host's world will start streaming in.

That's it. You're in the Zone together.

---

## Host Setup

If you're the one hosting (running the server), you need to open a port so your friend can connect to you.

### Open Port 44140

**Windows Firewall** (run PowerShell as Administrator):

```powershell
New-NetFirewallRule -DisplayName "GAMMA Multiplayer" -Direction Inbound -Protocol UDP -LocalPort 44140 -Action Allow
New-NetFirewallRule -DisplayName "GAMMA Multiplayer TCP" -Direction Inbound -Protocol TCP -LocalPort 44140 -Action Allow
```

**Router Port Forwarding:** You also need to forward port 44140 (UDP + TCP) on your router to your PC's local IP address. Google "port forward [your router model]" if you're not sure how. Your local IP is usually something like `192.168.1.x` — find it by running `ipconfig` in PowerShell and looking at "IPv4 Address" under your active adapter.

### Hosting a Game

1. Launch GAMMA through MO2, load your save.
2. Press **F10**, click **Host**.
3. Give your friend your **public IP** (Google "what is my IP").
4. Play normally — the mod watches what happens and broadcasts it.

---

## Uninstalling

Right-click **`uninstall.ps1`** → **"Run with PowerShell"**. This restores your original engine and removes all multiplayer files. Your saves, mods, and GAMMA install are untouched.

---

## Troubleshooting

**"install.ps1 won't run / red error about execution policy"**
→ Open PowerShell and run: `powershell -ExecutionPolicy Bypass -File install.ps1`

**Game crashes on startup after install**
→ Make sure you ran GAMMA at least once before installing MP. The installer backs up your engine exe — if something's wrong, run `uninstall.ps1` to revert.

**F10 doesn't open the MP menu**
→ The patched engine isn't running. Make sure MO2 is set to launch "Anomaly (DX11-AVX)" — that's the exe slot we replace.

**Can't connect to host**
→ Host: did you open port 44140? Check both Windows Firewall AND router port forwarding.
→ Try LAN first — use the host's local IP (192.168.x.x) to rule out router issues.

**"gns is nil" error in console**
→ The networking DLLs didn't copy correctly. Re-run `install.ps1`.
