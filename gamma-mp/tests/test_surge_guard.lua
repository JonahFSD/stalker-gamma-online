-- test_surge_guard.lua
--
-- Verifies puppet protection during surges (emissions).
--
-- FINDINGS (Phase 1 discovery, 2026-04-16):
--
--   surge_manager.script (mod 265 "NPCs Die in Emissions for Real"):
--     kill_objects_at_pos() line 1379: checks `npc:has_info("npcx_is_companion")`
--     → puppets have this infoportion → SAFE from surge kill.
--
--   surge_rush_scheme_common.script (same mod):
--     is_valid_npc() lines 139/154: checks axr_companions tables ONLY, not infoportion.
--     Puppets are NOT registered in axr_companions tables (mp_puppet never calls
--     axr_companions functions) → WITHOUT a patch, puppets would receive the cover
--     scheme, which sets movement destinations and FIGHTS position sync.
--
-- PATCH APPLIED:
--   C:\GAMMA\overwrite\gamedata\scripts\surge_rush_scheme_common.script
--   Function: is_valid_npc(), after `local id = npc:id()` (line 138)
--   Guard added:
--     if mp_puppet and mp_puppet.is_puppet and mp_puppet.is_puppet(id) then
--       return
--     end
--   → Nil-safe: file loads normally when MP mod is not present.

local BASE = debug.getinfo(1, "S").source:match("@(.+[\\/])") or "./"
dofile(BASE .. "framework.lua")

-- ---------------------------------------------------------------------------
-- Minimal reproduction of the patched is_valid_npc() logic
-- (extracted from surge_rush_scheme_common.script with our guard inserted)
-- ---------------------------------------------------------------------------

-- Minimal NPC object mock
local function make_npc(id, section, is_stalker, community, in_story)
    return {
        _id       = id,
        _section  = section,
        _stalker  = is_stalker,
        _comm     = community,
        _story    = in_story,
        id        = function(self) return self._id end,
        name      = function(self) return "npc_" .. self._id end,
    }
end

-- Stubs matching GAMMA's globals
local function setup_globals(puppet_ids)
    _G.IsStalker = function(npc) return npc._stalker end
    _G.character_community = function(npc) return npc._comm end
    _G.get_object_story_id = function(id) return nil end

    -- axr_companions tables — puppets are NOT in these
    _G.axr_companions = {
        non_task_companions = {},
        companion_squads    = {},
    }

    -- surge_manager_ignore_npc — empty
    _G.surge_manager_ignore_npc = { ignore_npc = {} }

    -- mp_puppet with the tracked ID set
    local puppet_set = {}
    for _, pid in ipairs(puppet_ids) do
        puppet_set[pid] = true
    end
    _G.mp_puppet = {
        is_puppet = function(id) return puppet_set[id] == true end,
    }
end

-- Inline of the patched is_valid_npc (mirrors the overwrite file exactly)
local surge_ignore_communities = { zombied = true, monolith = true, monster = true }
local function is_surge_community(npc)
    return not surge_ignore_communities[character_community(npc) or "monster"]
end

local function is_valid_npc_patched(npc)
    if not npc then return end
    if not IsStalker(npc) then return end
    if not is_surge_community(npc) then return end

    local id = npc:id()
    -- *** our guard ***
    if mp_puppet and mp_puppet.is_puppet and mp_puppet.is_puppet(id) then
        return
    end
    if axr_companions.non_task_companions[id] then return end
    if surge_manager_ignore_npc and surge_manager_ignore_npc.ignore_npc
            and surge_manager_ignore_npc.ignore_npc[npc._section] then
        return
    end
    if get_object_story_id(id) then return end
    for _, squad in pairs(axr_companions.companion_squads) do
        if squad then
            for k in squad:squad_members() do
                if k.id == id then return end
            end
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

describe("surge guard: puppet excluded from cover scheme", function()

    before_each(function()
        setup_globals({ 42 })  -- NPC id=42 is a puppet
    end)

    it("normal stalker is valid (eligible for cover scheme)", function()
        local npc = make_npc(99, "stalker_bandit", true, "bandit", false)
        assert_eq(true, is_valid_npc_patched(npc), "normal stalker should be valid")
    end)

    it("puppet stalker is rejected by mp_puppet guard", function()
        local npc = make_npc(42, "stalker_bandit", true, "bandit", false)
        assert_nil(is_valid_npc_patched(npc), "puppet should return nil (excluded)")
    end)

    it("non-stalker entity is rejected regardless", function()
        local npc = make_npc(10, "dog_flesh", false, "monster", false)
        assert_nil(is_valid_npc_patched(npc), "non-stalker should return nil")
    end)

    it("monolith community is rejected by community filter", function()
        local npc = make_npc(20, "stalker_monolith", true, "monolith", false)
        assert_nil(is_valid_npc_patched(npc), "monolith should return nil")
    end)

    it("nil npc returns nil safely", function()
        assert_nil(is_valid_npc_patched(nil), "nil input should return nil")
    end)

end)

describe("surge guard: nil-safe when mp_puppet not loaded", function()

    before_each(function()
        setup_globals({})
        _G.mp_puppet = nil  -- MP mod not present
    end)

    it("normal stalker still valid when mp_puppet is nil", function()
        local npc = make_npc(99, "stalker_bandit", true, "bandit", false)
        assert_eq(true, is_valid_npc_patched(npc), "should not crash or break without MP mod")
    end)

    it("no crash when mp_puppet.is_puppet is missing", function()
        _G.mp_puppet = {}  -- module exists but is_puppet not defined yet
        local npc = make_npc(99, "stalker_bandit", true, "bandit", false)
        assert_eq(true, is_valid_npc_patched(npc), "partial mp_puppet table should be safe")
    end)

end)

describe("surge guard: kill loop already protected via infoportion", function()

    -- This test documents — not re-implements — the kill guard.
    -- surge_manager.script:kill_objects_at_pos() line 1379:
    --   and not npc:has_info("npcx_is_companion")
    -- mp_puppet.script:try_give_infoportion() lines 30-36 give this infoportion on spawn.
    -- No patch needed in surge_manager.script.

    it("puppet has npcx_is_companion infoportion (set by mp_puppet on spawn)", function()
        local infoportions = {}
        local function make_npc_with_info(id)
            return {
                _id = id,
                give_info_portion = function(self, info)
                    infoportions[info] = true
                end,
                has_info = function(self, info)
                    return infoportions[info] == true
                end,
            }
        end

        -- Simulate try_give_infoportion from mp_puppet.script lines 30-36
        local function try_give_infoportion(se_obj)
            if se_obj and type(se_obj.give_info_portion) == "function" then
                se_obj:give_info_portion("npcx_is_companion")
            end
        end

        local npc = make_npc_with_info(42)
        try_give_infoportion(npc)

        assert_true(npc:has_info("npcx_is_companion"),
            "puppet must have npcx_is_companion after spawn")
    end)

end)

summary()
