-- Window: the CraftBoard guild crafting directory. Left: professions. Middle: recipe search
-- and list. Right: the selected recipe with reagents and who can craft it.
local _, CB = ...

local Theme, W, Catalog = CB.Theme, CB.W, CB.Catalog
local Window = {}
CB.Window = Window

local WIDTH, HEIGHT = 1060, 640
local TITLE_H, SIDE_W, DETAIL_W = 46, 214, 300
local RECIPE_ROW, CRAFTER_ROW, PROF_ROW = 46, 58, 30
local MAX_REAGENTS = 8
local REAGENT_ROW = 28

local frame
local state = { prof = nil, search = "", onlineOnly = false, selected = nil }
local data, view = { recipes = {}, profs = {} }, {}

local function sectionLabel(parent, text)
    local fs = W.Text(parent, -2, "textFaint")
    fs:SetText(strupper(text))
    return fs
end

local function itemLabel(itemID)
    return Catalog:ItemName(itemID) or ("item " .. tostring(itemID))
end

-- ---------------------------------------------------------------------------
-- Filtering
-- ---------------------------------------------------------------------------

local function matches(recipe, needle)
    if needle == "" then return true end
    if strfind(strlower(recipe.name), needle, 1, true) then return true end
    local r = recipe.reagents
    if r then
        for i = 1, #r, 2 do
            local n = Catalog:ItemName(r[i])
            if n and strfind(strlower(n), needle, 1, true) then return true end
        end
    end
    return false
end

local function applyFilter()
    wipe(view)
    local needle = strlower(strtrim(state.search or ""))
    for _, r in ipairs(data.recipes) do
        if (not state.prof or r.profName == state.prof)
            and (not state.onlineOnly or r.online > 0)
            and matches(r, needle) then
            view[#view + 1] = r
        end
    end
end

local function selectedRecipe()
    for _, r in ipairs(view) do if r.id == state.selected then return r end end
end

-- ---------------------------------------------------------------------------
-- Detail (right)
-- ---------------------------------------------------------------------------

local function whisper(name)
    if Hush and Hush.OpenWhisper then
        Hush.OpenWhisper(name)
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat("/w " .. name .. " ")
    end
end

local function mail(name)
    if MailFrame and MailFrame:IsShown() and SendMailNameEditBox then
        if MailFrameTab_OnClick then MailFrameTab_OnClick(MailFrame, 2) end
        SendMailNameEditBox:SetText(name)
    else
        CB:Print("Open a mailbox to send mail to " .. name .. ".")
    end
end

local function crafterStatus(c, recipe)
    local parts = {}
    if c.online then
        parts[1] = "Online"
    elseif c.own then
        parts[1] = "Offline"
    elseif c.ago then
        parts[1] = "Last seen " .. Catalog.FormatDuration(c.ago)
    else
        parts[1] = "Offline"
    end
    if c.own then parts[1] = (c.name == CB:PlayerFullName() and "You" or "Your alt") .. " · " .. parts[1] end
    local text = table.concat(parts, " ")
    if recipe.hasCD then
        if c.cdLeft then
            return text .. " · |cff" .. Theme:AccentHex() .. "Cooldown " .. Catalog.FormatDuration(c.cdLeft) .. " left|r"
        end
        return text .. " · |cff" .. Theme:AccentHex() .. "Cooldown ready|r"
    end
    return text
end

local function createCrafterRow(list)
    local row = CreateFrame("Frame", nil, list)
    local card = CreateFrame("Frame", nil, row)
    card:SetPoint("TOPLEFT", 0, -2)
    card:SetPoint("BOTTOMRIGHT", -6, 2)
    W.Surface(card, "field", 1, Theme.radius.control)
    row.dot = card:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(8, 8)
    row.dot:SetPoint("LEFT", 12, 0)
    W.Round(row.dot, 4)
    row.name = W.Text(card, 2, "text")
    row.name:SetPoint("TOPLEFT", 28, -13)
    row.sub = W.Text(card, -1, "textDim")
    row.sub:SetPoint("BOTTOMLEFT", 28, 13)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -104, 0)
    row.button = W.Button(row, "Whisper", "accent", nil, "whisper")
    row.button:SetPoint("RIGHT", -12, 0)
    return row
