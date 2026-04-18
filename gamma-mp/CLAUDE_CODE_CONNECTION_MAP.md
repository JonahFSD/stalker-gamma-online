# CLI Brief: Map the Client Connection Sequence and Identify Collision Classes

## Mission

Joe keeps crashing ~2-3 seconds after connecting to Jonah's MP host. Three crashes so far, three different failure modes. We've been playing whack-a-mole. Stop. Instead: **produce a definitive map of what actually happens on the client when a player connects to a host, catalog every class of state collision between the client's native alife and the host's broadcast stream, and recommend a filter/gate strategy that addresses the whole class rather than individual crash sites.**

This is a RESEARCH phase. Do NOT write code, do NOT edit files, do NOT commit anything. The deliverable is a single markdown document that lets Jonah pick a strategy with full information. Bar is perfection and correctness — time does not matter, thoroughness does.

## Project context you must absorb before dispatching subagents

- `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\.claude\CLAUDE.md` — top-level architecture, three-repo pattern, engine patches inventory
- `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\BUG_TRACKER.md` — existing bug history
- `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\lua-sync\` — the mp_*.script files (core, protocol, host_events, client_state, alife_guard, puppet, ui)
- `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\xray-monolith\src\` — engine source of truth, branch `mp-engine-baseline-2026-04-17`, HEAD `6f481655`. This is a clone with its own .git (gitignored from the parent repo)
- `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\engine-patch\` — numbered patches documenting engine changes (0008_ and 0009_ are the two soft-fail waves)
- `C:\Users\jonah\Documents\GitHub\gamma-mp-release\` — Joe's install channel, branch `master`, most recent commit `17c8a26` (ZCP smr_handle_spawn client gate)
- `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\Stalker_GAMMA\G.A.M.M.A\` — vanilla-extract of GAMMA mod files for reference (gitignored). ZCP 1.4 source lives here at `modpack_addons\G.A.M.M.A. ZCP 1.4 Balanced Spawns\gamedata\scripts\smr_pop.script`
- Joe's crash log: upload from Jonah's most recent prompt, referenced as `xray_twent (2).log`. Paste of the tail is below in the crash section — you have enough from the quotes but ask Jonah if you need the full file

What already exists:
- Engine patches applied: `m_mp_client_mode` bool gates `alife().update()` / `shedule_Update()`; soft-fail wrapping of `lua_error` / `lua_pcall_failed` / `lua_cast_failed` to log rather than fatal on `mp_client_mode`; Lua bindings for `set_mp_client_mode` / `mp_client_mode`; absolute `set_game_time()`; `SetBodyYaw`; GNS bridge registration
- Lua layer: mp_core (state machine + actor callback hook), mp_protocol (text serialization), mp_host_events (host broadcasts), mp_client_state (client applies with bidirectional ID mapping via pending spawn keys), mp_alife_guard (dummy se_obj returns on blocked create, pcall shield on SendScriptCallback dispatch)
- Recent patch: ZCP 1.4 `smr_handle_spawn` now short-circuits on `is_mp_client()` — prevents the earlier l13_generators native crash in `fill_start_position` loop

## The crash we are mapping around

Joe's xray_twent (2).log (attached as the most recent crash upload). Last recoverable lines before native crash at `AnomalyDX11AVX.exe+0x000000014013BCF8`:

```
[GAMMA MP] ID mapped: host 16350 -> local 31745 (zone_mine_gravitational_weak)
~ Story Objects | Multiple objects trying to use same story_id ah_sarik_squad
[GAMMA MP] ID mapped: host 19529 -> local 31747 (ah_sarik)
stack trace:
...crash site 0x13BCF8
```

The pattern: host entities are being mapped to local IDs successfully (thousands of space_restrictors, burning fuzz zones, radioactive fields, gravitational mines all worked), then the stream reaches an `ah_sarik` squad whose story_id collides with the client's pre-existing native-alife `ah_sarik` → engine's Story Objects registry complains → next lookup or ref-deref crashes natively.

## Central hypothesis to validate or disprove

> `set_mp_client_mode(true)` gates alife's *update* loop but does NOT prevent the engine's initial world population from `all.spawn` / level_spawn files during level init. The client therefore has a fully populated native alife BEFORE our sync stream arrives. Every entity with fixed identity (story_id, unique section, fixed smart_terrain name, etc.) is spawned twice — once natively, once from our stream — and the second spawn collides.

If this hypothesis holds, the correct fix is systemic (broadcast filter or native-alife suppression), not per-entity-type patching. If it fails, we need a different model.

## Research tracks — dispatch these in parallel as subagents

Fire each of these as an independent subagent. Wait for all to complete, then synthesize. Each subagent should produce a self-contained section of the final map.

### Track 1: Engine crash site & story_object registry

Deliverable: identify exactly where `0x13BCF8` lives and what the Story Objects duplicate-detection warning is gating.

- Grep xray-monolith src for `"Multiple objects trying to use same story_id"` literal. Find the function, the class (likely `CStoryObjectRegistry` or similar in `xrServerEntities/` or `xrGame/`), what it does on collision (warn-and-continue, or warn-then-use-first, or warn-and-some-ptr-becomes-stale).
- Determine what subsequent code path dereferences that state. The crash is at `0x13BCF8`; symbols aren't resolvable from a corrupted minidump but the warning-to-crash window is tiny so the crash is near-certainly a downstream effect.
- Map the story_object lifecycle: where are story_ids registered on spawn? Where are they looked up during sim update, AI scheme selection, dialog trigger, etc.?
- Can the engine be patched to have the registry *replace* rather than *duplicate* when `mp_client_mode` is true? (i.e., the second registration of the same story_id wins, or is silently ignored.) What would that break?
- Document any other engine-side uniqueness registries similar to story_objects — the crash reveals one class of collision; enumerate the others so we don't play whack-a-mole on the next crash.

### Track 2: Client-side native alife init sequence

Deliverable: a timeline of what runs between "user clicks load save / connect" and `actor_on_first_update` firing, with specific attention to when alife populates.

- Engine init calls during level load: where does `all.spawn` parse? Where does the per-level `.spawn` file parse? Where are smart_terrain configs loaded? In what order relative to `CScriptEngine::init()` / script callback registration?
- Where does our `set_mp_client_mode(true)` actually get called on the client? (Should be in `mp_core.script` when connection completes, but find the exact path.) Is that before or after `all.spawn` loading finishes?
- If it's after, can we move it earlier? Can we set mp_client_mode from a pre-level hook, or by setting a flag in user.ltx, or by intercepting `main_menu` / `disconnect` / `connect` engine events?
- If we gated `CALifeUpdateManager::create` (the native spawn function, not `alife():create()` from Lua) on `mp_client_mode`, what flows through that? Does `all.spawn` loading go through the same `create()` path? What's the "one function every spawn funnels through" on the engine side?
- Are there level_spawn callbacks or XR "register" events that fire once per entity during initial population, that we could hook from Lua to observe what's being spawned?

### Track 3: Sync layer broadcast catalog

Deliverable: an exhaustive list of what the host currently broadcasts, with classification of each entity type's identity properties.

- Read `mp_host_events.script` top to bottom. Enumerate every message type sent. For `ENTITY_SPAWN` specifically, what entities fire the broadcast? What filter rules currently apply? (We have ZCP source tag filtering and online-only filtering — document exactly what passes through.)
- In `mp_protocol.script`, what fields of the entity are serialized into the ENTITY_SPAWN payload? Section name? Story ID? Parent? Position? Level?
- In `mp_client_state.script`, how is ENTITY_SPAWN applied? What does `do_entity_spawn` call? If it calls `alife():create()`, what does the engine do with a section that has a fixed story_id when that story_id is already registered?
- Does the broadcast currently include entities that originated from `all.spawn` (natively populated world), or only entities that spawned *runtime* (from alife timers, scripts)? If both, how does the host tell them apart?

### Track 4: Fixed-identity entity catalog

Deliverable: a classified list of what kinds of entities have fixed identity that would collide on duplicate spawn.

- story_ids: grep `configs/gameplay/*.xml` and all `story_objects*.ltx` files for registered story objects. Estimate count. Sample representative entries.
- Unique quest items: grep configs for items flagged as unique (story items, quest-pinned items). 
- Unique NPCs: trader NPCs, named storyline characters, anomaly-field bosses, etc. Usually identified by story_id or by being a single instance of a section.
- Smart_terrains: each smart_terrain is a unique name. Does the host's broadcast touch them? Does our sync apply them? If yes, every single one collides.
- Space_restrictors / zones / level objects: the log shows thousands of these mapping successfully. Why don't they collide? (Hypothesis: no story_id, no uniqueness constraint — the engine allows duplicate zones. Confirm.)

### Track 5: Strategy cost-out

Deliverable: a structured comparison of the two strategies (plus any hybrid that emerges from Tracks 1-4) with a concrete recommendation.

- Strategy A: **Broadcast filter.** Host doesn't send entities that have fixed identity (story_id, unique section). Client keeps its own copies. Host only sends runtime-spawned entities (mutant squads, dropped items, actor hit events). What `mp_host_events` code changes? What do we lose — does the client still see host's random mutant spawns, dropped loot, etc.?
- Strategy B: **Suppress client native alife init.** Engine patch: when `mp_client_mode` is set pre-level-load, skip the `all.spawn` / level_spawn phase entirely. Client arrives with an empty alife. Host's broadcast populates everything. What engine code must change? What breaks (quests, scripted callbacks that assume certain NPCs exist, smart_terrain bookkeeping)?
- Strategy C: **Hybrid / other**, if Tracks 1-4 reveal one.
- For each strategy: implementation scope (file touches, patch count, LOC estimate), risk (known breakage, unknown breakage, test matrix), test plan (what Joe needs to verify), reversibility (can we back out easily?).

Give a clear recommendation with reasoning, not just "both have tradeoffs."

## Synthesis format

After subagents complete, produce a single markdown document at `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\docs\CONNECTION_MAP.md` with this structure:

```
# Client Connection Sequence Map

## 1. What happens on connect (timeline)
[bulletable flow from mouse click through actor_on_first_update through crash]

## 2. Engine crash site analysis (Track 1 output)
## 3. Native alife init sequence (Track 2 output)
## 4. Sync broadcast catalog (Track 3 output)
## 5. Fixed-identity collision catalog (Track 4 output)
## 6. Strategy analysis and recommendation (Track 5 output)

## 7. Open questions requiring live data
[what we couldn't answer without running the game / asking Joe]

## 8. Proposed next patch
[the ONE thing to change, with file/line/diff sketch, based on recommendation]
```

Do NOT write the patch itself. Sketch the diff in the markdown at most. The patch lands in a separate session after Jonah reviews this map.

## Methodology rules

- Fire subagents in parallel, not sequentially. Wait for all to complete before synthesizing.
- Verify claims by reading the actual files. If you say "`fill_start_position` is called from X", prove it with a grep line number.
- When a subagent reports something surprising or non-obvious, have a second subagent verify independently before including in the synthesis.
- If a subagent's output contradicts the central hypothesis, do NOT bend the evidence to fit. Update the hypothesis and report the contradiction prominently.
- If any research track hits a dead end (e.g., can't find the crash function without the PDB), say so explicitly rather than guessing. Flag as "open question requiring live data" — do not fabricate conclusions.
- Quote file paths and line numbers for every substantive claim.
- When you finish, do a self-review pass: is this document actually usable by Jonah to make a decision? Does it answer "what do we do next" with enough specificity? If not, refine.

## What "done" looks like

Jonah reads `CONNECTION_MAP.md`, in 15 minutes has a clear picture of what's happening and why, picks strategy A or B (or a recommended hybrid) with confidence, knows the concrete next change to make, and has no residual "wait but what about..." questions because the open-questions section already lists the remaining unknowns and what data would close them.
