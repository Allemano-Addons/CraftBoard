-- CraftBoard: core namespace, event dispatcher, SavedVariables and slash command.
-- Standalone: never requires Hush or AltBoard.
local addonName, CB = ...

CB.name = addonName
CB.SCHEMA = 1
CB.COLOR = "F0763A" -- CraftBoard orange (the Allemano mark)

function CB:Print(...)
    local msg = strjoin(" ", tostringall(...))
    DEFAULT_CHAT_FRAME:AddMessage("|cfff0763aCraftBoard|r " .. msg)
end

-- ---------------------------------------------------------------------------
-- Errors: WoW Forever does not show Lua errors, so they are kept (last 10, also in
-- CraftBoardDB.errors), announced once per session and listed by /cb errors.
-- ---------------------------------------------------------------------------

CB.errors = {}
local announced = false

function CB:RecordError(where, err)
    local list = self.errors
    list[#list + 1] = { t = time(), where = tostring(where), msg = tostring(err):sub(1, 400), v = self.version }
    while #list > 10 do tremove(list, 1) end
    if not announced then
        announced = true
        self:Print("|cffe8a33dhit an error|r (" .. tostring(where) .. "). /cb errors shows it.")
    end
    geterrorhandler()(err)
end

-- Run fn protected; errors are recorded instead of lost.
function CB:Call(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then self:RecordError(where, err) end
    return ok
end

-- ---------------------------------------------------------------------------
-- Game events: several handlers per event, one shared frame. Each handler runs
-- protected so one failing part never stops the others.
-- ---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

-- Returns false if the client does not know the event.
function CB:RegisterEvent(event, handler)
    local list = eventHandlers[event]
    if not list then
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
        list = {}
        eventHandlers[event] = list
    end
    list[#list + 1] = handler
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    local snapshot = { unpack(list, 1, #list) }
    for i = 1, #snapshot do
        local ok, err = pcall(snapshot[i], event, ...)
        if not ok then CB:RecordError(event, err) end
    end
end)

-- ---------------------------------------------------------------------------
-- SavedVariables: read at ADDON_LOADED, never at file load (WoW Forever quirk).
-- ---------------------------------------------------------------------------

local function initDB()
    if type(CraftBoardDB) ~= "table" then CraftBoardDB = {} end
    local db = CraftBoardDB
    db.schema = db.schema or CB.SCHEMA
    db.settings = db.settings or {}
    db.probe = db.probe or {}
    db.chars = db.chars or {}
    db.recipes = db.recipes or {}
    -- Errors from before the saved data was loaded are kept too.
    db.errors = db.errors or {}
    for _, e in ipairs(CB.errors) do tinsert(db.errors, e) end
    while #db.errors > 10 do tremove(db.errors, 1) end
    CB.errors = db.errors
    CB.db = db
end

local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

CB:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= addonName then return end
    initDB()
    CB.version = getMetadata and getMetadata(addonName, "Version") or "?"
end)

CB:RegisterEvent("PLAYER_LOGIN", function()
    CB.guid = UnitGUID("player")
    CB.ready = true
end)

-- ---------------------------------------------------------------------------
-- Slash command: other files add subcommands with CB:AddSlashCommand.
-- ---------------------------------------------------------------------------

local slashCommands, slashOrder = {}, {}

function CB:AddSlashCommand(name, fn, help)
    if not slashCommands[name] then slashOrder[#slashOrder + 1] = name end
    slashCommands[name] = { fn = fn, help = help }
end

CB:AddSlashCommand("version", function() CB:Print("v" .. tostring(CB.version)) end, "show version")

CB:AddSlashCommand("errors", function(arg)
    if strlower(arg or "") == "clear" then
        wipe(CB.errors)
        CB:Print("Error list cleared.")
        return
    end
    if #CB.errors == 0 then CB:Print("No errors recorded.") return end
    for _, e in ipairs(CB.errors) do
        CB:Print(("[%s] %s (v%s): %s"):format(date("%d/%m %H:%M", e.t), e.where, tostring(e.v), e.msg))
    end
end, "show recent errors (/cb errors clear empties the list)")

SLASH_CRAFTBOARD1 = "/craftboard"
SLASH_CRAFTBOARD2 = "/cb"
SlashCmdList.CRAFTBOARD = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = strlower(cmd or "")
    if cmd == "" and slashCommands.open then cmd = "open" end
    local c = slashCommands[cmd]
    if c then
        local ok, err = pcall(c.fn, rest)
        if not ok then CB:RecordError("/cb " .. cmd, err) end
    else
        CB:Print("CraftBoard v" .. tostring(CB.version) .. " (step 3: window; /cb opens it)")
        for _, name in ipairs(slashOrder) do
            CB:Print(("/cb %s - %s"):format(name, slashCommands[name].help or ""))
        end
    end
end