end

local function updateCrafterRow(row, c)
    local recipe = selectedRecipe()
    row.name:SetText(c.name)
    row.name:SetTextColor(Theme.ClassColor(c.class))
    row.sub:SetText(recipe and crafterStatus(c, recipe) or "")
    if c.online then row.dot:SetColorTexture(Theme:Color("good")) else row.dot:SetColorTexture(Theme:Color("textFaint")) end
    if c.own then
        row.button:Hide()
    else
        row.button:Show()
        if c.online then
            row.button:Configure("Whisper", "accent", "whisper")
            row.button:SetScript("OnClick", function() whisper(c.name) end)
        else
            row.button:Configure("Mail", "plain", "mail")
            row.button:SetScript("OnClick", function() mail(c.name) end)
        end
    end
end

-- Reagent click: shift = link it in chat (or any edit box that has focus), plain = put the
-- name in the Auction House search box when the auction house is open.
local function reagentClick(itemID)
    if not itemID then return end
    local link = Catalog:ItemLink(itemID)
    if IsModifiedClick and IsModifiedClick("CHATLINK") or IsShiftKeyDown() then
        if link then ChatEdit_InsertLink(link) end
        return
    end
    local name = Catalog:ItemName(itemID)
    if name and AuctionFrame and AuctionFrame:IsShown() and BrowseName then
        BrowseName:SetText(name)
        BrowseName:SetFocus()
    elseif link then
        ChatEdit_InsertLink(link)
    end
end

