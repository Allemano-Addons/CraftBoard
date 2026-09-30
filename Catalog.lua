-- Catalog: merges every source of "who can craft what" into one searchable list.
-- Sources: your own characters (CraftBoardDB.chars) and, from step 2, recipes other guild
-- members shared (CraftBoardDB.guild[fullName] = { class, t, profs = { [professionID] =
-- { name, skill, recipes = { ... }, cd = { [recipeID] = expiresAt } } } }).
-- Online status comes from the guild roster.
local _, CB = ...

local Catalog = {}
CB.Catalog = Catalog

local roster = {} -- full name -> { online, class, ago = seconds since last online }

function Catalog:RefreshRoster()
    wipe(roster)
    if not IsInGuild() or not GetNumGuildMembers then return end
    local last = C_GuildInfo and C_GuildInfo.GetGuildRosterLastOnline
    for i = 1, (GetNumGuildMembers()) do
        local name, _, _, _, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            local e = { online = online and true or false, class = classFile }
            if not e.online and last then
                local ok, years, months, days, hours = pcall(last, i)
                if ok and years then
                    e.ago = ((years * 12 + (months or 0)) * 30 + (days or 0)) * 86400 + (hours or 0) * 3600
                end
            end
            roster[name] = e
        end
    end
end

function Catalog:RosterInfo(name) return roster[name] end

-- Members the roster knows about, and how many of them have data here.
function Catalog:MemberCounts()
    local total, shared = 0, 0
    for name in pairs(roster) do
        total = total + 1
        if (CB.db.guild and CB.db.guild[name]) or self.ownNames[name] then shared = shared + 1 end
    end
    return shared, total
end

-- Recipe IDs are spell IDs and C_TradeSkillUI answers for any recipe, so a recipe another member
-- shared can usually be named without asking that member. Cached in CraftBoardDB.recipes; each ID is
-- tried once per session.
local tried = {}
local function resolveLocal(rid)
    local recipes = CB.db.recipes
    local meta = recipes[rid]
    if (meta and meta.n) or tried[rid] then return meta end
    tried[rid] = true
    local TS = C_TradeSkillUI
    local name, icon
    if TS and TS.GetRecipeInfo then
        local ok, info = pcall(TS.GetRecipeInfo, rid)
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            name, icon = info.name, info.icon
        end
    end
    if not name and C_Spell and C_Spell.GetSpellName then
        local ok, spellName = pcall(C_Spell.GetSpellName, rid)
        if ok and type(spellName) == "string" and spellName ~= "" then name = spellName end
    end
    if not name then return meta end
    meta = meta or {}
    meta.n = name
    meta.i = meta.i or icon
    if not meta.r and TS and CB.ReagentList then
        local reagents, output = CB.ReagentList(rid)
        meta.r = reagents
        meta.o = meta.o or output
    end
    recipes[rid] = meta
    return meta
end

local function compareCrafters(a, b)
    if a.online ~= b.online then return a.online end
    if a.ready ~= b.ready then return a.ready end
    return a.name < b.name
end

-- Returns { recipes = { recipe, ... }, profs = { { name, count }, ... } }.
-- recipe = { id, name, output, reagents, profName, hasCD, crafters, online, ready }
function Catalog:Build()
    local db = CB.db
    local now = time()
    local me = CB:PlayerFullName()
    local byRecipe, profCount = {}, {}
    self.ownNames = {}

    local function addChar(name, class, own, profs)
        for _, prof in pairs(profs) do
            for _, rid in ipairs(prof.recipes or {}) do
                local r = byRecipe[rid]
                if not r then
                    local meta = resolveLocal(rid) or db.recipes[rid] or {}
                    r = {
                        id = rid, name = meta.n or ("Recipe " .. rid), output = meta.o, reagents = meta.r, icon = meta.i,
                        profName = prof.name, hasCD = meta.cdr and true or false, crafters = {}, has = {},
                    }
                    byRecipe[rid] = r
                end
                if not r.has[name] then
                    r.has[name] = true
                    local info = roster[name]
                    local online = own and name == me or (info and info.online) or false
                    local expires = prof.cd and prof.cd[rid]
                    local left = expires and expires > now and expires - now or nil
                    r.crafters[#r.crafters + 1] = {
                        name = name, class = class or (info and info.class), own = own, online = online,
                        ago = info and info.ago, cdLeft = left, ready = left == nil,
                    }
                end
            end
        end
    end

    for _, rec in pairs(db.chars) do
        if rec.name then
            self.ownNames[rec.name] = true
            addChar(rec.name, rec.class, true, rec.profs or {})
        end
    end
    for name, rec in pairs(db.guild or {}) do
        if not self.ownNames[name] then addChar(name, rec.class, false, rec.profs or {}) end
    end

    local recipes = {}
    for _, r in pairs(byRecipe) do
        r.has = nil
        table.sort(r.crafters, compareCrafters)
        r.online, r.ready = 0, 0
        for _, c in ipairs(r.crafters) do
            if c.online then r.online = r.online + 1 end
            if c.ready and c.online then r.ready = r.ready + 1 end
        end
        recipes[#recipes + 1] = r
        profCount[r.profName] = (profCount[r.profName] or 0) + 1
    end
    table.sort(recipes, function(a, b)
        if a.online ~= b.online then return a.online > b.online end
        return a.name < b.name
    end)

    local profs = {}
    for name, count in pairs(profCount) do profs[#profs + 1] = { name = name, count = count } end
    table.sort(profs, function(a, b) return a.name < b.name end)
    return { recipes = recipes, profs = profs }
end

-- Item name for a reagent/output, or nil until the client has it (then a refresh is asked for).
function Catalog:ItemName(itemID)
    if not itemID then return nil end
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    return name
end

function Catalog:ItemIcon(itemID)
    if not itemID then return nil end
    return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
end

-- A clickable item link, or nil until the item's name is known. Uses the client's own link when
-- it has one, otherwise builds a plain one (quality colored).
function Catalog:ItemLink(itemID)
    local name = self:ItemName(itemID)
    if not name then return nil end
    if C_Item and C_Item.GetItemInfo then
        local ok, _, link = pcall(C_Item.GetItemInfo, itemID)
        if ok and type(link) == "string" then return link end
    end
    local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID) or 1
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    local hex = color and color.hex or "|cffffffff"
    return ("%s|Hitem:%d::::::::|h[%s]|h|r"):format(hex, itemID, name)
end

-- How many of an item you own (bags and bank), or nil if the client cannot say.
function Catalog:ItemCount(itemID)
    if not (C_Item and C_Item.GetItemCount) then return nil end
    local ok, count = pcall(C_Item.GetItemCount, itemID, true)
    return ok and tonumber(count) or nil
end

function Catalog.FormatDuration(seconds)
    if seconds >= 86400 then return ("%dd %dh"):format(seconds / 86400, (seconds % 86400) / 3600) end
    if seconds >= 3600 then return ("%dh %dm"):format(seconds / 3600, (seconds % 3600) / 60) end
    return ("%dm"):format(max(1, seconds / 60))
end
