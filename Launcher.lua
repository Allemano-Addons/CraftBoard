-- Launcher: a small movable button (own, no LibDBIcon). Click opens the window, drag moves it.
local _, CB = ...

local Theme, W = CB.Theme, CB.W
local SIZE = 32
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

    -- The round Allemano mark; if the texture does not load, a flat panel with the accent.
    local logo = button:CreateTexture(nil, "ARTWORK")
    logo:SetAllPoints()
    if logo:SetTexture(W.LOGO_ROUND) == false then
        logo:SetColorTexture(Theme:Color("accent"))
    end
    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetAllPoints()
    ring:SetTexture("Interface\\AddOns\\CraftBoard\\Media\\ui\\ring10")
    ring:SetVertexColor(Theme:Color("line"))

    button:SetScript("OnEnter", function(self)
        ring:SetVertexColor(Theme:Color("accent"))
        W.ShowTooltip(self, "CraftBoard - who in your guild can craft what")
    end)
    button:SetScript("OnLeave", function()
        ring:SetVertexColor(Theme:Color("line"))
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
