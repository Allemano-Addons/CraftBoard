-- Widgets: Theme (the Allemano palette, CraftBoard violet) and the flat building blocks
-- used by the window: fills, lines, borders, text, buttons, edit box, toggle, scrolling list.
-- No Blizzard textures (they are refused or restyled on WoW Forever).
local _, CB = ...

local Theme = {}
CB.Theme = Theme

local function hex(s)
    return tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255
end
Theme.Hex = hex

Theme.colors = {
    window    = { hex("121418") },
    sidebar   = { hex("0E1013") },
    field     = { hex("181B20") },
    selected  = { hex("1F232A") },
    line      = { hex("262A31") },
    text      = { hex("ECEDEF") },
    textDim   = { hex("9098A1") },
    textFaint = { hex("6E757E") },
    good      = { hex("3FC77F") },
    warn      = { hex("E8A33D") },
    cooldown  = { hex("F0703C") },
    accent    = { hex(CB.COLOR) },
}

Theme.FONT = "Fonts\\FRIZQT__.TTF"
Theme.SIZE = 12

function Theme:Color(key)
    local c = self.colors[key]
    return c[1], c[2], c[3]
end

function Theme.ClassColor(classFile)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = classFile and colors and colors[classFile]
    if c then return c.r, c.g, c.b end
    return Theme:Color("text")
end

-- One physical pixel in UI units, so 1 px lines stay sharp at any UI scale.
function Theme:Pixel(frame)
    local physH = 1080
    if GetPhysicalScreenSize then
        local _, h = GetPhysicalScreenSize()
        if h and h > 0 then physH = h end
    end
    return 768 / physH / (frame or UIParent):GetEffectiveScale()
end

local W = {}
CB.W = W

