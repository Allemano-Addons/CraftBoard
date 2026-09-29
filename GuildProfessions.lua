-- GuildProfessions: step 1b. Blizzard's guild profession list (GetGuildTradeSkillInfo) is
-- readable on Forever: one header row per profession with member counts. This tests whether
-- expanding a header lists the members and their skill, i.e. who crafts without the addon.
--
-- Row layout (Cataclysm): skillID, isCollapsed, icon, headerName, numOnline, numVisible,
-- numPlayers, playerName, playerFullName, class, online, zone, skill, classFile, isMobile, isLeader.
local _, CB = ...

local function rowCount()
    local ok, n = pcall(_G.GetNumGuildTradeSkill)
    return ok and tonumber(n) or 0
end

local function readRows()
    local rows = {}
    for i = 1, rowCount() do
        local ok, skillID, collapsed, _, header, online, visible, players, name, fullName, class, isOnline, zone, skill =
            pcall(_G.GetGuildTradeSkillInfo, i)
        if ok then
            rows[i] = {
                skillID = skillID, collapsed = collapsed, header = header, online = online, visible = visible,
                players = players, name = name, fullName = fullName, class = class, isOnline = isOnline,
                zone = zone, skill = skill,
            }
        end
    end
    return rows
end

-- Only the headers: { id, name, total, online } per profession.
local function headers()
    local list = {}
    for _, row in ipairs(readRows()) do
        if row.header then
            list[#list + 1] = { id = row.skillID, name = row.header, total = tonumber(row.players) or 0, online = tonumber(row.online) or 0 }
        end
    end
    return list
end
CB.GuildProfessionHeaders = headers

local function saveHeaders()
    if not CB.db or type(_G.GetNumGuildTradeSkill) ~= "function" then return end
    CB.db.guildProf = CB.db.guildProf or {}
    CB.db.guildProf.headers = headers()
    CB.db.guildProf.t = time()
end

CB:RegisterEvent("GUILD_TRADESKILL_UPDATE", function() saveHeaders() end)
CB:RegisterEvent("PLAYER_LOGIN", function() C_Timer.After(5, function() CB:Call("guild professions", saveHeaders) end) end)

-- /cb guildprof: expand every header, record what shows up, collapse again.
CB:AddSlashCommand("guildprof", function()
    if type(_G.GetNumGuildTradeSkill) ~= "function" then CB:Print("This client has no guild profession list.") return end
    local before = readRows()
    local expandCalls = {}
    for _, row in ipairs(before) do
        if row.header and row.collapsed then
            local ok, err = pcall(_G.ExpandGuildTradeSkillHeader, row.skillID)
            expandCalls[#expandCalls + 1] = { header = row.header, arg = "skillID", ok = ok, err = not ok and tostring(err) or nil }
        end
    end
    local after = readRows()
    if #after == #before and #before > 0 then
        -- Nothing appeared: maybe the argument is the row index instead of the skill ID.
        for i, row in ipairs(before) do
            if row.header and row.collapsed then
                local ok, err = pcall(_G.ExpandGuildTradeSkillHeader, i)
                expandCalls[#expandCalls + 1] = { header = row.header, arg = "index " .. i, ok = ok, err = not ok and tostring(err) or nil }
            end
        end
        after = readRows()
    end

    local members = 0
    for _, row in ipairs(after) do if row.name then members = members + 1 end end
    CB.db.guildProf = CB.db.guildProf or {}
    CB.db.guildProf.test = {
        t = time(), rowsBefore = #before, rowsAfter = #after, members = members,
        calls = expandCalls, sample = { unpack(after, 1, 25) },
        collapseApi = type(_G.CollapseGuildTradeSkillHeader),
    }
    CB:Print(("Guild professions: %d rows before, %d after expanding, %d of them members."):format(#before, #after, members))

    -- Put the list back the way it was.
    if type(_G.CollapseGuildTradeSkillHeader) == "function" then
        for _, row in ipairs(before) do
            if row.header and row.collapsed then pcall(_G.CollapseGuildTradeSkillHeader, row.skillID) end
        end
    end
end, "test reading guild members per profession (Blizzard's list)")
