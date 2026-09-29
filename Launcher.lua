-- Launcher: a small movable button (own, no LibDBIcon). Click opens the window, drag moves it.
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
    W.Fill(button, "sidebar", 0.95):SetAllPoints()
    local border = W.Border(button, "line")

    -- Logo: three violet columns.
    for i, h in ipairs({ 8, 13, 10 }) do
        local t = button:CreateTexture(nil, "ARTWORK")
        t:SetSize(4, h)
        t:SetPoint("BOTTOMLEFT", 7 + (i - 1) * 6, 8)
        t:SetColorTexture(Theme:Color("accent"))
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
    button:SetScript("OnDragStart", function(self) self:StartMoving() end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    restorePosition()
end

CB:RegisterEvent("PLAYER_LOGIN", function() CB:Call("launcher", build) end)
