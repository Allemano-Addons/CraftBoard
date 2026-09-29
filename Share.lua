-- Share: step 2. Recipes are shared between guild members with addon messages
-- (prefix "CraftBoard", at most 255 bytes each). Only recipe IDs travel; names, output and
-- reagents are asked for separately, once, and cached.
--
-- Messages (fields split by "|", lists by ","):
--   H|hash                        hello: a fingerprint of my recipes (GUILD at login, or WHISPER as answer to A)
--   A                             ask everyone to tell me their fingerprint (GUILD at login)
--   Q                             (WHISPER) send me all your data
--   P|sid|class|prof|skill|max|name|i|n|id,id,...   one chunk of a profession's recipes
--   D|sid|prof|id:secondsLeft,...                    cooldowns of that profession
--   E|hash                        end of a full send: this is my fingerprint now
--   N|id,id,...                   (WHISPER) tell me what these recipes are
--   M|id|output|name|item:qty,...  answer to N
--
-- Received data: CraftBoardDB.guild[fullName] = { class, hash, t, profs = { [profID] = {
--   name, skill, max, recipes = {...}, cd = { [recipeID] = expiresAt }, sid, t } } }
-- The catalog (Catalog.lua) reads that table next to your own characters.
local _, CB = ...

local Share = {}
CB.Share = Share

local PREFIX = "CraftBoard"
local MAX_BYTES = 250           -- Forever silently cuts at 255
local SEND_INTERVAL = 0.35      -- ~3 messages/s, under the chat throttle
local ASK_COOLDOWN = 600        -- seconds between login asks
local MAX_RECIPES_PER_PROF = 3000
local META_BATCH = 25
local META_MAX = 400            -- recipes asked for per full receive

local me -- full name, set at login

local function settings() return CB.db.settings end
local function sharingOn() return settings().share ~= false end

-- ---------------------------------------------------------------------------
-- Sending: one queue, paced.
-- ---------------------------------------------------------------------------

local queue, pumping = {}, false

local function pump()
    local item = tremove(queue, 1)
    if not item then pumping = false return end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.text, item.channel, item.target)
    end
    C_Timer.After(SEND_INTERVAL, pump)
end

