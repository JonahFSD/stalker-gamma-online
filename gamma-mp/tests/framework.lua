-- framework.lua: Minimal test framework for Lua 5.1
-- describe/it/assert_*/before_each/summary

local _pass = 0
local _fail = 0
local _current_before_each = nil
local _current_describe = ""

local function green(s) return "\27[32m" .. s .. "\27[0m" end
local function red(s)   return "\27[31m" .. s .. "\27[0m" end

-- Deep equality for tables
local function deep_eq(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not deep_eq(v, b[k]) then return false end
    end
    for k, v in pairs(b) do
        if not deep_eq(v, a[k]) then return false end
    end
    return true
end

function describe(name, fn)
    local prev_describe = _current_describe
    local prev_before = _current_before_each
    _current_describe = name
    _current_before_each = nil
    print("\n=== " .. name .. " ===")
    fn()
    _current_describe = prev_describe
    _current_before_each = prev_before
end

function before_each(fn)
    _current_before_each = fn
end

function it(name, fn)
    if _current_before_each then
        local ok, err = pcall(_current_before_each)
        if not ok then
            _fail = _fail + 1
            print("  " .. red("[FAIL]") .. " " .. name)
            print("        before_each error: " .. tostring(err))
            return
        end
    end

    local ok, err = pcall(fn)
    if ok then
        _pass = _pass + 1
        print("  " .. green("[PASS]") .. " " .. name)
    else
        _fail = _fail + 1
        print("  " .. red("[FAIL]") .. " " .. name)
        print("        " .. tostring(err))
    end
end

-- Assertions

local function fail(msg, extra)
    error((extra and (extra .. ": ") or "") .. msg, 3)
end

function assert_eq(expected, actual, msg)
    if not deep_eq(expected, actual) then
        fail(string.format("expected %s, got %s", tostring(expected), tostring(actual)), msg)
    end
end

function assert_neq(a, b, msg)
    if deep_eq(a, b) then
        fail(string.format("expected values to differ, both are %s", tostring(a)), msg)
    end
end

function assert_nil(val, msg)
    if val ~= nil then
        fail(string.format("expected nil, got %s", tostring(val)), msg)
    end
end

function assert_not_nil(val, msg)
    if val == nil then
        fail("expected non-nil value", msg)
    end
end

function assert_true(val, msg)
    if not val then
        fail(string.format("expected true, got %s", tostring(val)), msg)
    end
end

function assert_false(val, msg)
    if val then
        fail(string.format("expected false/nil, got %s", tostring(val)), msg)
    end
end

function assert_contains(str, sub, msg)
    if type(str) ~= "string" then
        fail(string.format("assert_contains: expected string, got %s", type(str)), msg)
    end
    if not str:find(sub, 1, true) then
        fail(string.format("expected %q to contain %q", str, sub), msg)
    end
end

function assert_error(fn, msg)
    local ok = pcall(fn)
    if ok then
        fail("expected function to throw an error", msg)
    end
end

function summary()
    local total = _pass + _fail
    print(string.format("\nRESULTS: %d passed, %d failed", _pass, _fail))
    if _fail > 0 then
        os.exit(1)
    end
    os.exit(0)
end