-- Puts every reagent of the selected recipe, with counts, in the chat box (max 250 characters).
local function linkAllReagents()
    local r = selectedRecipe()
    if not (r and r.reagents) then return end
    local parts, length = {}, 0
    for i = 1, #r.reagents, 2 do
        local link = Catalog:ItemLink(r.reagents[i])
        if link then
            local part = ("%dx %s"):format(r.reagents[i + 1], link)
            if length + #part + 2 > 250 then break end
            parts[#parts + 1] = part
            length = length + #part + 2
        end
    end
    if #parts > 0 then ChatEdit_InsertLink(table.concat(parts, ", ")) end
end

local function buildDetail(parent)
    local d = CreateFrame("Frame", nil, parent)
    d:SetWidth(DETAIL_W)
    d:SetPoint("TOPRIGHT", 0, -TITLE_H)
    d:SetPoint("BOTTOMRIGHT")
    W.Line(d, "left", "line")

    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(44, 44)
    d.icon:SetPoint("TOPLEFT", 16, -16)
    d.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    d.iconBg = W.Fill(d, "field", 1, "BACKGROUND")
    d.iconBg:SetAllPoints(d.icon)
    W.Round(d.iconBg, Theme.radius.control)
    d.name = W.Text(d, 4, "text")
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 12, -3)
    d.name:SetPoint("RIGHT", -14, 0)
    d.prof = W.Text(d, -2, "accent")
    d.prof:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -6)

    d.reagentsLabel = sectionLabel(d, "Reagents")
    d.reagentsLabel:SetPoint("TOPLEFT", 16, -84)
    d.reagents = {}
    for i = 1, MAX_REAGENTS do
        local row = CreateFrame("Button", nil, d)
        row:SetHeight(REAGENT_ROW)
        row:SetPoint("TOPLEFT", 10, -100 - (i - 1) * REAGENT_ROW)
        row:SetPoint("TOPRIGHT", -8, -100 - (i - 1) * REAGENT_ROW)
        row.hover = W.Fill(row, "selected", 1)
        row.hover:SetAllPoints()
        W.Round(row.hover, Theme.radius.small)
        row.hover:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 6, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.text = W.Text(row, 1, "text")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetPoint("RIGHT", -74, 0)
        row.qty = W.Text(row, 1, "textDim")
        row.qty:SetPoint("RIGHT", -8, 0)
        row.qty:SetJustifyH("RIGHT")
        row:RegisterForClicks("LeftButtonUp")
        row:SetScript("OnEnter", function(self)
            self.hover:Show()
            if not self.itemID then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetHyperlink("item:" .. self.itemID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Shift-click: link in chat   Click: search the Auction House", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self.hover:Hide()
            GameTooltip:Hide()
        end)
        row:SetScript("OnClick", function(self) reagentClick(self.itemID) end)
        d.reagents[i] = row
    end

    d.linkAll = W.Button(d, "Link all", "plain", function() linkAllReagents() end, "share")
    d.linkAll:SetHeight(22)
    d.linkAll:SetPoint("TOPRIGHT", -12, -78)

    d.craftersLabel = sectionLabel(d, "Crafters")
    d.craftersSort = W.Text(d, -1, "textDim")
    d.craftersSort:SetText("Online first")
    d.craftersSort:SetPoint("TOPRIGHT", -14, -6)

    d.list = W.VirtualList(d, CRAFTER_ROW, createCrafterRow, updateCrafterRow)
    d.list:SetPoint("BOTTOMLEFT", 10, 10)
    d.list:SetPoint("BOTTOMRIGHT", -4, 10)

    d.empty = W.Text(d, 0, "textFaint")
    d.empty:SetPoint("TOP", 0, -140)
    d.empty:SetText("Select a recipe")
    return d
end

local function updateDetail()
    local d = frame.detail
    local r = selectedRecipe()
    d.empty:SetShown(r == nil)
    for _, w in ipairs({ d.icon, d.iconBg, d.name, d.prof, d.reagentsLabel, d.craftersLabel, d.craftersSort, d.list }) do
        w:SetShown(r ~= nil)
    end
    if not r then
        for _, row in ipairs(d.reagents) do row:Hide() end
        d.linkAll:Hide()
        return
    end
    d.icon:SetTexture(Catalog:ItemIcon(r.output) or 134400)
    d.name:SetText(r.name)
    d.prof:SetText(strupper(r.profName or ""))

    local n = r.reagents and min(#r.reagents / 2, MAX_REAGENTS) or 0
    d.linkAll:SetShown(n > 0)
    for i, row in ipairs(d.reagents) do
        if i <= n then
            local itemID, need = r.reagents[i * 2 - 1], r.reagents[i * 2]
            row.itemID = itemID
            row.text:SetText(itemLabel(itemID))
            row.icon:SetTexture(Catalog:ItemIcon(itemID) or 134400)
            -- "x5", green when you already own enough, amber when not.
            local have = Catalog:ItemCount(itemID)
            if have then
                local color = have >= need and "|cff3fc77f" or "|cffe8a33d"
                row.qty:SetText(("%s%d|r|cff6e757e/%d|r"):format(color, have, need))
            else
                row.qty:SetText("x" .. need)
            end
            row:Show()
        else
            row.itemID = nil
            row:Hide()
        end
    end
    local below = 100 + max(n, 1) * REAGENT_ROW
    d.craftersLabel:ClearAllPoints()
    d.craftersLabel:SetPoint("TOPLEFT", 16, -(below + 16))
    d.craftersSort:ClearAllPoints()
    d.craftersSort:SetPoint("TOPRIGHT", d, "TOPRIGHT", -14, -(below + 16))
    d.list:ClearAllPoints()
    d.list:SetPoint("TOPLEFT", 10, -(below + 36))
    d.list:SetPoint("BOTTOMRIGHT", -4, 10)
    d.list:SetData(r.crafters, d.shownRecipe == r.id)
    d.shownRecipe = r.id
end

-- ---------------------------------------------------------------------------
-- Recipe list (middle)
-- ---------------------------------------------------------------------------

local function createRecipeRow(list)
    local row = CreateFrame("Button", nil, list)
    row.bg = W.Fill(row, "selected", 1)
    row.bg:SetPoint("TOPLEFT", 10, -2)
    row.bg:SetPoint("BOTTOMRIGHT", -10, 2)
    W.Round(row.bg, Theme.radius.control)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", 22, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.iconBg = W.Fill(row, "field", 1)
    row.iconBg:SetAllPoints(row.icon)
    W.Round(row.iconBg, Theme.radius.small)
    row.name = W.Text(row, 2, "text")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 1)
    row.name:SetPoint("RIGHT", row, "LEFT", 330, 0)
    row.sub = W.Text(row, -1, "textDim")
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, -1)
    row.crafters = W.Text(row, 1, "text")
    row.crafters:SetPoint("LEFT", row, "LEFT", 340, 0)
    row.cooldown = W.Text(row, 0, "textFaint")
    row.cooldown:SetPoint("LEFT", row, "LEFT", 450, 0)
    row:SetScript("OnClick", function(self)
        state.selected = self.recipeID
        Window:RefreshLists()
    end)
    row:SetScript("OnEnter", function(self)
        if self.recipeID ~= state.selected then self.bg:SetAlpha(0.5) self.bg:Show() end
    end)
    row:SetScript("OnLeave", function(self)
        if self.recipeID ~= state.selected then self.bg:Hide() end
    end)
    return row
