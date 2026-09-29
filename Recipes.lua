-- Recipes: step 1. Saves the recipes every character knows, automatically, whenever a
-- profession window is opened (C_TradeSkillUI is the only trade skill API on Forever).
--
-- CraftBoardDB.chars[guid] = { name, class, t, profs = { [professionID] = {
--     name, skill, max, t, recipes = { recipeID, ... }, cd = { [recipeID] = expiresAt } } },
--     known = { [professionName] = { skill, max } } }
-- CraftBoardDB.recipes[recipeID] = { n = name, o = outputItemID, p = professionID,
--     r = { itemID, quantity, itemID, quantity, ... } }   (shared by all characters)
local _, CB = ...

local TS = C_TradeSkillUI
local SNAPSHOT_DELAY = 1 -- TRADE_SKILL_LIST_UPDATE fires a lot while a window loads

function CB:PlayerFullName()
    local first, second = UnitName("player")
    if second and second ~= "" then return first .. (CHARACTERNAME_SURNAME_SEPARATOR or " ") .. second end
    return first or "Unknown"
end

local function charRecord()
    local db = CB.db
    db.chars = db.chars or {}
    local guid = UnitGUID("player")
    local rec = db.chars[guid]
    if not rec then
        rec = { profs = {}, known = {} }
        db.chars[guid] = rec
    end
    rec.name = CB:PlayerFullName()
    rec.class = select(2, UnitClass("player"))
    rec.profs = rec.profs or {}
    rec.known = rec.known or {}
    return rec
end
CB.CharRecord = charRecord

-- Reagents as a flat list { itemID, quantity, ... }: the first item of each slot.
local function reagentList(recipeID)
    local ok, schematic = pcall(TS.GetRecipeSchematic, recipeID, false)
    if not ok or type(schematic) ~= "table" then return nil, nil end
    local list = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local first = slot.reagents and slot.reagents[1]
        if first and first.itemID and (slot.quantityRequired or 0) > 0 then
            list[#list + 1] = first.itemID
            list[#list + 1] = slot.quantityRequired
        end
    end
    return list, schematic.outputItemID
end

-- Remembers a recipe's static data once; later snapshots only fill in what is missing.
local function cacheRecipe(recipeID, name, professionID)
    local recipes = CB.db.recipes
    local entry = recipes[recipeID]
    if entry and entry.r then return end
    local reagents, output = reagentList(recipeID)
    recipes[recipeID] = {
        n = name or (entry and entry.n), o = output or (entry and entry.o),
        p = professionID, r = reagents or (entry and entry.r),
    }
end

-- Seconds left on a recipe cooldown, or nil.
local function cooldownLeft(recipeID)
    local ok, cooldown = pcall(TS.GetRecipeCooldown, recipeID)
    if ok and type(cooldown) == "number" and cooldown > 0 then return cooldown end
end

local function snapshot(trigger)
    if not CB.db or type(TS) ~= "table" then return end
    if TS.IsTradeSkillLinked and TS.IsTradeSkillLinked() then return end -- someone else's window
    if TS.IsTradeSkillGuild and TS.IsTradeSkillGuild() then return end
    if TS.IsTradeSkillReady and not TS.IsTradeSkillReady() then return end

    local okBase, base = pcall(TS.GetBaseProfessionInfo)
    if not okBase or type(base) ~= "table" or not base.professionID then return end
    local okIds, ids = pcall(TS.GetAllRecipeIDs)
    if not okIds or type(ids) ~= "table" or #ids == 0 then return end

    local recipes, cds = {}, {}
    local now = time()
    for _, id in ipairs(ids) do
        local okInfo, info = pcall(TS.GetRecipeInfo, id)
        if okInfo and type(info) == "table" and info.learned then
            recipes[#recipes + 1] = id
            cacheRecipe(id, info.name, base.professionID)
            local left = cooldownLeft(id)
            if left then
                cds[id] = now + left
                CB.db.recipes[id].cdr = true -- a recipe with a cooldown, remembered even when it is ready
            end
        end
    end

    local rec = charRecord()
    local name = base.professionName or ("profession " .. tostring(base.professionID))
    rec.profs[base.professionID] = {
        name = name, skill = base.skillLevel or 0, max = base.maxSkillLevel or 0,
        t = now, recipes = recipes, cd = cds,
    }
    rec.t = now
    CB.lastSnapshot = { name = name, count = #recipes, trigger = trigger, t = now }
    if CB.OnRecipesChanged then CB:OnRecipesChanged(rec) end
end

local pending = false
local function scheduleSnapshot(trigger)
    if pending then return end
    pending = true
    C_Timer.After(SNAPSHOT_DELAY, function()
        pending = false
        CB:Call("recipe snapshot", snapshot, trigger)
    end)
end

for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED" }) do
    CB:RegisterEvent(event, function() scheduleSnapshot(event) end)
end

-- Which professions this character has, without opening any window (name and skill only).
local function recordKnownProfessions()
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return end
    local rec = charRecord()
    for _, index in pairs({ GetProfessions() }) do
        local ok, name, _, skill, max = pcall(GetProfessionInfo, index)
        if ok and name then rec.known[name] = { skill = skill or 0, max = max or 0 } end
    end
end

CB:RegisterEvent("PLAYER_LOGIN", function() recordKnownProfessions() end)
CB:RegisterEvent("SKILL_LINES_CHANGED", function() if CB.db then recordKnownProfessions() end end)

-- ---------------------------------------------------------------------------
-- /cb recipes: what is saved.
-- ---------------------------------------------------------------------------

CB:AddSlashCommand("recipes", function()
    local chars = CB.db.chars
    if not chars or not next(chars) then
        CB:Print("Nothing saved yet. Open a profession window (K / your tradeskill button).")
        return
    end
    for _, rec in pairs(chars) do
        CB:Print(("|cffb57edc%s|r (%s)"):format(rec.name or "?", rec.class or "?"))
        local any = false
        for _, prof in pairs(rec.profs) do
            any = true
            CB:Print(("  %s %d/%d: %d recipes (saved %s)"):format(
                prof.name, prof.skill, prof.max, #prof.recipes, date("%d/%m %H:%M", prof.t)))
        end
        if not any then CB:Print("  no profession window opened yet") end
        for pname, k in pairs(rec.known) do
            local saved = false
            for _, prof in pairs(rec.profs) do if prof.name == pname then saved = true end end
            if not saved then CB:Print(("  %s %d/%d: not opened yet"):format(pname, k.skill, k.max)) end
        end
    end
end, "list the recipes saved for your characters")
