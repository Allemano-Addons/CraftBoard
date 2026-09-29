-- Widgets: Theme (the Allemano palette, CraftBoard orange) and the flat building blocks
-- used by the window: fills, lines, borders with rounded corners (same technique as
-- AltBoard and Hush's Allemano theme), text, icons, buttons, edit box, toggle, scrolling list.
-- No Blizzard textures (they are refused or restyled on WoW Forever).
local addonName, CB = ...

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
    accent    = { hex(CB.COLOR) },
}
Theme.radius = { control = 6, panel = 10, small = 4 }

Theme.FONT = "Fonts\\FRIZQT__.TTF"
Theme.SIZE = 12

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

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

-- Pixel-sized textures, re-sized when the UI scale changes.
local pixelItems = {}

local function applyPixel(item)
    local px = Theme:Pixel(item.frame)
    if item.axis == "h" then item.tex:SetHeight(px * item.n) else item.tex:SetWidth(px * item.n) end
end

function W.PixelSize(tex, frame, axis, n)
    local item = { tex = tex, frame = frame, axis = axis, n = n or 1 }
    pixelItems[#pixelItems + 1] = item
    applyPixel(item)
end

local function refreshPixels()
    for i = 1, #pixelItems do applyPixel(pixelItems[i]) end
end
CB:RegisterEvent("UI_SCALE_CHANGED", refreshPixels)
CB:RegisterEvent("DISPLAY_SIZE_CHANGED", refreshPixels)

function W.Fill(frame, colorKey, alpha, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    local r, g, b = Theme:Color(colorKey)
    t:SetColorTexture(r, g, b, alpha or 1)
    t.cbColor = { r, g, b, alpha or 1 } -- read by W.Round
    return t
end

-- A 1 px line along one side of frame.
function W.Line(frame, side, colorKey, layer)
    local t = W.Fill(frame, colorKey or "line", 1, layer or "BORDER")
    if side == "top" or side == "bottom" then
        local p = side == "top" and "TOP" or "BOTTOM"
        t:SetPoint(p .. "LEFT")
        t:SetPoint(p .. "RIGHT")
        W.PixelSize(t, frame, "h")
    else
        local p = side == "left" and "LEFT" or "RIGHT"
        t:SetPoint("TOP" .. p)
        t:SetPoint("BOTTOM" .. p)
        W.PixelSize(t, frame, "w")
    end
    return t
end

-- 1 px border. Recolor with border:SetColor(r, g, b, a) (also after W.RoundBorder).
local SIDES = { "top", "bottom", "left", "right" }
local borderMethods = {}
function borderMethods:SetColor(r, g, b, a)
    self.color = { r, g, b, a or 1 }
    for _, side in ipairs(SIDES) do self[side]:SetColorTexture(r, g, b, a or 1) end
end

function W.Border(frame, colorKey)
    local b = setmetatable({}, { __index = borderMethods })
    for _, side in ipairs(SIDES) do b[side] = W.Line(frame, side, colorKey) end
    local r, g, bl = Theme:Color(colorKey or "line")
    b.color = { r, g, bl, 1 }
    return b
end

-- ---------------------------------------------------------------------------
-- Rounded corners. W.Round turns an existing flat texture into a rounded rectangle and
-- W.RoundBorder does the same for a W.Border. Callers keep using the same methods
-- (SetColorTexture, SetAlpha, Show/Hide, SetPoint, border:SetColor). Corners come from
-- Media/ui (white circle / ring, tinted); if those do not load, the corners are square.
-- ---------------------------------------------------------------------------

local UI_MEDIA = MEDIA .. "ui\\"
local QUADS = { -- corner point, texcoords of that quarter of the circle
    { "TOPLEFT", 0, 0.5, 0, 0.5 }, { "TOPRIGHT", 0.5, 1, 0, 0.5 },
    { "BOTTOMLEFT", 0, 0.5, 0.5, 1 }, { "BOTTOMRIGHT", 0.5, 1, 0.5, 1 },
}
local RING_SIZES = { 4, 6, 8, 10 }

local function ringFile(radius)
    local best = RING_SIZES[1]
    for _, s in ipairs(RING_SIZES) do
        if math.abs(s - radius) < math.abs(best - radius) then best = s end
    end
    return UI_MEDIA .. "ring" .. best
end

-- Largest radius that fits the current size (tiny frames get smaller corners).
local function fitRadius(radius, w, h)
    return max(0, min(radius, floor(min(w or 0, h or 0) / 2)))
end

function W.Round(tex, radius)
    if not tex or tex.round then return tex end
    radius = radius or Theme.radius.control
    local parent = tex:GetParent()
    local layer, sub = tex:GetDrawLayer()
    local R = {
        color = tex.cbColor and { unpack(tex.cbColor) } or { 1, 1, 1, 1 },
        alpha = tex:GetAlpha(), shown = tex:IsShown(), corners = {}, rects = {}, parts = {},
    }

    -- An invisible frame carries the geometry; the pieces are textures on the parent, so
    -- they keep the original draw layer.
    local anchor = CreateFrame("Frame", nil, parent)
    anchor:SetSize(tex:GetSize())
    for i = 1, tex:GetNumPoints() do anchor:SetPoint(tex:GetPoint(i)) end
    tex:Hide()

    local function piece(list)
        local t = parent:CreateTexture(nil, layer, nil, sub)
        list[#list + 1] = t
        R.parts[#R.parts + 1] = t
        return t
    end
    for _, q in ipairs(QUADS) do
        local t = piece(R.corners)
        t.quad = q
        R.ok = t:SetTexture(UI_MEDIA .. "round") ~= false
        if R.ok then t:SetTexCoord(q[2], q[3], q[4], q[5]) end
    end
    local mid, left, right = piece(R.rects), piece(R.rects), piece(R.rects)

    local function layout()
        local r = fitRadius(radius, anchor:GetWidth(), anchor:GetHeight())
        for _, t in ipairs(R.corners) do
            t:ClearAllPoints()
            t:SetPoint(t.quad[1], anchor, t.quad[1])
            t:SetSize(max(r, 0.01), max(r, 0.01))
            t:SetShown(R.shown and r > 0)
        end
        mid:ClearAllPoints()
        mid:SetPoint("TOPLEFT", anchor, "TOPLEFT", r, 0)
        mid:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -r, 0)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -r)
        left:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", r, r)
        right:ClearAllPoints()
        right:SetPoint("TOPLEFT", anchor, "TOPRIGHT", -r, -r)
        right:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, r)
        left:SetShown(R.shown and r > 0)
        right:SetShown(R.shown and r > 0)
    end
    local function paint()
        local c = R.color
        for _, t in ipairs(R.rects) do t:SetColorTexture(c[1], c[2], c[3], c[4]) end
        for _, t in ipairs(R.corners) do
            if R.ok then t:SetVertexColor(c[1], c[2], c[3], c[4]) else t:SetColorTexture(c[1], c[2], c[3], c[4]) end
        end
    end
    local function show(on)
        R.shown = on and true or false
        mid:SetShown(R.shown)
        layout()
    end
    anchor:SetScript("OnSizeChanged", layout)

    tex.round = R
    tex.SetColorTexture = function(_, r, g, b, a) R.color = { r, g, b, a or 1 } paint() end
    tex.SetVertexColor = tex.SetColorTexture
    tex.SetAlpha = function(_, a)
        R.alpha = a
        for _, t in ipairs(R.parts) do t:SetAlpha(a) end
    end
    tex.GetAlpha = function() return R.alpha end
    tex.Show = function() show(true) end
    tex.Hide = function() show(false) end
    tex.SetShown = function(_, on) show(on) end
    tex.IsShown = function() return R.shown end
    tex.SetPoint = function(_, ...) anchor:SetPoint(...) end
    tex.ClearAllPoints = function() anchor:ClearAllPoints() end
    tex.SetAllPoints = function(_, rel) anchor:SetAllPoints(rel or parent) end
    tex.SetSize = function(_, w, h) anchor:SetSize(w, h) end
    tex.SetWidth = function(_, w) anchor:SetWidth(w) end
    tex.SetHeight = function(_, h) anchor:SetHeight(h) end
    tex.GetWidth = function() return anchor:GetWidth() end
    tex.GetHeight = function() return anchor:GetHeight() end

    paint()
    tex:SetAlpha(R.alpha)
    show(R.shown)
    return tex
end

function W.RoundBorder(b, radius)
    if not b or b.round then return b end
    radius = radius or Theme.radius.control
    local frame = b.top:GetParent()
    local layer, sub = b.top:GetDrawLayer()
    for _, side in ipairs(SIDES) do b[side]:Hide() end

    local R = { corners = {}, lines = {} }
    local file = ringFile(radius)
    for _, q in ipairs(QUADS) do
        local t = frame:CreateTexture(nil, layer, nil, sub)
        t.quad = q
        R.ok = t:SetTexture(file) ~= false
        if R.ok then t:SetTexCoord(q[2], q[3], q[4], q[5]) end
        R.corners[#R.corners + 1] = t
    end
    local top, bottom = frame:CreateTexture(nil, layer, nil, sub), frame:CreateTexture(nil, layer, nil, sub)
    local left, right = frame:CreateTexture(nil, layer, nil, sub), frame:CreateTexture(nil, layer, nil, sub)
    R.lines = { top, bottom, left, right }
    W.PixelSize(top, frame, "h")
    W.PixelSize(bottom, frame, "h")
    W.PixelSize(left, frame, "w")
    W.PixelSize(right, frame, "w")

    local function layout()
        local r = fitRadius(radius, frame:GetWidth(), frame:GetHeight())
        for _, t in ipairs(R.corners) do
            t:ClearAllPoints()
            t:SetPoint(t.quad[1], frame, t.quad[1])
            t:SetSize(max(r, 0.01), max(r, 0.01))
            t:SetShown(r > 0)
        end
        top:ClearAllPoints()
        top:SetPoint("TOPLEFT", r, 0)
        top:SetPoint("TOPRIGHT", -r, 0)
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", r, 0)
        bottom:SetPoint("BOTTOMRIGHT", -r, 0)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", 0, -r)
        left:SetPoint("BOTTOMLEFT", 0, r)
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", 0, -r)
        right:SetPoint("BOTTOMRIGHT", 0, r)
    end
    frame:HookScript("OnSizeChanged", layout)

    b.round = R
    b.SetColor = function(self, r, g, bl, a)
        self.color = { r, g, bl, a or 1 }
        for _, t in ipairs(R.lines) do t:SetColorTexture(r, g, bl, a or 1) end
        for _, t in ipairs(R.corners) do
            if R.ok then t:SetVertexColor(r, g, bl, a or 1) else t:SetColorTexture(r, g, bl, a or 1) end
        end
    end
    local c = b.color or { Theme:Color("line") }
    b:SetColor(c[1], c[2], c[3], c[4] or 1)
    layout()
    return b
end

-- A rounded background filling `frame` with a rounded 1 px border. Returns bg, border.
function W.Surface(frame, colorKey, alpha, radius, borderKey)
    local bg = W.Fill(frame, colorKey, alpha)
    bg:SetAllPoints()
    local border = W.Border(frame, borderKey or "line")
    W.Round(bg, radius or Theme.radius.panel)
    W.RoundBorder(border, radius or Theme.radius.panel)
    return bg, border
end

-- ---------------------------------------------------------------------------
-- Text, icons, tooltip
-- ---------------------------------------------------------------------------

function W.Text(parent, delta, colorKey, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(Theme.FONT, Theme.SIZE + (delta or 0), "")
    fs:SetShadowOffset(0, 0)
    fs:SetTextColor(Theme:Color(colorKey or "text"))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- White glyph from Media/Icons, tinted with a color key. Returns nil-safe texture.
function W.Icon(parent, name, size, colorKey)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size or 16, size or 16)
    if t:SetTexture(MEDIA .. "Icons\\" .. name) == false then t:Hide() end
    t:SetVertexColor(Theme:Color(colorKey or "textDim"))
    return t
end

local PROFESSION_ICONS = {
    ["Alchemy"] = "alchemy", ["Blacksmithing"] = "blacksmithing", ["Enchanting"] = "enchanting",
    ["Engineering"] = "engineering", ["Leatherworking"] = "leatherworking", ["Tailoring"] = "tailoring",
    ["Cooking"] = "cooking", ["First Aid"] = "first_aid",
}
function W.ProfessionIcon(name) return PROFESSION_ICONS[name] or "recipe" end

W.LOGO = MEDIA .. "Logo\\cb_mark_64"
W.LOGO_ROUND = MEDIA .. "Logo\\cb_minimap"

-- Own flat tooltip. lines = string or { "line", ... }.
local tip
function W.ShowTooltip(owner, lines)
    if not tip then
        tip = CreateFrame("Frame", nil, UIParent)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetClampedToScreen(true)
        W.Surface(tip, "field", 0.98, Theme.radius.control)
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

-- ---------------------------------------------------------------------------
-- Buttons and inputs
-- ---------------------------------------------------------------------------

function W.CloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(26, 26)
    b.bg = W.Fill(b, "selected", 1)
    b.bg:SetAllPoints()
    W.Round(b.bg, Theme.radius.small)
    b.bg:Hide()
    b.text = W.Text(b, 2, "textDim")
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

-- Square title-bar button with a glyph from Media/Icons.
function W.IconButton(parent, iconName, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(26, 26)
    b.bg = W.Fill(b, "selected", 1)
    b.bg:SetAllPoints()
    W.Round(b.bg, Theme.radius.small)
    b.bg:Hide()
    b.icon = W.Icon(b, iconName, 16, "textDim")
    b.icon:SetPoint("CENTER")
    b:SetScript("OnEnter", function(self)
        self.bg:Show()
        self.icon:SetVertexColor(Theme:Color("text"))
        if tooltip then W.ShowTooltip(self, tooltip) end
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:Hide()
        self.icon:SetVertexColor(Theme:Color("textDim"))
        W.HideTooltip()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Bordered text button, optionally with an icon. kind "accent" = orange outline and text.
function W.Button(parent, label, kind, onClick, iconName)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(28)
    b.kind = kind or "plain"
    b.bg = W.Fill(b, "field", 1)
    b.bg:SetAllPoints()
    b.border = W.Border(b, "line")
    W.Round(b.bg, Theme.radius.control)
    W.RoundBorder(b.border, Theme.radius.control)
    b.text = W.Text(b, 0, "text")
    if iconName then
        b.icon = W.Icon(b, iconName, 14, "text")
    end
    local function place()
        local w = b.text:GetStringWidth()
        b.text:ClearAllPoints()
        if b.icon then
            b.icon:ClearAllPoints()
            b.icon:SetPoint("LEFT", b, "LEFT", 12, 0)
            b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
            b:SetWidth(w + 12 + 14 + 6 + 12)
        else
            b.text:SetPoint("CENTER")
            b:SetWidth(w + 26)
        end
    end
    local function paint(hover)
        local r, g, bl
        if b.kind == "accent" then
            r, g, bl = Theme:Color("accent")
            b.border:SetColor(r, g, bl, hover and 1 or 0.85)
            b.bg:SetColorTexture(r, g, bl, hover and 0.26 or 0.13)
        else
            r, g, bl = Theme:Color("text")
            b.border:SetColor(Theme:Color(hover and "textFaint" or "line"))
            b.bg:SetColorTexture(Theme:Color(hover and "selected" or "field"))
        end
        b.text:SetTextColor(r, g, bl)
        if b.icon then b.icon:SetVertexColor(r, g, bl) end
    end
    b.text:SetText(label)
    place()
    paint(false)
    b:SetScript("OnEnter", function() paint(true) end)
    b:SetScript("OnLeave", function() paint(false) end)
    b:SetScript("OnClick", onClick)
    -- Change label, style and icon (list rows reuse their buttons).
    function b:Configure(text, newKind, newIcon)
        self.text:SetText(text)
        self.kind = newKind
        if self.icon and newIcon then self.icon:SetTexture(MEDIA .. "Icons\\" .. newIcon) end
        place()
        paint(false)
    end
    return b
end

-- Flat single-line edit box with a search icon and a placeholder.
function W.EditBox(parent, placeholder, height)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetHeight(height or 32)
    e:SetAutoFocus(false)
    e:SetFont(Theme.FONT, Theme.SIZE + 1, "")
    e:SetTextColor(Theme:Color("text"))
    e:SetTextInsets(36, 10, 0, 0)
    e.bg, e.border = W.Surface(e, "field", 1, Theme.radius.control)
    e.icon = W.Icon(e, "search", 16, "textFaint")
    e.icon:SetPoint("LEFT", 12, 0)
    e.placeholder = W.Text(e, 1, "textFaint")
    e.placeholder:SetPoint("LEFT", 36, 0)
    e.placeholder:SetText(placeholder or "")
    local function update(self)
        self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
    end
    e:SetScript("OnEditFocusGained", function(self)
        self.border:SetColor(Theme:Color("accent"))
        self.icon:SetVertexColor(Theme:Color("accent"))
        update(self)
    end)
    e:SetScript("OnEditFocusLost", function(self)
        self.border:SetColor(Theme:Color("line"))
        self.icon:SetVertexColor(Theme:Color("textFaint"))
        update(self)
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:HookScript("OnTextChanged", update)
    return e
end

function W.Toggle(parent, onChange)
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(34, 18)
    t.track = t:CreateTexture(nil, "BACKGROUND")
    t.track:SetAllPoints()
    t.knob = t:CreateTexture(nil, "ARTWORK")
    t.knob:SetSize(14, 14)
    W.Round(t.track, 9) -- pill track, round knob
    W.Round(t.knob, 7)
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
    W.Round(list.bar, 1)
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