function W.Fill(frame, colorKey, alpha, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    local r, g, b = Theme:Color(colorKey)
    t:SetColorTexture(r, g, b, alpha or 1)
    return t
end

-- A 1 px line along one side of frame.
function W.Line(frame, side, colorKey, layer)
    local t = W.Fill(frame, colorKey or "line", 1, layer or "BORDER")
    local px = Theme:Pixel(frame)
    if side == "top" or side == "bottom" then
        local p = side == "top" and "TOP" or "BOTTOM"
        t:SetPoint(p .. "LEFT")
        t:SetPoint(p .. "RIGHT")
        t:SetHeight(px)
    else
        local p = side == "left" and "LEFT" or "RIGHT"
        t:SetPoint("TOP" .. p)
        t:SetPoint("BOTTOM" .. p)
        t:SetWidth(px)
    end
    return t
end

local SIDES = { "top", "bottom", "left", "right" }
local borderMethods = {}
function borderMethods:SetColor(r, g, b, a)
    for _, side in ipairs(SIDES) do self[side]:SetColorTexture(r, g, b, a or 1) end
end

function W.Border(frame, colorKey)
    local b = setmetatable({}, { __index = borderMethods })
    for _, side in ipairs(SIDES) do b[side] = W.Line(frame, side, colorKey) end
    return b
end

function W.Text(parent, delta, colorKey, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(Theme.FONT, Theme.SIZE + (delta or 0), "")
    fs:SetShadowOffset(0, 0)
    fs:SetTextColor(Theme:Color(colorKey or "text"))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Own flat tooltip. lines = string or { "line", ... }.
local tip
function W.ShowTooltip(owner, lines)
    if not tip then
        tip = CreateFrame("Frame", nil, UIParent)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetClampedToScreen(true)
        W.Fill(tip, "field", 0.98):SetAllPoints()
        W.Border(tip, "line")
        tip.text = W.Text(tip, -1, "text")
        tip.text:SetWordWrap(true)
        tip.text:SetSpacing(3)
        tip.text:SetPoint("TOPLEFT", 8, -6)
    end
    tip.text:SetText(type(lines) == "table" and table.concat(lines, "\n") or lines)
    tip.text:SetWidth(0)
    local w = min(tip.text:GetStringWidth() + 2, 320)
    tip.text:SetWidth(w)
    tip:SetSize(w + 16, tip.text:GetStringHeight() + 12)
    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
    tip:Show()
end

function W.HideTooltip()
    if tip then tip:Hide() end
end

function W.CloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    b.bg = W.Fill(b, "selected", 1)
    b.bg:SetAllPoints()
    b.bg:Hide()
    b.text = W.Text(b, 1, "textDim")
    b.text:SetPoint("CENTER", 0, 1)
    b.text:SetText("x")
    b:SetScript("OnEnter", function(self)
        self.bg:Show()
        self.text:SetTextColor(Theme:Color("text"))
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:Hide()
        self.text:SetTextColor(Theme:Color("textDim"))
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Bordered text button. kind "accent" = violet outline and text, "plain" = neutral.
function W.Button(parent, label, kind, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(26)
    b.kind = kind or "plain"
    b.bg = W.Fill(b, "field", 1)
    b.bg:SetAllPoints()
    b.border = W.Border(b, "line")
    b.text = W.Text(b, 0, "text")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetWidth(b.text:GetStringWidth() + 26)
    local function paint(hover)
        local r, g, bl
        if b.kind == "accent" then
            r, g, bl = Theme:Color("accent")
            b.border:SetColor(r, g, bl, hover and 1 or 0.8)
            b.bg:SetColorTexture(r, g, bl, hover and 0.28 or 0.14)
            b.text:SetTextColor(r, g, bl)
        else
            b.border:SetColor(Theme:Color("line"))
            b.bg:SetColorTexture(Theme:Color(hover and "selected" or "field"))
            b.text:SetTextColor(Theme:Color("text"))
            if hover then b.border:SetColor(Theme:Color("textFaint")) end
        end
    end
    paint(false)
    b:SetScript("OnEnter", function() paint(true) end)
    b:SetScript("OnLeave", function() paint(false) end)
    b:SetScript("OnClick", onClick)
    function b:SetLabel(text)
        self.text:SetText(text)
        self:SetWidth(self.text:GetStringWidth() + 26)
    end
    return b
end

-- Flat single-line edit box with a placeholder.
function W.EditBox(parent, placeholder, height)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetHeight(height or 28)
    e:SetAutoFocus(false)
    e:SetFont(Theme.FONT, Theme.SIZE + 1, "")
    e:SetTextColor(Theme:Color("text"))
    e:SetTextInsets(10, 10, 0, 0)
    e.bg = W.Fill(e, "field", 1)
    e.bg:SetAllPoints()
    e.border = W.Border(e, "line")
    e.placeholder = W.Text(e, 1, "textFaint")
    e.placeholder:SetPoint("LEFT", 10, 0)
    e.placeholder:SetText(placeholder or "")
    local function update(self)
        self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
    end
    e:SetScript("OnEditFocusGained", function(self)
        self.border:SetColor(Theme:Color("accent"))
        update(self)
    end)
    e:SetScript("OnEditFocusLost", function(self)
        self.border:SetColor(Theme:Color("line"))
        update(self)
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:HookScript("OnTextChanged", update)
    return e
end

function W.Toggle(parent, onChange)
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(32, 16)
    t.track = t:CreateTexture(nil, "BACKGROUND")
    t.track:SetAllPoints()
    t.knob = t:CreateTexture(nil, "ARTWORK")
    t.knob:SetSize(12, 12)
    function t:Set(on)
        self.value = on and true or false
        self.knob:ClearAllPoints()
        if self.value then
            self.track:SetColorTexture(Theme:Color("accent"))
            self.knob:SetColorTexture(Theme:Color("sidebar"))
            self.knob:SetPoint("RIGHT", -2, 0)
        else
            self.track:SetColorTexture(Theme:Color("line"))
            self.knob:SetColorTexture(Theme:Color("textDim"))
            self.knob:SetPoint("LEFT", 2, 0)
        end
    end
    t:SetScript("OnClick", function(self)
        self:Set(not self.value)
        if onChange then onChange(self.value) end
    end)
    t:Set(false)
    return t
end

-- Scrolling list of fixed-height rows; only the visible rows exist.
-- createRow(list) -> row frame; updateRow(row, item, index). Mouse wheel scrolls.
function W.VirtualList(parent, rowH, createRow, updateRow)
    local list = CreateFrame("Frame", nil, parent)
    list:SetClipsChildren(true)
    list:EnableMouseWheel(true)
    list.rows, list.data, list.offset = {}, {}, 0

    list.bar = W.Fill(list, "line", 1, "OVERLAY")
    list.bar:SetWidth(3)
    list.bar:Hide()

    function list:Refresh()
        local h, data = self:GetHeight(), self.data
        if h <= 0 then return end
        local total = #data * rowH
        local maxOffset = max(0, total - h)
        self.offset = min(max(self.offset, 0), maxOffset)
        local first = floor(self.offset / rowH) + 1
        local shift = self.offset - (first - 1) * rowH
        for i = 1, ceil(h / rowH) + 1 do
            local row = self.rows[i]
            if not row then
                row = createRow(self)
                self.rows[i] = row
            end
            local item = data[first + i - 1]
            if item then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, shift - (i - 1) * rowH)
                row:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, shift - (i - 1) * rowH)
                row:SetHeight(rowH)
                row.index = first + i - 1
                updateRow(row, item, first + i - 1)
                row:Show()
            else
                row:Hide()
            end
        end
        for i = ceil(h / rowH) + 2, #self.rows do self.rows[i]:Hide() end
        if maxOffset > 0 then
            local barH = max(20, h * h / total)
            self.bar:ClearAllPoints()
            self.bar:SetPoint("TOPRIGHT", 0, -(h - barH) * (self.offset / maxOffset))
            self.bar:SetHeight(barH)
            self.bar:Show()
        else
            self.bar:Hide()
        end
    end

    -- keepScroll: stay where we are (data was only refreshed).
    function list:SetData(data, keepScroll)
        self.data = data
        if not keepScroll then self.offset = 0 end
        self:Refresh()
    end

    list:SetScript("OnMouseWheel", function(self, delta)
        self.offset = self.offset - delta * rowH * 1.5
        self:Refresh()
    end)
    list:SetScript("OnSizeChanged", function(self) self:Refresh() end)
    return list
end
