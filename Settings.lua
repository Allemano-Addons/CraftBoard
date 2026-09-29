-- Settings window: a label on the left, a control on the right, grouped in sections.
-- Every change is applied at once (CB:SetSetting); nothing needs a /reload.
local _, CB = ...

local Theme, W = CB.Theme, CB.W

local Settings = {}
CB.Settings = Settings

local WIDTH, ROW, LABEL_X, CONTROL_X, TITLE_H = 460, 34, 16, 170, 46
local frame
local controls = {} -- refresh functions, run when the window opens

local function set(key, value) CB:SetSetting(key, value) end

-- Layout helpers: y grows downward while building.
local y
local function heading(parent, text)
    y = y + 10
    local fs = W.Text(parent, -1, "accent")
    fs:SetPoint("TOPLEFT", LABEL_X, -y)
    fs:SetText(strupper(text))
    y = y + 24
end

local function row(parent, label, control, offsetY)
    local fs = W.Text(parent, 0, "textDim")
    fs:SetPoint("TOPLEFT", LABEL_X, -(y + 7))
    fs:SetText(label)
    control:SetPoint("TOPLEFT", CONTROL_X, -(y + (offsetY or 3)))
    y = y + ROW
    return fs
end

local function toggleRow(parent, label, get, onChange)
    local t = W.Toggle(parent, onChange)
    row(parent, label, t, 7)
    t.refresh = function() t:Set(get()) end
    controls[#controls + 1] = t
    return t
end

local function build()
    local s = CB.db.settings
    frame = CreateFrame("Frame", "CraftBoardSettingsFrame", UIParent)
    tinsert(UISpecialFrames, "CraftBoardSettingsFrame") -- ESC closes it
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetWidth(WIDTH)
    W.Surface(frame, "window", 0.98, Theme.radius.panel)

    -- Title bar (drag to move).
    local title = CreateFrame("Frame", nil, frame)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(TITLE_H)
    W.Line(title, "bottom", "line")
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() frame:StartMoving() end)
    title:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local name = W.Text(title, 3, "text")
    name:SetPoint("LEFT", 16, 0)
    name:SetText("CraftBoard Settings")
    local close = W.CloseButton(title, function() frame:Hide() end)
    close:SetPoint("RIGHT", -12, 0)

    local body = frame
    y = TITLE_H + 4

    -- Appearance -------------------------------------------------------------
    heading(body, "Appearance")

    local font = W.Dropdown(body, 240, function()
        local opts = {}
        for _, f in ipairs(Theme:AvailableFonts()) do opts[#opts + 1] = { value = f.name, label = f.name, font = f.path } end
        return opts
    end, function(v) set("font", v) end)
    row(body, "Font", font)
    font.refresh = function() font:Set(s.font) end
    controls[#controls + 1] = font

    local size = W.Segment(body, {
        { value = "S", label = "Small" }, { value = "M", label = "Medium" }, { value = "L", label = "Large" },
    }, function(v) set("textSize", v) end)
    row(body, "Text size", size, 5)
    size.refresh = function() size:Set(s.textSize) end
    controls[#controls + 1] = size

    local swatches = CreateFrame("Frame", nil, body)
    local accent = W.Segment(body, {
        { value = "own", label = "CraftBoard" },
        { value = "hush", label = "Follow Hush" },
        { value = "class", label = "Class" },
        { value = "custom", label = "Custom" },
    }, function(v)
        set("accentMode", v)
        swatches.refresh()
    end)
    row(body, "Accent color", accent, 5)
    accent.refresh = function() accent:Set(s.accentMode) end
    controls[#controls + 1] = accent

    -- Custom accent presets (only active with "Custom").
    swatches:SetSize(#Theme.ACCENTS * 26, 22)
    swatches:SetPoint("TOPLEFT", CONTROL_X, -(y - 2))
    swatches.list = {}
    for i, hexColor in ipairs(Theme.ACCENTS) do
        local sw = W.Swatch(swatches, hexColor, function()
            s.accentMode = "custom"
            accent:Set("custom")
            set("accent", hexColor)
            swatches.refresh()
        end)
        sw:SetPoint("LEFT", (i - 1) * 26, 0)
        sw.hex = hexColor
        swatches.list[i] = sw
    end
    swatches.refresh = function()
        for _, sw in ipairs(swatches.list) do
            sw:SetSelected(s.accentMode == "custom" and s.accent == sw.hex)
            sw:SetAlpha(s.accentMode == "custom" and 1 or 0.4)
        end
    end
    controls[#controls + 1] = swatches
    y = y + ROW - 6

    local alpha = W.Slider(body, 50, 100, 5, 170, function(v) return v .. "%" end,
        function(v) set("bgAlpha", v / 100) end)
    row(body, "Background", alpha, 9)
    alpha.refresh = function() alpha:Set(floor((s.bgAlpha or 0.97) * 100 + 0.5)) end
    controls[#controls + 1] = alpha

    local scale = W.Slider(body, 70, 130, 5, 170, function(v) return v .. "%" end,
        function(v) set("scale", v / 100) end)
    row(body, "Window scale", scale, 9)
    scale.refresh = function() scale:Set(floor((s.scale or 1) * 100 + 0.5)) end
    controls[#controls + 1] = scale

    -- Sharing ------------------------------------------------------------------
    heading(body, "Guild sharing")
    toggleRow(body, "Share my recipes", function() return s.share ~= false end, function(on) set("share", on) end)
    local note = W.Text(body, -1, "textFaint")
    note:SetWordWrap(true)
    note:SetPoint("TOPLEFT", LABEL_X, -(y - 4))
    note:SetWidth(WIDTH - 2 * LABEL_X)
    note:SetText("Only recipe IDs, skill levels and cooldowns are sent, to guild members who also run CraftBoard. Receiving always works.")
    y = y + 34

    local ask = W.Button(body, "Ask the guild now", "plain", function()
        if CB.Share.Ask(true) then CB:Print("Asked the guild for recipes.") else CB:Print("You are not in a guild.") end
    end, "sync")
    ask:SetPoint("TOPLEFT", LABEL_X, -y)
    local forget = W.Button(body, "Clear received data", "plain", nil)
    forget:SetPoint("LEFT", ask, "RIGHT", 8, 0)
    local armed
    forget:SetScript("OnClick", function()
        if not armed then
            armed = true
            forget:Configure("Click again to confirm", "plain")
            C_Timer.After(4, function()
                armed = false
                forget:Configure("Clear received data", "plain")
            end)
            return
        end
        armed = false
        wipe(CB.db.guild)
        CB.syncedAt = nil
        forget:Configure("Clear received data", "plain")
        CB:Print("Cleared the recipes received from other members.")
        if CB.Window.Changed then CB.Window.Changed() end
    end)
    y = y + 40

    -- Launcher -----------------------------------------------------------------
    heading(body, "Launcher button")
    toggleRow(body, "Show button", function() return s.launcher ~= false end, function(on) set("launcher", on) end)
    toggleRow(body, "Lock position", function() return s.launcherLocked == true end, function(on) set("launcherLocked", on) end)

    local reset = W.Button(body, "Reset window positions", "plain", function()
        CB.Window.ResetPosition()
        CB.ResetLauncherPosition()
        CB:Print("Window and launcher positions reset.")
    end)
    reset:SetPoint("TOPLEFT", LABEL_X, -(y + 8))
    y = y + 50

    frame:SetHeight(y)
    frame:SetScript("OnHide", function()
        W.HideTooltip()
        W.CloseMenus()
    end)
    frame:Hide()
end

local function place()
    frame:ClearAllPoints()
    local main = CB.Window.Frame()
    if main and main:IsShown() and main:GetRight() and
        (main:GetRight() * main:GetEffectiveScale() + WIDTH * frame:GetEffectiveScale()) < UIParent:GetRight() * UIParent:GetEffectiveScale() then
        -- Anchored to the screen, not to the window: resizing the window (scale slider) must not
        -- carry this one, and the slider under the mouse, along.
        local k = main:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local mine = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (main:GetRight() * k + 8) / mine, (main:GetTop() * k) / mine)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
end

function Settings.Toggle()
    if not CB.db then return end
    if not frame then
        -- A failed build must not leave a half-made (invisible) window behind.
        local ok, err = pcall(build)
        if not ok then
            if frame then frame:Hide() end
            frame = nil
            wipe(controls)
            CB:RecordError("settings build", err)
            return
        end
    end
    if frame:IsShown() then frame:Hide() return end
    for _, c in ipairs(controls) do c.refresh() end
    place()
    frame:Show()
end

CB:AddSlashCommand("settings", function() Settings.Toggle() end, "open the settings")
