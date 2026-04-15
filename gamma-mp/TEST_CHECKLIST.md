# GAMMA MP Quick Test Checklist

Run after every code change + deploy.

## Pre-Flight
- [ ] `.\gamma-mp\deploy.ps1` ran clean (no errors)
- [ ] Launch GAMMA through MO2

## Basic Startup
- [ ] Game loads without crash
- [ ] Console shows `[GAMMA MP] Core module loaded`
- [ ] F10 opens MP menu
- [ ] ESC closes MP menu
- [ ] Menu shows version and "Idle — not connected" status

## Host Mode
- [ ] Click Host → status shows "Hosting on port 44140"
- [ ] Click Status → shows "0 clients, N entities tracked"
- [ ] Click Stop Host → status shows "Hosting stopped"

## Client Mode (requires second instance or second machine)
- [ ] Enter host IP, click Connect
- [ ] Status shows "Connecting to IP:44140..."
- [ ] On connection confirmed: "Connected — cleaning" → "syncing" → "active"
- [ ] Status shows entity count and ID mappings
- [ ] Click Disconnect → "Disconnected"

## Save Protection
- [ ] F5 (quicksave) shows "Save disabled" tip when connected as client
- [ ] Console `save` command blocked when connected

## Stability
- [ ] Game doesn't crash on disconnect
- [ ] Game doesn't crash on reconnect after disconnect
- [ ] Host can stop hosting cleanly
- [ ] Shutdown button cleans up everything (status shows "Shutdown complete")
- [ ] F10 still works after shutdown + re-init

## API Verification (run in console while hosting)
Test these engine APIs exist — if any error, file a bug:
```
lua: alife():kill_entity
lua: db.actor.force_set_position
lua: level.set_game_time
```

## Entity Sync Verification (two instances connected)
- [ ] Client's NPC count roughly matches host's tracked count
- [ ] NPCs on client are moving (position updates arriving)
- [ ] Killing an NPC on host → NPC dies on client
- [ ] NPC spawning on host → NPC appears on client
