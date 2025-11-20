-- gold-digger.lua

local ADDON_NAME = ...
local PREFIX = "|cffffcc00[gold-digger]|r"

-- Local (non-saved) state
local gold_digger = {}
gold_digger.current_run = nil

------------------------------------------------------------
-- SavedVariables initialization
------------------------------------------------------------
local function InitDB()
    gold_digger_db = gold_digger_db or {}
    gold_digger_db.profile = gold_digger_db.profile or {
        auto_start_instances = false,  -- reserved for future phases
    }
    gold_digger_db.runs = gold_digger_db.runs or {}
end

------------------------------------------------------------
-- Utility: converting copper to gold string
------------------------------------------------------------
local function format_money(copper)
    local negative = copper < 0
    copper = math.abs(copper)

    local gold   = math.floor(copper / (100 * 100))
    local silver = math.floor((copper / 100) % 100)
    local copper_rem = copper % 100

    local s = string.format("%dg %02ds %02dc", gold, silver, copper_rem)
    if negative then
        s = "-" .. s
    end
    return s
end

local function print_msg(msg)
    print(PREFIX .. " " .. (msg or ""))
end

------------------------------------------------------------
-- Run helpers
------------------------------------------------------------
local function get_character_info()
    local name = UnitName("player")
    local realm = GetRealmName() or ""
    local _, class = UnitClass("player")
    local level = UnitLevel("player")

    local spec_id = nil
    if GetSpecialization then
        local spec_index = GetSpecialization()
        if spec_index then
            spec_id = select(1, GetSpecializationInfo(spec_index))
        end
    end

    return name, realm, class, level, spec_id
end

local function get
