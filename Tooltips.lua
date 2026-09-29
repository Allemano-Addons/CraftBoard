-- Tooltips: a "Craftable by" line on item tooltips, from the same catalog the window uses.
-- Item -> crafters is looked up in an index that is rebuilt at most every few seconds.
local _, CB = ...

local Theme, Catalog = CB.Theme, CB.Catalog

local MAX_NAMES = 6
local INDEX_TTL = 15 -- seconds

local index, builtAt

local function compare(a, b)
    if a.online ~= b.online then return a.online end
    return a.name < b.name
end

local function buildIndex()
    local now = GetTime()
    if index and now - builtAt < INDEX_TTL then return index end
    Catalog:RefreshRoster()
    index = {}
    for _, recipe in ipairs(Catalog:Build().recipes) do
        if recipe.output then
            local entry = index[recipe.output]
            if not entry then
                entry = { list = {}, seen = {} }
                index[recipe.output] = entry
            end
            for _, c in ipairs(recipe.crafters) do
                if not entry.seen[c.name] then
                    entry.seen[c.name] = true
                    entry.list[#entry.list + 1] = c
                end
            end
        end
    end
    for _, entry in pairs(index) do table.sort(entry.list, compare) end
    builtAt = now
    return index
end

local function colorCode(r, g, b)
    return ("|cff%02x%02x%02x"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

-- "|cff...Name|r, ..." online members in their class color, offline ones dimmed.
local function namesText(list, includeOffline)
    local parts, shown, total = {}, 0, 0
    for _, c in ipairs(list) do
        if c.online or includeOffline then
            total = total + 1
            if shown < MAX_NAMES then
                shown = shown + 1
                local code = c.online and colorCode(Theme.ClassColor(c.class)) or "|cff6e757e"
                parts[shown] = code .. c.name .. "|r"
            end
        end
    end
    if total == 0 then return nil end
    local text = table.concat(parts, ", ")
    if total > shown then text = text .. (" |cff9098a1+%d more|r"):format(total - shown) end
    return text
end

local function itemIDOf(tooltip, data)
    if data and tonumber(data.id) then return tonumber(data.id) end
    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    if ok and type(link) == "string" then return tonumber(link:match("item:(%d+)")) end
end

local function addLine(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local s = CB.db and CB.db.settings
    if not s or s.tooltip == false then return end
    local itemID = itemIDOf(tooltip, data)
    local entry = itemID and buildIndex()[itemID]
    if not entry then return end
    local text = namesText(entry.list, s.tooltipOffline ~= false)
    if not text then return end
    tooltip:AddLine(("|cff%sCraftable by:|r %s"):format(Theme:AccentHex(), text), 1, 1, 1, true)
    return true
end

local function hook()
    if type(TooltipDataProcessor) == "table" and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        local ok = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip, data)
            CB:Call("tooltip line", addLine, tooltip, data)
        end)
        if ok then return end
    end
    -- Older clients: the line is added after the tooltip is built, so it has to be resized.
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tip and tip.HookScript then
            pcall(tip.HookScript, tip, "OnTooltipSetItem", function(t)
                CB:Call("tooltip line", function()
                    if addLine(t) then t:Show() end
                end)
            end)
        end
    end
end

CB:RegisterEvent("PLAYER_LOGIN", function() CB:Call("tooltip hook", hook) end)

-- New data (a snapshot, a share) should show up without waiting for the timer.
CB:OnSettingChanged(function(key)
    if key == "tooltipOffline" then index = nil end
end)
function CB.InvalidateTooltips() index = nil end