local function enqueue(channel, target, text)
    if #text > 255 then CB:Print("|cffe8a33dshare: message too long, dropped|r") return end
    if target == "Test Peer" then return end -- the fake member of /cb selftest
    queue[#queue + 1] = { channel = channel, target = target, text = text }
    if not pumping then
        pumping = true
        C_Timer.After(0, pump)
    end
end

-- ---------------------------------------------------------------------------
-- Encoding
-- ---------------------------------------------------------------------------

local function clean(s) return (tostring(s or ""):gsub("[|,:]", ""):sub(1, 30)) end

local function sortedIDs(recipes)
    local ids = { unpack(recipes) }
    table.sort(ids)
    return ids
end

-- A fingerprint of the recipe IDs of a { [profID] = prof } table (same on both ends).
function Share.Hash(profs)
    local pids = {}
    for pid in pairs(profs) do pids[#pids + 1] = pid end
    table.sort(pids)
    local h = 5381
    for _, pid in ipairs(pids) do
        h = (h * 33 + pid) % 2147483647
        for _, id in ipairs(sortedIDs(profs[pid].recipes or {})) do h = (h * 33 + id) % 2147483647 end
    end
    return h
end

-- Fingerprint of ids + cooldown expiry (rounded to minutes): what changed since the last broadcast.
local function signature(prof)
    local h = 7
    for _, id in ipairs(sortedIDs(prof.recipes or {})) do h = (h * 33 + id) % 2147483647 end
    local cds = {}
    for id, at in pairs(prof.cd or {}) do cds[#cds + 1] = id * 100000 + floor(at / 60) % 100000 end
    table.sort(cds)
    for _, v in ipairs(cds) do h = (h * 33 + v) % 2147483647 end
    return h
end

-- The messages for one profession: P chunks, then D if it has cooldowns.
function Share.EncodeProfession(class, profID, prof)
    local sid = math.random(1, 1073741823)
    local base = ("P|%d|%s|%d|%d|%d|%s|"):format(sid, clean(class), profID, prof.skill or 0, prof.max or 0, clean(prof.name))
    local budget = MAX_BYTES - #base - 8 -- room for "i|n|"
    local chunks, current = {}, {}
    local size = 0
    for _, id in ipairs(sortedIDs(prof.recipes or {})) do
        local s = tostring(id)
        if size + #s + 1 > budget and #current > 0 then
            chunks[#chunks + 1] = table.concat(current, ",")
            current, size = {}, 0
        end
        current[#current + 1] = s
        size = size + #s + 1
    end
    chunks[#chunks + 1] = table.concat(current, ",")
    local out = {}
    for i, chunk in ipairs(chunks) do out[#out + 1] = ("%s%d|%d|%s"):format(base, i, #chunks, chunk) end

    local cds, line = {}, {}
    local now = time()
    for id, at in pairs(prof.cd or {}) do
        if at > now then cds[#cds + 1] = ("%d:%d"):format(id, at - now) end
    end
    local prefix = ("D|%d|%d|"):format(sid, profID)
    for _, c in ipairs(cds) do
        if #prefix + #table.concat(line, ",") + #c + 1 > MAX_BYTES then
            out[#out + 1] = prefix .. table.concat(line, ",")
            line = {}
        end
        line[#line + 1] = c
    end
    if #line > 0 then out[#out + 1] = prefix .. table.concat(line, ",") end
    return out
end

local function ownRecord()
    return CB.db.chars[UnitGUID("player")]
end

local function sendProfessions(channel, target, pids)
    local rec = ownRecord()
    if not rec then return end
    for _, pid in ipairs(pids) do
        local prof = rec.profs[pid]
        if prof then
            for _, text in ipairs(Share.EncodeProfession(rec.class, pid, prof)) do enqueue(channel, target, text) end
        end
    end
    enqueue(channel, target, "E|" .. Share.Hash(rec.profs))
end

local function allProfessionIDs(rec)
    local pids = {}
    for pid in pairs(rec.profs) do pids[#pids + 1] = pid end
    table.sort(pids)
    return pids
end

-- ---------------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------------

local pending = {}          -- sender:profID -> chunks being collected
local askedFrom = {}        -- sender -> time we asked for their data (this session)
local sentTo = {}           -- sender -> time we sent our data to them
local handlers = {}

local function num(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= floor(v) or v < lo or v > hi then return nil end
    return v
end

local function guildRecord(sender, class)
    local g = CB.db.guild
    local rec = g[sender]
    if not rec then
        rec = { profs = {} }
        g[sender] = rec
    end
    if class and class ~= "" then rec.class = class end
    return rec
end

local function requestMeta(sender, rec)
    local unknown, seen = {}, {}
    for _, prof in pairs(rec.profs) do
        for _, id in ipairs(prof.recipes) do
            local meta = CB.db.recipes[id]
            if not (meta and meta.n and meta.r) and not seen[id] then
                seen[id] = true
                unknown[#unknown + 1] = id
                if #unknown >= META_MAX then break end
            end
        end
    end
    for i = 1, #unknown, META_BATCH do
        enqueue("WHISPER", sender, "N|" .. table.concat(unknown, ",", i, min(i + META_BATCH - 1, #unknown)))
    end
end

function handlers.A(sender)
    if not sharingOn() then return end
    local rec = ownRecord()
    if not rec or not next(rec.profs) then return end
    C_Timer.After(1 + math.random() * 11, function()
        enqueue("WHISPER", sender, "H|" .. Share.Hash(rec.profs))
    end)
end

function handlers.H(sender, _, hash)
    hash = num(hash, 0, 2147483647)
    if not hash then return end
    local rec = CB.db.guild[sender]
    if rec and rec.hash == hash then return end
    if askedFrom[sender] and time() - askedFrom[sender] < ASK_COOLDOWN then return end
    askedFrom[sender] = time()
    C_Timer.After(0.5 + math.random() * 4, function() enqueue("WHISPER", sender, "Q") end)
end

function handlers.Q(sender)
    if not sharingOn() then return end
    if sentTo[sender] and time() - sentTo[sender] < 120 then return end
    sentTo[sender] = time()
    local rec = ownRecord()
    if rec then sendProfessions("WHISPER", sender, allProfessionIDs(rec)) end
end

function handlers.P(sender, _, sid, class, pid, skill, max, pname, i, n, ids)
    sid, pid, i, n = num(sid, 1, 2147483647), num(pid, 1, 1000000), num(i, 1, 200), num(n, 1, 200)
    skill, max = num(skill, 0, 1000), num(max, 0, 1000)
    if not (sid and pid and i and n and skill and max and i <= n) then return end
    local key = sender .. ":" .. pid
    local p = pending[key]
    if not p or p.sid ~= sid then
        p = { sid = sid, n = n, got = 0, chunks = {} }
        pending[key] = p
    end
    if not p.chunks[i] then
        p.chunks[i] = ids or ""
        p.got = p.got + 1
    end
    if p.got < p.n then return end
    pending[key] = nil

    local recipes = {}
    for c = 1, p.n do
        for id in (p.chunks[c] or ""):gmatch("%d+") do
            id = tonumber(id)
            if id and id > 0 and id < 2147483647 and #recipes < MAX_RECIPES_PER_PROF then recipes[#recipes + 1] = id end
        end
    end
    local rec = guildRecord(sender, class:match("^%u+$") and class or nil)
    rec.profs[pid] = { name = clean(pname), skill = skill, max = max, recipes = recipes, cd = {}, sid = sid, t = time() }
    rec.t = time()
end

function handlers.D(sender, _, sid, pid, list)
    sid, pid = num(sid, 1, 2147483647), num(pid, 1, 1000000)
    local rec = CB.db.guild[sender]
    local prof = rec and pid and rec.profs[pid]
    if not (sid and prof and prof.sid == sid) then return end
    local now = time()
    for id, left in (list or ""):gmatch("(%d+):(%d+)") do
        id, left = tonumber(id), tonumber(left)
        if id and left and left > 0 and left < 86400 * 400 then prof.cd[id] = now + left end
    end
end

function handlers.E(sender, _, hash)
    hash = num(hash, 0, 2147483647)
    local rec = CB.db.guild[sender]
    if not (hash and rec) then return end
    rec.hash = hash
    CB.syncedAt = time()
    requestMeta(sender, rec)
    if CB.Window and CB.Window.Changed then CB.Window.Changed() end
end

function handlers.N(sender, _, list)
    if not sharingOn() then return end
    local count = 0
    for id in (list or ""):gmatch("%d+") do
        id = tonumber(id)
        local meta = id and CB.db.recipes[id]
        if meta and meta.n and count < META_BATCH then
            count = count + 1
            local r = {}
            for k = 1, #(meta.r or {}), 2 do r[#r + 1] = meta.r[k] .. ":" .. meta.r[k + 1] end
            enqueue("WHISPER", sender, ("M|%d|%d|%s|%s"):format(id, meta.o or 0, clean(meta.n):sub(1, 40), table.concat(r, ",")))
        end
    end
end

function handlers.M(_, _, id, output, name, reagents)
    id, output = num(id, 1, 2147483647), num(output, 0, 2147483647)
    if not (id and output and name and name ~= "") then return end
    local meta = CB.db.recipes[id] or {}
    CB.db.recipes[id] = meta
    meta.n = meta.n or name:sub(1, 60)
    if output > 0 then meta.o = meta.o or output end
    if not meta.r then
        local r = {}
        for item, qty in (reagents or ""):gmatch("(%d+):(%d+)") do
            item, qty = tonumber(item), tonumber(qty)
            if item and qty and qty > 0 and qty < 1000 then r[#r + 1] = item r[#r + 1] = qty end
        end
        meta.r = r
    end
    if CB.Window and CB.Window.Changed then CB.Window.Changed() end
end

local function normalize(sender)
    if type(Ambiguate) == "function" then
        local ok, name = pcall(Ambiguate, sender, "none")
        if ok and name then return name end
    end
    return sender
end

local rosterAt = 0
local function inGuild(name)
    if time() - rosterAt > 30 then
        rosterAt = time()
        CB.Catalog:RefreshRoster()
    end
    return CB.Catalog:RosterInfo(name) ~= nil
end

-- text as received; allowAny skips the "must be in my guild" check (self test only).
function Share.Receive(text, channel, sender, allowAny)
    if type(text) ~= "string" or #text > 255 then return end
    sender = normalize(sender or "")
    if sender == "" or (sender == me and not allowAny) then return end
    if not allowAny and not inGuild(sender) then return end
    local fields = { strsplit("|", text) }
    local handler = handlers[fields[1]]
    if handler then handler(sender, channel, unpack(fields, 2)) end
end

CB:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
    if prefix ~= PREFIX or not CB.db then return end
    Share.Receive(text, channel, sender)
end)

-- ---------------------------------------------------------------------------
-- Sending triggers
-- ---------------------------------------------------------------------------

-- Ask the guild for fingerprints (and tell them mine). force skips the cooldown.
function Share.Ask(force)
    if not IsInGuild() then return false end
    local db = CB.db
    local now = time()
    if not force and db.lastAsk and now - db.lastAsk < ASK_COOLDOWN then return false end
    db.lastAsk = now
    local rec = ownRecord()
    if rec and next(rec.profs) and sharingOn() then enqueue("GUILD", nil, "H|" .. Share.Hash(rec.profs)) end
    enqueue("GUILD", nil, "A")
    return true
end

-- Something changed in my recipes: broadcast the professions whose signature changed.
local changeTimer = false
local function broadcastChanges()
    changeTimer = false
    if not sharingOn() or not IsInGuild() then return end
    local rec = ownRecord()
    if not rec then return end
    local db = CB.db
    local guid = UnitGUID("player")
    db.sentSig = db.sentSig or {}
    db.sentSig[guid] = db.sentSig[guid] or {}
    local changed = {}
    for pid, prof in pairs(rec.profs) do
        local sig = signature(prof)
        if db.sentSig[guid][pid] ~= sig then
            db.sentSig[guid][pid] = sig
            changed[#changed + 1] = pid
        end
    end
    if #changed == 0 then return end
    table.sort(changed)
    sendProfessions("GUILD", nil, changed)
end

local previous = CB.OnRecipesChanged
function CB:OnRecipesChanged(rec)
    if previous then previous(self, rec) end
    if changeTimer then return end
    changeTimer = true
    C_Timer.After(5, function() CB:Call("share broadcast", broadcastChanges) end)
end

-- A guild switch invalidates what we collected.
local function checkGuild()
    local name = GetGuildInfo and GetGuildInfo("player")
    if not name then return end
    if CB.db.guildName and CB.db.guildName ~= name then
        wipe(CB.db.guild)
        CB:Print("New guild: cleared the recipes collected from the old one.")
    end
    CB.db.guildName = name
end

CB:RegisterEvent("PLAYER_LOGIN", function()
    me = CB:PlayerFullName()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    C_Timer.After(12, function() -- guild info and roster are ready by now
        CB:Call("share hello", function()
            checkGuild()
            Share.Ask(false)
        end)
    end)
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

CB:AddSlashCommand("share", function(arg)
    arg = strlower(arg or "")
    if arg == "on" or arg == "off" then
        settings().share = arg == "on"
        CB:Print("Sharing your recipes with the guild: " .. arg)
    else
        CB:Print("Sharing your recipes: " .. (sharingOn() and "on" or "off") .. " (/cb share on|off)")
    end
end, "share your recipes with the guild on/off")

CB:AddSlashCommand("sync", function()
    if Share.Ask(true) then CB:Print("Asked the guild for recipes.") else CB:Print("You are not in a guild.") end
end, "ask the guild for recipes now")

-- /cb selftest: run my own data through the encoder and decoder as if "Test Peer" sent it.
CB:AddSlashCommand("selftest", function(arg)
    if strlower(arg or "") == "clear" then
        CB.db.guild["Test Peer"] = nil
        CB:Print("Test Peer removed.")
        return
    end
    local rec = ownRecord()
    if not rec or not next(rec.profs) then CB:Print("Open a profession window first.") return end
    local profs = {}
    for pid, prof in pairs(rec.profs) do
        -- Pretend the peer has these recipes, with one fake cooldown so D is exercised.
        local copy = { name = prof.name, skill = prof.skill, max = prof.max, recipes = prof.recipes, cd = {} }
        if prof.recipes[1] then copy.cd[prof.recipes[1]] = time() + 7200 end
        profs[pid] = copy
    end
    local count, longest = 0, 0
    local pids = {}
    for pid in pairs(profs) do pids[#pids + 1] = pid end
    table.sort(pids)
    for _, pid in ipairs(pids) do
        for _, text in ipairs(Share.EncodeProfession("MAGE", pid, profs[pid])) do
            count = count + 1
            longest = max(longest, #text)
            Share.Receive(text, "WHISPER", "Test Peer", true)
        end
    end
    Share.Receive("E|" .. Share.Hash(profs), "WHISPER", "Test Peer", true)
    local got = CB.db.guild["Test Peer"]
    local recipes = 0
    for _, prof in pairs(got and got.profs or {}) do recipes = recipes + #prof.recipes end
    CB:Print(("Self test: %d messages (longest %d bytes), Test Peer now has %d recipes. /cb selftest clear removes it."):format(count, longest, recipes))
    if CB.Window and CB.Window.Changed then CB.Window.Changed() end
end, "test sharing with a fake guild member built from your own recipes")