end

local function updateRecipeRow(row, r)
    row.recipeID = r.id
    row.icon:SetTexture(Catalog:ItemIcon(r.output) or 134400)
    row.name:SetText(r.name)
    row.sub:SetText(r.profName or "")
    local total = #r.crafters
    if r.online > 0 then
        row.crafters:SetText(("%d · |cff3fc77f%d online|r"):format(total, r.online))
    else
        row.crafters:SetText(("%d · |cff6e757eoffline|r"):format(total))
    end
    if r.hasCD and r.ready > 0 then
        row.cooldown:SetText("|cff" .. Theme:AccentHex() .. "" .. r.ready .. " ready now|r")
    else
        row.cooldown:SetText("|cff6e757e–|r")
    end
    local selected = r.id == state.selected
    row.bg:SetAlpha(1)
    row.bg:SetShown(selected)
end

-- ---------------------------------------------------------------------------
-- Sidebar (left)
-- ---------------------------------------------------------------------------

local function createProfRow(list)
    local row = CreateFrame("Button", nil, list)
    row.bg = W.Fill(row, "selected", 1)
    row.bg:SetPoint("TOPLEFT", 10, -1)
    row.bg:SetPoint("BOTTOMRIGHT", -10, 1)
    W.Round(row.bg, Theme.radius.control)
    row.mark = W.Fill(row, "accent", 1, "ARTWORK")
    row.mark:SetPoint("LEFT", 10, 0)
    row.mark:SetSize(3, 16)
    W.Round(row.mark, 1)
    W.OnAccent(function(r, g, b) row.mark:SetColorTexture(r, g, b, 1) end)
    row.icon = W.Icon(row, "recipe", 16, "textDim")
    row.icon:SetPoint("LEFT", 22, 0)
    row.text = W.Text(row, 1, "textDim")
    row.text:SetPoint("LEFT", 46, 0)
    row.count = W.Text(row, 0, "textFaint")
    row.count:SetPoint("RIGHT", -20, 0)
    row.count:SetJustifyH("RIGHT")
    row:SetScript("OnClick", function(self)
        state.prof = self.prof
        Window:RefreshLists()
    end)
    row:SetScript("OnEnter", function(self) if self.prof ~= state.prof then self.bg:SetAlpha(0.4) self.bg:Show() end end)
    row:SetScript("OnLeave", function(self) if self.prof ~= state.prof then self.bg:Hide() end end)
    return row
end

local function updateProfRow(row, p)
    row.prof = p.name
    row.text:SetText(p.label or p.name)
    row.count:SetText(p.count)
    local selected = p.name == state.prof
    row.bg:SetAlpha(1)
    row.bg:SetShown(selected)
    row.mark:SetShown(selected)
    row.text:SetTextColor(Theme:Color(selected and "text" or "textDim"))
    row.icon:SetTexture("Interface\\AddOns\\CraftBoard\\Media\\Icons\\" .. (p.name and W.ProfessionIcon(p.name) or "filter"))
    row.icon:SetVertexColor(Theme:Color(selected and "accent" or "textDim"))
