-- Launcher: a small movable button (own, no LibDBIcon), the same look and size as the other
-- Allemano addons' buttons (AltBoard's): a dark rounded square with the mark filling it.
-- Click opens the window, drag moves it.
local _, CB = ...

local Theme, W = CB.Theme, CB.W
local SIZE = 30
local button

local function savePosition()
    local d = CB.db.settings
    d.launcherLeft, d.launcherTop = button:GetLeft(), button:GetTop()
end

local function restorePosition()
    local d = CB.db.settings
    button:ClearAllPoints()
    if d.launcherLeft and d.launcherTop then
        button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d.launcherLeft, d.launcherTop)
    else
        button:SetPoint("TOP", UIParent, "TOP", 80, -8) -- right of Hush and AltBoard's buttons
    end
end

local function build()
    button = CreateFrame("Button", nil, UIParent)
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("HIGH")
    button:SetClampedToScreen(true)
    button:SetMovable(true)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    local _, border = W.Surface(button, "sidebar", 0.95, Theme.radius.control)

    -- The mark in its own colors; if the texture does not load, an accent-colored square.
    local logo = button:CreateTexture(nil, "ARTWORK")
    logo:SetPoint("TOPLEFT", 2, -2)
    logo:SetPoint("BOTTOMRIGHT", -2, 2)
    if logo:SetTexture(W.MARK) == false then
        logo:SetColorTexture(Theme:Color("accent"))
    end

    button:SetScript("OnEnter", function(self)
        border:SetColor(Theme:Color("accent"))
        W.ShowTooltip(self, "CraftBoard - who in your guild can craft what")
    end)
    button:SetScript("OnLeave", function()
        border:SetColor(Theme:Color("line"))
        W.HideTooltip()
    end)
    button:SetScript("OnClick", function() CB.Window.Toggle() end)
    button:SetScript("OnDragStart", function(self)
        if not CB.db.settings.launcherLocked then self:StartMoving() end
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    restorePosition()
    button:SetShown(CB.db.settings.launcher ~= false)
end

function CB.ResetLauncherPosition()
    CB.db.settings.launcherLeft, CB.db.settings.launcherTop = nil, nil
    if button then restorePosition() end
end

CB:OnSettingChanged(function(key, value)
    if key == "launcher" and button then button:SetShown(value ~= false) end
end)

CB:RegisterEvent("PLAYER_LOGIN", function() CB:Call("launcher", build) end)
