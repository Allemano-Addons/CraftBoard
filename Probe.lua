-- Probe (step 0): records what the WoW Forever client really offers for CraftBoard:
-- which profession APIs exist and what they return, which events fire, whether item
-- tooltips can get a line, how guild names look and whether guild addon messages arrive
-- (and how long they may be). Everything goes to CraftBoardDB.probe[guid], read from the
-- SavedVariables file after /reload. Read-only: never crafts, never calls protected code.
local _, CB = ...

local Probe = {}
CB.Probe = Probe

local PREFIX = "CraftBoard"
local MAX_ROWS = 400      -- recipe names kept per profession window
local DETAIL_ROWS = 6     -- recipes recorded in full (links, reagents, tools, cooldown)

-- ---------------------------------------------------------------------------
-- Helpers (as in ART's probe): values as strings, secret values never touched.
-- ---------------------------------------------------------------------------

local function str(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    if type(v) == "table" then return "<table>" end
    return tostring(v)
end

local function pack(...)
    local t = { n = select("#", ...) }
    for i = 1, t.n do t[i] = str((select(i, ...))) end
    return t
end

-- Calls fn protected; { missing = true }, { err = msg } or the packed return values.
local function try(fn, ...)
    if type(fn) ~= "function" then return { missing = true } end
    local res = pack(pcall(fn, ...))
    if res[1] ~= "true" then return { err = res[2] } end
    tremove(res, 1)
    res.n = res.n - 1
    return res
end

-- A table's fields as strings (for C_ API results).
local function fields(tbl)
    if type(tbl) ~= "table" then return str(tbl) end
    local out = {}
    for k, v in pairs(tbl) do
        out[tostring(k)] = type(v) == "table" and ("<table " .. #v .. ">") or str(v)
    end
    return out
end

local function fnList(tbl)
    local list = {}
    if type(tbl) == "table" then
        for k, v in pairs(tbl) do if type(v) == "function" then list[#list + 1] = k end end
    end
    sort(list)
    return table.concat(list, " ")
end

local function charKey() return UnitGUID("player") or "unknown" end

local function data()
    local p = CB.db.probe
    local key = charKey()
    p[key] = p[key] or {}
    return p[key]
end

-- Full name as Forever shows it ("First Surname"); UnitName's 2nd return is the surname there.
local function playerFullName()
    local first, second = UnitName("player")
    if second and second ~= "" then return first .. (CHARACTERNAME_SURNAME_SEPARATOR or " ") .. second end
    return first
end

-- ---------------------------------------------------------------------------
-- 1. APIs
-- ---------------------------------------------------------------------------

local API_NAMES = {
    -- Classic trade skill API
    "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillLine", "GetTradeSkillItemLink", "GetTradeSkillRecipeLink",
    "GetTradeSkillNumMade", "GetTradeSkillNumReagents", "GetTradeSkillReagentInfo", "GetTradeSkillReagentItemLink",
    "GetTradeSkillTools", "GetTradeSkillCooldown", "GetTradeSkillDescription", "GetTradeSkillIcon",
    "GetTradeSkillSelectionIndex", "ExpandTradeSkillSubClass", "CollapseTradeSkillSubClass", "DoTradeSkill",
    "CloseTradeSkill", "GetTradeSkillSubClassFilter", "SetTradeSkillSubClassFilter", "TradeSkillOnlyShowMakeable",
    -- Classic craft API (Enchanting, Beast Training)
    "GetNumCrafts", "GetCraftInfo", "GetCraftDisplaySkillLine", "GetCraftName", "GetCraftItemLink", "GetCraftRecipeLink",
    "GetCraftNumReagents", "GetCraftReagentInfo", "GetCraftReagentItemLink", "GetCraftSpellFocus", "GetCraftDescription",
    "DoCraft", "CloseCraft",
    -- professions and skills
    "GetProfessions", "GetProfessionInfo", "GetNumSkillLines", "GetSkillLineInfo", "IsSpellKnown", "GetSpellInfo",
    -- items and tooltips
    "GetItemInfo", "C_Item", "GameTooltip", "TooltipDataProcessor", "C_TooltipInfo", "ItemRefTooltip",
    -- guild and messages
    "IsInGuild", "GetGuildInfo", "GetNumGuildMembers", "GetGuildRosterInfo", "GuildRoster", "C_GuildInfo",
    "C_ChatInfo", "SendAddonMessage", "RegisterAddonMessagePrefix", "Ambiguate",
    -- misc
    "issecretvalue", "C_TradeSkillUI", "C_Container", "C_Timer", "C_AddOns", "CHARACTERNAME_SURNAME_SEPARATOR",
}

local function probeApis()
    local out = {}
    for _, name in ipairs(API_NAMES) do out[name] = type(_G[name]) end
    local ns = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:match("^C_") and type(v) == "table" then ns[#ns + 1] = k end
    end
    sort(ns)
    out._namespaces = table.concat(ns, " ")
    out._C_TradeSkillUI = fnList(C_TradeSkillUI)
    out._C_TooltipInfo = fnList(C_TooltipInfo)
    out._C_GuildInfo = fnList(C_GuildInfo)
    out._C_ChatInfo = fnList(C_ChatInfo)
    out._TooltipDataProcessor = fnList(TooltipDataProcessor)
    return out
end

-- ---------------------------------------------------------------------------
-- 2. Professions (skill lines) of this character
-- ---------------------------------------------------------------------------

local function probeProfessions()
    local out = { getProfessions = try(GetProfessions), info = {}, skillLines = {} }
    if type(GetProfessions) == "function" then
        local ok, a, b, c, d, e = pcall(GetProfessions)
        if ok then
            for _, idx in ipairs({ a, b, c, d, e }) do
                if idx then out.info[#out.info + 1] = try(GetProfessionInfo, idx) end
            end
        end
    end
    local n = type(GetNumSkillLines) == "function" and select(2, pcall(GetNumSkillLines)) or 0
    for i = 1, min(tonumber(n) or 0, 40) do out.skillLines[i] = try(GetSkillLineInfo, i) end
    return out
end

-- ---------------------------------------------------------------------------
-- 3. Profession window snapshots: taken automatically each time a profession (or the
--    craft window, Enchanting in Classic) opens or updates.
-- ---------------------------------------------------------------------------

local function tradeRow(i)
    local row = {
        info = try(GetTradeSkillInfo, i), itemLink = try(GetTradeSkillItemLink, i),
        recipeLink = try(GetTradeSkillRecipeLink, i), numMade = try(GetTradeSkillNumMade, i),
        tools = try(GetTradeSkillTools, i), cooldown = try(GetTradeSkillCooldown, i),
        icon = try(GetTradeSkillIcon, i), reagents = {},
    }
    local okN, n = pcall(GetTradeSkillNumReagents, i)
    for r = 1, (okN and tonumber(n) or 0) do
        row.reagents[r] = { info = try(GetTradeSkillReagentInfo, i, r), link = try(GetTradeSkillReagentItemLink, i, r) }
    end
    return row
end

local function craftRow(i)
    local row = {
        info = try(GetCraftInfo, i), itemLink = try(GetCraftItemLink, i), recipeLink = try(GetCraftRecipeLink, i),
        focus = try(GetCraftSpellFocus, i), reagents = {},
    }
    local okN, n = pcall(GetCraftNumReagents, i)
    for r = 1, (okN and tonumber(n) or 0) do
        row.reagents[r] = { info = try(GetCraftReagentInfo, i, r), link = try(GetCraftReagentItemLink, i, r) }
    end
    return row
end

-- kind "trade" or "craft". Headers are listed by name; the first DETAIL_ROWS real recipes in full.
local function snapshotWindow(kind, trigger)
    local isTrade = kind == "trade"
    local line = isTrade and try(GetTradeSkillLine) or try(GetCraftDisplaySkillLine)
    local okCount, count = pcall(isTrade and GetNumTradeSkills or GetNumCrafts)
    count = okCount and tonumber(count) or 0
    local snap = {
        t = time(), trigger = trigger, line = line, count = count, rows = {}, details = {},
        headers = 0, recipes = 0, selection = isTrade and try(GetTradeSkillSelectionIndex) or nil,
    }
    local infoFn = isTrade and GetTradeSkillInfo or GetCraftInfo
    for i = 1, min(count, MAX_ROWS) do
        local ok, name, kindOrSub, a3, a4 = pcall(infoFn, i)
        if ok then
            -- Trade: name, type, numAvailable, isExpanded. Craft: name, subName, type, numAvailable.
            local rowType = isTrade and kindOrSub or a3
            snap.rows[i] = str(name) .. " | " .. str(rowType) .. " | " .. str(isTrade and a3 or a4)
            if rowType == "header" then
                snap.headers = snap.headers + 1
            else
                snap.recipes = snap.recipes + 1
                if #snap.details < DETAIL_ROWS then
                    snap.details[#snap.details + 1] = isTrade and tradeRow(i) or craftRow(i)
                end
            end
        else
            snap.rows[i] = "error: " .. str(name)
        end
    end
    local d = data()
    d.windows = d.windows or {}
    local lineName = line[1] or "?"
    d.windows[kind .. ": " .. lineName] = snap
    return snap
end

-- Retail-style C_TradeSkillUI, if this client has it (recorded next to the Classic API).
local function probeTradeSkillUI()
    if type(C_TradeSkillUI) ~= "table" then return { missing = true } end
    local out = {
        baseInfo = try(function() return fields(C_TradeSkillUI.GetBaseProfessionInfo()) end),
        childInfo = try(function() return fields(C_TradeSkillUI.GetChildProfessionInfo()) end),
        isOpen = try(C_TradeSkillUI.IsTradeSkillReady),
    }
    local okIds, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if okIds and type(ids) == "table" then
        out.recipeCount = #ids
        out.firstRecipes = {}
        for i = 1, min(#ids, 3) do
            local id = ids[i]
            out.firstRecipes[i] = {
                id = str(id),
                info = try(function() return fields(C_TradeSkillUI.GetRecipeInfo(id)) end),
                schematic = try(function() return fields(C_TradeSkillUI.GetRecipeSchematic(id, false)) end),
                itemLink = try(C_TradeSkillUI.GetRecipeItemLink, id),
            }
        end
    else
        out.allRecipeIDs = okIds and str(ids) or ("error: " .. str(ids))
    end
    return out
end

local pendingSnapshot = {}
local function scheduleSnapshot(kind, trigger)
    if not CB.db or pendingSnapshot[kind] then return end
    pendingSnapshot[kind] = true
    -- Wait a moment: the list is filled after the "show" event.
    C_Timer.After(0.5, function()
        pendingSnapshot[kind] = nil
        CB:Call("probe " .. kind .. " window", function()
            local snap = snapshotWindow(kind, trigger)
            if kind == "trade" then data().tradeSkillUI = probeTradeSkillUI() end
            if snap.line.missing then return end -- this client has no such window API
            CB:Print(("Probe: %s window recorded (%d recipes, %d headers)."):format(
                str(snap.line[1]), snap.recipes, snap.headers))
        end)
    end)
end

-- ---------------------------------------------------------------------------
-- 4. Event log: which profession, guild and message events fire, how often, last args.
-- ---------------------------------------------------------------------------

local EVENTS = {
    "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE",
    "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_NAME_UPDATE", "TRADE_SKILL_FILTER_UPDATE",
    "CRAFT_SHOW", "CRAFT_UPDATE", "CRAFT_CLOSE",
    "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_TAB", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "CHAT_MSG_TRADESKILLS",
    "UNIT_SPELLCAST_SUCCEEDED", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "CHAT_MSG_ADDON", "BAG_UPDATE_DELAYED",
}
local SNAPSHOT_ON = {
    TRADE_SKILL_SHOW = "trade", TRADE_SKILL_LIST_UPDATE = "trade", TRADE_SKILL_UPDATE = "trade",
    CRAFT_SHOW = "craft", CRAFT_UPDATE = "craft",
}

local function logEvent(event, ...)
    if not CB.db then return end
    local d = data()
    d.events = d.events or {}
    local e = d.events[event] or { count = 0 }
    e.count = e.count + 1
    e.last = pack(...)
    if e.last.n > 6 then e.last = { n = 6, unpack(e.last, 1, 6) } end
    d.events[event] = e
end

local knownEvents = {}
for _, event in ipairs(EVENTS) do
    local ok = CB:RegisterEvent(event, function(ev, ...)
        if ev == "CHAT_MSG_ADDON" and (...) ~= PREFIX then return end -- only our own prefix
        logEvent(ev, ...)
        if SNAPSHOT_ON[ev] then scheduleSnapshot(SNAPSHOT_ON[ev], ev) end
    end)
    knownEvents[event] = ok and "ok" or "unknown"
end

-- ---------------------------------------------------------------------------
-- 5. Tooltips: count item tooltips we see, and with /cb probe tooltip add a test line.
-- ---------------------------------------------------------------------------

local tip = { method = "none", calls = 0, lines = 0, items = {} }
local tooltipLine = false

local function onItemTooltip(tooltip)
    tip.calls = tip.calls + 1
    local ok, name, link = pcall(tooltip.GetItem, tooltip)
    if ok and link and #tip.items < 8 then tip.items[#tip.items + 1] = str(name) .. " " .. str(link) end
    if tooltipLine then
        local okAdd, err = pcall(tooltip.AddLine, tooltip, "CraftBoard: tooltip line works", 0.71, 0.49, 0.86)
        if okAdd then
            tip.lines = tip.lines + 1
            if tip.method == "OnTooltipSetItem" then tooltip:Show() end -- Classic: resize after adding
        else
            tip.lineError = str(err)
        end
    end
end

if type(TooltipDataProcessor) == "table" and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    local ok, err = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip)
        CB:Call("tooltip", onItemTooltip, tooltip)
    end)
    tip.method = ok and "TooltipDataProcessor" or ("TooltipDataProcessor failed: " .. str(err))
end
if tip.method ~= "TooltipDataProcessor" and GameTooltip and GameTooltip.HookScript then
    local ok = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", function(tooltip)
        CB:Call("tooltip", onItemTooltip, tooltip)
    end)
    tip.method = ok and "OnTooltipSetItem" or (tip.method .. "; OnTooltipSetItem failed")
end

-- ---------------------------------------------------------------------------
-- 6. Guild: roster names, and addon messages of several lengths to the guild and to
--    ourselves (recipe lists will need many messages; the limit matters).
-- ---------------------------------------------------------------------------

local function probeGuild()
    local out = {
        inGuild = try(IsInGuild), guildInfo = try(GetGuildInfo, "player"),
        members = try(GetNumGuildMembers), roster = {},
    }
    for i = 1, 5 do out.roster[i] = try(GetGuildRosterInfo, i) end
    return out
end

local function runProbe()
    local d = data()
    d.t = time()
    d.version = CB.version
    d.build = pack(GetBuildInfo())
    d.unitName = try(UnitName, "player")
    d.fullName = playerFullName()
    d.apis = probeApis()
    d.knownEvents = knownEvents
    d.professions = probeProfessions()
    d.tooltip = tip

    -- Ask for a fresh roster, then read it once it has had time to arrive.
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster)
    elseif GuildRoster then pcall(GuildRoster) end

    local comm = { prefix = try(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix, PREFIX), sent = {}, received = {} }
    d.comm = comm
    local listener = function(_, prefix, text, channel, sender)
        if prefix ~= PREFIX then return end
        comm.received[#comm.received + 1] = { len = #text, head = text:sub(1, 12), channel = str(channel), sender = str(sender) }
    end
    CB:RegisterEvent("CHAT_MSG_ADDON", listener)
    local send = C_ChatInfo and C_ChatInfo.SendAddonMessage
    for _, len in ipairs({ 10, 200, 250, 255, 256, 300 }) do
        local text = ("p%03d"):format(len) .. string.rep("x", len - 4)
        comm.sent["guild" .. len] = try(send, PREFIX, text, "GUILD")
        comm.sent["whisper" .. len] = try(send, PREFIX, text, "WHISPER", playerFullName())
    end
    CB:Print("Probing for 6 seconds...")
    C_Timer.After(6, function()
        d.guild = probeGuild()
        comm.receivedCount = #comm.received
        CB:Print(("Probe saved (%d of our addon messages arrived). Open each profession window once, "
            .. "then /reload and send the file WTF\\...\\SavedVariables\\CraftBoard.lua."):format(#comm.received))
    end)
end

CB:AddSlashCommand("probe", function(arg)
    if strlower(arg or "") == "tooltip" then
        tooltipLine = not tooltipLine
        CB:Print("Tooltip test line " .. (tooltipLine and "ON: hover any item." or "off.") ..
            " Hook: " .. tip.method .. ", item tooltips seen: " .. tip.calls)
        if CB.db then data().tooltip = tip end
        return
    end
    runProbe()
end, "record what this client supports (then /reload); /cb probe tooltip toggles a test line on item tooltips")
