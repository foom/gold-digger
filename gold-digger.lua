-- gold-digger.lua

local ADDON_NAME = ...
local PREFIX = "|cffffcc00[gold-digger]|r"

-- Local runtime state (not saved)
local gold_digger = {}
gold_digger.current_run = nil

------------------------------------------------------------
-- SavedVariables initialization
------------------------------------------------------------
local function InitDB()
    gold_digger_db = gold_digger_db or {}
    gold_digger_db.profile = gold_digger_db.profile or {
        auto_start_instances = false,
    }
    gold_digger_db.runs = gold_digger_db.runs or {}
end

------------------------------------------------------------
-- Utilities
------------------------------------------------------------
local function print_msg(msg)
    print(PREFIX .. " " .. (msg or ""))
end

local function format_money(copper)
    local negative = copper < 0
    copper = math.abs(copper)

    local gold   = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copper_rem = copper % 100

    local s = string.format("%dg %02ds %02dc", gold, silver, copper_rem)
    return negative and ("-" .. s) or s
end

------------------------------------------------------------
-- Character / Instance helpers
------------------------------------------------------------
local function get_character_info()
    local name = UnitName("player")
    local realm = GetRealmName() or ""
    local _, class = UnitClass("player")
    local level = UnitLevel("player")

    local spec_id = nil
    if GetSpecialization then
        local idx = GetSpecialization()
        if idx then
            spec_id = select(1, GetSpecializationInfo(idx))
        end
    end

    return name, realm, class, level, spec_id
end

local function get_instance_info_safe()
    local in_instance, instance_type = IsInInstance()
    if not in_instance then return nil end

    local name, inst_type2, difficulty_id, _, _, _, _, instance_id = GetInstanceInfo()

    return {
        name         = name or "Unknown",
        type         = inst_type2 or instance_type or "world",
        difficultyID = difficulty_id or 0,
        instanceID   = instance_id or 0,
    }
end

------------------------------------------------------------
-- Run control
------------------------------------------------------------
local function start_run(manual, custom_name)
    if gold_digger.current_run then
        print_msg("A run is already in progress. Use /gd stop first.")
        return
    end

    local instance = get_instance_info_safe()
    if not instance then
        print_msg("You are not in an instance. The run will be tracked but instance will be 'Unknown'.")
    end

    local char_name, realm, class, level, spec_id = get_character_info()
    local now = time()
    local money = GetMoney()
    local next_id = #gold_digger_db.runs + 1

    local run = {
        id         = next_id,
        character  = char_name,
        realm      = realm,
        class      = class,
        level      = level,
        specID     = spec_id,
        startTime  = now,
        startMoney = money,
        autoStarted = not manual,
        autoStopped = false,
        customName = custom_name,
    }

    run.customName = nil

    if instance then
        run.instanceName = instance.name
        run.instanceType = instance.type
        run.difficultyID = instance.difficultyID
        run.instanceID   = instance.instanceID
    else
        run.instanceName = "Unknown"
        run.instanceType = "world"
        run.difficultyID = 0
        run.instanceID   = 0
    end

    gold_digger.current_run = run

    if custom_name then
      print_msg(string.format(
        "Run #%d started (%s).",
        run.id, custom_name
    ))
    else
    print_msg(string.format(
        "Run #%d started for %s-%s in %s.",
        run.id, char_name, realm, run.instanceName
    ))
end

local function end_run(reason, auto)
    if not gold_digger.current_run then
        print_msg("No run is currently in progress.")
        return
    end

    local run = gold_digger.current_run
    gold_digger.current_run = nil

    local now = time()
    local money = GetMoney()

    run.endTime   = now
    run.endMoney  = money
    run.duration  = now - (run.startTime or now)
    run.goldDelta = money - (run.startMoney or money)
    run.autoStopped = auto or false
    run.endReason   = reason or "unknown"

    table.insert(gold_digger_db.runs, run)

    print_msg(string.format(
        "Run #%d ended. Duration: %d sec. Gold change: %s.",
        run.id,
        run.duration,
        format_money(run.goldDelta)
    ))
end

------------------------------------------------------------
-- Stats
------------------------------------------------------------
local function show_summary_stats()
    local runs = gold_digger_db.runs
    local total = #runs

    if total == 0 then
        print_msg("No runs recorded yet.")
        return
    end

    local total_gold = 0
    local total_duration = 0
    local per_char = {}

    for _, run in ipairs(runs) do
        if run.duration and run.duration > 0 then
            local gold = run.goldDelta or 0
            total_gold = total_gold + gold
            total_duration = total_duration + run.duration

            local key = (run.character or "Unknown") .. "-" .. (run.realm or "")
            per_char[key] = per_char[key] or { gold = 0, duration = 0 }
            per_char[key].gold = per_char[key].gold + gold
            per_char[key].duration = per_char[key].duration + run.duration
        end
    end

    print_msg("----- Overall Summary -----")
    print_msg("Total runs: " .. total)

    if total_duration > 0 then
        local hours = total_duration / 3600
        local gph = total_gold / hours
        print_msg(string.format("Total time: %.2f hours", hours))
        print_msg("Total gold: " .. format_money(total_gold))
        print_msg("Gold/hour (overall): " .. format_money(math.floor(gph)))
    else
        print_msg("Total time: 0h")
        print_msg("Total gold: " .. format_money(total_gold))
    end

    print_msg("----- Per Character -----")
    for key, cs in pairs(per_char) do
        if cs.duration > 0 then
            local hours = cs.duration / 3600
            local gph = cs.gold / hours
            print_msg(string.format(
                "%s: %s total, %.2f hours, %s gold/hour",
                key,
                format_money(cs.gold),
                hours,
                format_money(math.floor(gph))
            ))
        else
            print_msg(key .. ": " .. format_money(cs.gold) .. " total, 0 hours")
        end
    end
end

local function show_help()
    print_msg("Commands:")
    print_msg("/gd start   - Start a run manually")
    print_msg("/gd stop    - Stop the current run")
    print_msg("/gd stats   - Show summary stats")
    print_msg("/gd help    - Show this help")
end

------------------------------------------------------------
-- Slash Commands
------------------------------------------------------------
SLASH_GOLD_DIGGER1 = "/gd"
SLASH_GOLD_DIGGER2 = "/golddigger"

SlashCmdList["GOLD_DIGGER"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg:find("^start") then
      -- strip the word "start" from the message
      local custom = msg:sub(6):gsub("^%s+", "")
      start_run(true, custom ~= "" and custom or nil)

    elseif msg == "stop" or msg == "end" or msg == "e" then
        end_run("manual", false)

    elseif msg == "stats" or msg == "summary" then
        show_summary_stats()

    elseif msg == "help" or msg == "" then
        show_help()

    else
        print_msg("Unknown command. Use /gd help.")
    end
end

------------------------------------------------------------
-- Events (addon load, logout)
------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        InitDB()
        print_msg("Loaded. Use /gd help for commands.")

    elseif event == "PLAYER_LOGOUT" then
        -- Optionally auto-close a run here:
        -- if gold_digger.current_run then
        --     end_run("logout", true)
        -- end
    end
end)
