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
            return text .. " · |cfff0703cCooldown " .. Catalog.FormatDuration(c.cdLeft) .. " left|r"
        end
        return text .. " · |cfff0703cCooldown ready|r"
    end
    return text
end

local function createCrafterRow(list)
    local row = CreateFrame("Frame", nil, list)
    row.bg = W.Fill(row, "field", 1)
    row.bg:SetPoint("TOPLEFT", 0, -2)
    row.bg:SetPoint("BOTTOMRIGHT", -6, 2)
    row.border = W.Border(row, "line")
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(7, 7)
    row.dot:SetPoint("LEFT", 12, 0)
    row.name = W.Text(row, 2, "text")
    row.name:SetPoint("TOPLEFT", 28, -13)
    row.sub = W.Text(row, -1, "textDim")
    row.sub:SetPoint("BOTTOMLEFT", 28, 13)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -84, 0)
    row.button = W.Button(row, "Whisper", "accent")
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
            row.button:SetLabel("Whisper")
            row.button.kind = "accent"
            row.button:SetScript("OnClick", function() whisper(c.name) end)
        else
            row.button:SetLabel("Mail")
            row.button.kind = "plain"
            row.button:SetScript("OnClick", function() mail(c.name) end)
        end
        row.button:GetScript("OnLeave")(row.button)
    end
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
    d.name = W.Text(d, 4, "text")
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 12, -3)
    d.name:SetPoint("RIGHT", -14, 0)
    d.prof = W.Text(d, -2, "accent")
    d.prof:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -6)

    d.reagentsLabel = sectionLabel(d, "Reagents")
    d.reagentsLabel:SetPoint("TOPLEFT", 16, -84)
    d.reagents = {}
    for i = 1, MAX_REAGENTS do
        local row = CreateFrame("Frame", nil, d)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", 16, -100 - (i - 1) * 24)
        row:SetPoint("TOPRIGHT", -14, -100 - (i - 1) * 24)
        row.text = W.Text(row, 1, "text")
        row.text:SetPoint("LEFT", 0, 0)
        row.text:SetPoint("RIGHT", -34, 0)
        row.qty = W.Text(row, 1, "textDim")
        row.qty:SetPoint("RIGHT", 0, 0)
        row.qty:SetJustifyH("RIGHT")
        d.reagents[i] = row
    end

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
        return
    end
    d.icon:SetTexture(Catalog:ItemIcon(r.output) or 134400)
    d.name:SetText(r.name)
    d.prof:SetText(strupper(r.profName or ""))

    local n = r.reagents and #r.reagents / 2 or 0
    for i, row in ipairs(d.reagents) do
        if i <= n then
            row.text:SetText(itemLabel(r.reagents[i * 2 - 1]))
            row.qty:SetText("x" .. r.reagents[i * 2])
            row:Show()
        else
            row:Hide()
        end
    end
    d.craftersLabel:ClearAllPoints()
    d.craftersLabel:SetPoint("TOPLEFT", 16, -(100 + max(n, 1) * 24 + 16))
    d.craftersSort:ClearAllPoints()
    d.craftersSort:SetPoint("TOPRIGHT", d, "TOPRIGHT", -14, -(100 + max(n, 1) * 24 + 16))
    d.list:ClearAllPoints()
    d.list:SetPoint("TOPLEFT", 10, -(100 + max(n, 1) * 24 + 36))
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
    row.bg:SetAllPoints()
    W.Line(row, "bottom", "line")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", 20, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.iconBg = W.Fill(row, "field", 1)
    row.iconBg:SetAllPoints(row.icon)
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
        row.cooldown:SetText("|cfff0703c" .. r.ready .. " ready now|r")
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
    row.mark = W.Fill(row, "accent", 1, "ARTWORK")
    row.mark:SetPoint("LEFT", 14, 0)
    row.mark:SetSize(2, 14)
    row.text = W.Text(row, 1, "textDim")
    row.text:SetPoint("LEFT", 26, 0)
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
end

local function buildSidebar(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetWidth(SIDE_W)
    s:SetPoint("TOPLEFT", 0, -TITLE_H)
    s:SetPoint("BOTTOMLEFT")
    W.Fill(s, "sidebar", 1):SetAllPoints()
    W.Line(s, "right", "line")

    local label = sectionLabel(s, "Professions")
    label:SetPoint("TOPLEFT", 16, -18)

    s.share = CreateFrame("Frame", nil, s)
    s.share:SetPoint("BOTTOMLEFT", 12, 12)
    s.share:SetPoint("BOTTOMRIGHT", -12, 12)
    s.share:SetHeight(150)
    W.Fill(s.share, "window", 1):SetAllPoints()
    W.Border(s.share, "line")
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
    for i, l in ipairs(s.shareLines) do
        local line = lines[i]
        l.name:SetText(line and line.name or "")
        l.skill:SetText(line and line.skill or "")
    end
    s.shareNote:SetText(#lines == 0 and "Open a profession window to add your recipes" or "Updates when you open your tradeskill window")
end

-- ---------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------

local function savePosition()
    local d = CB.db.settings
    d.left, d.top = frame:GetLeft(), frame:GetTop()
end

local function restorePosition()
    local d = CB.db.settings
    frame:ClearAllPoints()
    if d.left and d.top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d.left, d.top)
    else
        frame:SetPoint("CENTER")
    end
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
    frame.sync:SetText(total > 0 and ("|cffb57edc" .. shared .. "/" .. total .. "|r members") or "Your characters only")
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
    W.Fill(frame, "window", 0.97):SetAllPoints()
    W.Border(frame, "line")

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
    logo:SetSize(20, 20)
    logo:SetPoint("LEFT", 16, 0)
    logo:SetColorTexture(Theme:Color("accent"))
    local name = W.Text(title, 4, "text")
    name:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    name:SetText("CraftBoard")
    local sub = W.Text(title, -2, "accent")
    sub:SetPoint("LEFT", name, "RIGHT", 14, -1)
    sub:SetText("PROFESSIONS")

    local close = W.CloseButton(title, function() frame:Hide() end)
    close:SetPoint("RIGHT", -12, 0)
    local refresh = W.Button(title, "Refresh", "plain", function() Window:Refresh() end)
    refresh:SetPoint("RIGHT", close, "LEFT", -8, 0)
    local pill = CreateFrame("Frame", nil, title)
    pill:SetHeight(26)
    pill:SetPoint("RIGHT", refresh, "LEFT", -10, 0)
    W.Fill(pill, "field", 1):SetAllPoints()
    W.Border(pill, "line")
    local dot = pill:CreateTexture(nil, "ARTWORK")
    dot:SetSize(7, 7)
    dot:SetPoint("LEFT", 10, 0)
    dot:SetColorTexture(Theme:Color("accent"))
    frame.sync = W.Text(pill, 0, "textDim")
    frame.sync:SetPoint("LEFT", dot, "RIGHT", 8, 0)
    frame.sync:SetText("Your characters only")
    pill:SetWidth(200)

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
CB:RegisterEvent("GUILD_ROSTER_UPDATE", later)
CB:RegisterEvent("GET_ITEM_INFO_RECEIVED", later)
CB:RegisterEvent("ITEM_DATA_LOAD_RESULT", later)
function CB:OnRecipesChanged() later() end

CB:AddSlashCommand("open", function() Window.Toggle() end, "open or close the window")