end

local function buildSidebar(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetWidth(SIDE_W)
    s:SetPoint("TOPLEFT", 1, -TITLE_H)
    s:SetPoint("BOTTOMLEFT", 1, 1)
    -- Rounded at the bottom-left (the window's corner); a flat strip squares off the top.
    local sbg = W.Fill(s, "sidebar", 1)
    sbg:SetAllPoints()
    W.Round(sbg, Theme.radius.panel)
    local cap = W.Fill(s, "sidebar", 1)
    cap:SetPoint("TOPLEFT")
    cap:SetPoint("TOPRIGHT")
    cap:SetHeight(24)
    W.Line(s, "right", "line")

    local label = sectionLabel(s, "Professions")
    label:SetPoint("TOPLEFT", 16, -18)

    s.share = CreateFrame("Frame", nil, s)
    s.share:SetPoint("BOTTOMLEFT", 12, 12)
    s.share:SetPoint("BOTTOMRIGHT", -12, 12)
    s.share:SetHeight(150)
    W.Surface(s.share, "window", 1, Theme.radius.panel)
    local shareLabel = sectionLabel(s.share, "You share")
    shareLabel:SetPoint("TOPLEFT", 12, -12)
    s.shareLines = {}
    for i = 1, 5 do
        local name = W.Text(s.share, 1, "text")
        name:SetPoint("TOPLEFT", 12, -12 - i * 18)
        local skill = W.Text(s.share, 0, "textDim")
        skill:SetPoint("TOPRIGHT", -12, -12 - i * 18)
        skill:SetJustifyH("RIGHT")
        s.shareLines[i] = { name = name, skill = skill }
    end
    s.shareNote = W.Text(s.share, -1, "textFaint")
    s.shareNote:SetWordWrap(true)
    s.shareNote:SetPoint("BOTTOMLEFT", 12, 10)
    s.shareNote:SetPoint("BOTTOMRIGHT", -12, 10)
    s.shareNote:SetText("Updates when you open your tradeskill window")

    local toggleRow = CreateFrame("Frame", nil, s)
    toggleRow:SetHeight(28)
    toggleRow:SetPoint("BOTTOMLEFT", s.share, "TOPLEFT", 4, 14)
    toggleRow:SetPoint("BOTTOMRIGHT", s.share, "TOPRIGHT", 0, 14)
    local sep = W.Line(toggleRow, "top", "line")
    sep:ClearAllPoints()
    sep:SetPoint("BOTTOMLEFT", toggleRow, "TOPLEFT", -4, 10)
    sep:SetPoint("BOTTOMRIGHT", toggleRow, "TOPRIGHT", 0, 10)
    sep:SetHeight(Theme:Pixel(toggleRow))
    s.toggle = W.Toggle(toggleRow, function(on)
        state.onlineOnly = on
        Window:RefreshLists()
    end)
    s.toggle:SetPoint("LEFT", 0, 0)
    local toggleText = W.Text(toggleRow, 1, "text")
    toggleText:SetPoint("LEFT", s.toggle, "RIGHT", 10, 0)
    toggleText:SetText("Online crafters only")

    s.list = W.VirtualList(s, PROF_ROW, createProfRow, updateProfRow)
    s.list:SetPoint("TOPLEFT", 0, -40)
    s.list:SetPoint("BOTTOMRIGHT", toggleRow, "TOPRIGHT", 0, 28)
    return s
end

local function updateShare()
    local s = frame.sidebar
    local rec = CB.db.chars[UnitGUID("player")]
    local lines = {}
    if rec then
        for name, k in pairs(rec.known or {}) do lines[#lines + 1] = { name = name, skill = k.skill } end
        table.sort(lines, function(a, b) return a.name < b.name end)
    end
    local saved, missing = {}, nil
    for _, prof in pairs(rec and rec.profs or {}) do saved[prof.name] = true end
    for i, l in ipairs(s.shareLines) do
        local line = lines[i]
        l.name:SetText(line and line.name or "")
        l.skill:SetText(line and line.skill or "")
        local isSaved = line and saved[line.name]
        l.name:SetTextColor(Theme:Color(isSaved and "text" or "textFaint"))
        if line and not isSaved then missing = missing or line.name end
    end
    if #lines == 0 then
        s.shareNote:SetText("Open a profession window to add your recipes")
    elseif missing then
        s.shareNote:SetText("Open your " .. missing .. " window to share it (dimmed = not opened yet)")
    else
        s.shareNote:SetText("Updates when you open your tradeskill window")
    end
end

-- ---------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------

-- Saved in UIParent units, so a scale change keeps the top-left corner where it was.
local function savePosition()
    local d = CB.db.settings
    local scale = frame:GetScale()
    d.left, d.top = frame:GetLeft() * scale, frame:GetTop() * scale
end

local function restorePosition()
    local d = CB.db.settings
    local scale = frame:GetScale()
    frame:ClearAllPoints()
    if d.left and d.top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d.left / scale, d.top / scale)
    else
        frame:SetPoint("CENTER")
    end
end

function Window.ResetPosition()
    CB.db.settings.left, CB.db.settings.top = nil, nil
    if frame then restorePosition() end
end

function Window:RefreshLists()
    if not frame or not frame:IsShown() then return end
    applyFilter()
    if not selectedRecipe() then state.selected = view[1] and view[1].id end

    local profs = { { name = nil, label = "All professions", count = #data.recipes } }
    for _, p in ipairs(data.profs) do profs[#profs + 1] = p end
    frame.sidebar.list:SetData(profs, true)

    frame.count:SetText(#view .. " recipes")
    frame.list:SetData(view, true)
    frame.emptyText:SetShown(#view == 0)
    frame.emptyText:SetText(#data.recipes == 0
        and "No recipes yet. Open a profession window and they appear here."
        or "No recipe matches.")
    updateDetail()
    updateShare()

    local shared, total = Catalog:MemberCounts()
    local age = CB.syncedAt and ("Synced " .. Catalog.FormatDuration(time() - CB.syncedAt) .. " ago · ") or ""
    frame.sync:SetText(total > 0 and (age .. "|cff" .. Theme:AccentHex() .. "" .. shared .. "/" .. total .. "|r members") or "Your characters only")
end

function Window:Refresh()
    if not frame or not frame:IsShown() then return end
    Catalog:RefreshRoster()
    data = Catalog:Build()
    if state.prof then
        local found
        for _, p in ipairs(data.profs) do if p.name == state.prof then found = true end end
        if not found then state.prof = nil end
    end
    self:RefreshLists()
end

local function build()
    frame = CreateFrame("Frame", "CraftBoardFrame", UIParent)
    tinsert(UISpecialFrames, "CraftBoardFrame") -- ESC closes it
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetScale(CB.db.settings.scale or 1)
    frame.bg = W.Surface(frame, "window", CB.db.settings.bgAlpha or 0.97, Theme.radius.panel)

    local title = CreateFrame("Frame", nil, frame)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(TITLE_H)
    W.Line(title, "bottom", "line")
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() frame:StartMoving() end)
    title:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
    end)

    local logo = title:CreateTexture(nil, "ARTWORK")
    logo:SetSize(24, 24)
    logo:SetPoint("LEFT", 16, 0)
    if logo:SetTexture(W.LOGO) == false then logo:SetColorTexture(Theme:Color("accent")) end
    local name = W.Text(title, 4, "text")
    name:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    name:SetText("CraftBoard")
    local sub = W.Text(title, -2, "accent")
    sub:SetPoint("LEFT", name, "RIGHT", 14, -1)
    sub:SetText("PROFESSIONS")

    local close = W.CloseButton(title, function() frame:Hide() end)
    close:SetPoint("RIGHT", -12, 0)
    local refresh = W.IconButton(title, "sync", "Refresh (roster and recipes)", function()
        local last = CB.db.lastAsk
        if CB.Share and (not last or time() - last > 60) then CB.Share.Ask(true) end
        Window:Refresh()
    end)
    refresh:SetPoint("RIGHT", close, "LEFT", -4, 0)
    local gear = W.IconButton(title, "settings", "Settings", function() CB.Settings.Toggle() end)
    gear:SetPoint("RIGHT", refresh, "LEFT", -4, 0)
    local pill = CreateFrame("Frame", nil, title)
    pill:SetHeight(28)
    pill:SetPoint("RIGHT", gear, "LEFT", -10, 0)
    W.Surface(pill, "field", 1, Theme.radius.control)
    local dot = pill:CreateTexture(nil, "ARTWORK")
    dot:SetSize(8, 8)
    dot:SetPoint("LEFT", 12, 0)
    W.Round(dot, 4)
    W.OnAccent(function(r, g, b) dot:SetColorTexture(r, g, b, 1) end)
    frame.sync = W.Text(pill, 0, "textDim")
    frame.sync:SetPoint("LEFT", dot, "RIGHT", 8, 0)
    frame.sync:SetText("Your characters only")
    pill:SetWidth(240)

    frame.sidebar = buildSidebar(frame)
    frame.detail = buildDetail(frame)

    local mid = CreateFrame("Frame", nil, frame)
    mid:SetPoint("TOPLEFT", frame.sidebar, "TOPRIGHT")
    mid:SetPoint("BOTTOMRIGHT", frame.detail, "BOTTOMLEFT")

    local searchLabel = sectionLabel(mid, "Search recipes")
    searchLabel:SetPoint("TOPLEFT", 26, -18)
    frame.count = W.Text(mid, 0, "textDim")
    frame.count:SetPoint("TOPRIGHT", -20, -18)
    local search = W.EditBox(mid, "Item, enchant or reagent", 32)
    search:SetPoint("TOPLEFT", 26, -38)
    search:SetPoint("TOPRIGHT", -20, -38)
    search:SetScript("OnTextChanged", function(self)
        state.search = self:GetText()
        Window:RefreshLists()
    end)

    local header = CreateFrame("Frame", nil, mid)
    header:SetHeight(28)
    header:SetPoint("TOPLEFT", 0, -84)
    header:SetPoint("TOPRIGHT", 0, -84)
    W.Line(header, "top", "line")
    W.Line(header, "bottom", "line")
    for _, col in ipairs({ { "Recipe", 20 }, { "Crafters", 340 }, { "Cooldown", 450 } }) do
        local fs = sectionLabel(header, col[1])
        fs:SetPoint("LEFT", col[2], 0)
    end

    frame.list = W.VirtualList(mid, RECIPE_ROW, createRecipeRow, updateRecipeRow)
    frame.list:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    frame.list:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.emptyText = W.Text(mid, 1, "textFaint")
    frame.emptyText:SetPoint("TOP", header, "BOTTOM", 0, -60)

    frame:SetScript("OnShow", function()
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        Window:Refresh()
    end)
    restorePosition()
    frame:Hide()
end

function Window.Frame() return frame end

-- Settings that change the window itself; fonts and accent colors repaint through the widgets.
CB:OnSettingChanged(function(key, value)
    if not frame then return end
    if key == "scale" then
        savePosition()
        frame:SetScale(value)
        restorePosition()
    elseif key == "bgAlpha" then
        frame.bg:SetAlpha(value)
    elseif key == "accentMode" or key == "accent" or key == "font" or key == "textSize" then
        Window:RefreshLists()
    end
end)

function Window.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end

function Window.Show()
    if not frame then build() end
    frame:Show()
end

-- Refresh while open when something changed underneath.
local pending = false
local function later()
    if pending or not frame or not frame:IsShown() then return end
    pending = true
    C_Timer.After(1, function()
        pending = false
        CB:Call("window refresh", Window.Refresh, Window)
    end)
end
Window.Changed = later
CB:RegisterEvent("GUILD_ROSTER_UPDATE", later)
CB:RegisterEvent("GET_ITEM_INFO_RECEIVED", later)
CB:RegisterEvent("ITEM_DATA_LOAD_RESULT", later)
function CB:OnRecipesChanged() later() end

CB:AddSlashCommand("open", function() Window.Toggle() end, "open or close the window")
