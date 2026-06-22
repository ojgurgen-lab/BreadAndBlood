-- Bread and Blood Addon for WoW 3.3.5a


local defaultDB = {
    hunger = 100,
    thirst = 100,
    fatigue = 100,
    blood = 100,
    pos = nil,
    config = {
        hungerRate = 1,
        thirstRate = 1,
        fatigueRate = 1,
        effectThreshold = 15,
        sourceActionBars = "hunger",
        sourceUnitFrames = "hunger",
        sourceMinimap = "thirst",
        sourceWorldMap = "thirst",
        sourceCombatError = "hunger",
        threshActionBars = 50,
        threshUnitFrames = 25,
        threshMinimap = 50,
        threshWorldMap = 25,
        threshCombatError = 25,
        heavyLoadPenalty = "enabled",
        woundSystem = "enabled",
        zoneWeather = "enabled",
        combatPenalty = "enabled",
        movementPenalty = "enabled",
        alwaysShowBars = "enabled",
    }
}

local effectTimer = 0

local hotZones = {
    ["Tanaris"] = true, ["The Barrens"] = true, ["Silithus"] = true, ["Desolace"] = true, 
    ["Durotar"] = true, ["Badlands"] = true, ["Searing Gorge"] = true, ["Burning Steppes"] = true, 
    ["Hellfire Peninsula"] = true, ["Blade's Edge Mountains"] = true
}

local coldZones = {
    ["Winterspring"] = true, ["Dun Morogh"] = true, ["Alterac Mountains"] = true, 
    ["Icecrown"] = true, ["The Storm Peaks"] = true, ["Dragonblight"] = true, 
    ["Borean Tundra"] = true, ["Howling Fjord"] = true, ["Zul'Drak"] = true, 
    ["Crystalsong Forest"] = true, ["Grizzly Hills"] = true
}

local effectTimer = 0

local blinkTimer = 0
local isBlinking = false
local isSleeping = false

local scanTooltip = CreateFrame("GameTooltip", "BnBScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function CheckConsumables()
    local isEating, eatIdx = false, nil
    local isDrinking, drinkIdx = false, nil
    
    for i=1, 40 do
        local name, _, icon = UnitAura("player", i)
        if not name then break end
        
        local lName = name:lower()
        local lIcon = icon and icon:lower() or ""
        
        if not isEating and (lName:find("food") or lName:find("yemek") or (lIcon and (lIcon:find("inv_misc_food") or lIcon:find("spell_misc_food")))) then
            isEating = true
            eatIdx = i
        end
        
        if not isDrinking and (lName:find("drink") or lName:find("water") or lName:find("su") or lName:find("içmek") or (lIcon and lIcon:find("inv_drink"))) then
            isDrinking = true
            drinkIdx = i
        end
        
        if isEating and isDrinking then break end
    end
    
    return isEating, eatIdx, isDrinking, drinkIdx
end

local function GetAuraRestorePercent(auraIndex, isDrink)
    scanTooltip:ClearLines()
    scanTooltip:SetUnitAura("player", auraIndex)
    
    local amount = 0
    for i = 1, 6 do
        local leftLine = _G["BnBScanTooltipTextLeft" .. i]
        if leftLine then
            local text = leftLine:GetText()
            if text then
                local hm = text:match("(%d+) health and mana")
                if hm then
                    amount = tonumber(hm)
                    break
                end
                
                if isDrink then
                    local m = text:match("(%d+) mana")
                    if m then amount = tonumber(m); break end
                else
                    local h = text:match("(%d+) health")
                    if h then amount = tonumber(h); break end
                end
            end
        end
    end
    
    if amount == 0 then
        return 25
    end
    
    local maxStat = 1
    if isDrink then
        maxStat = UnitPowerMax("player", 0)
        if maxStat == 0 then maxStat = UnitHealthMax("player") end
    else
        maxStat = UnitHealthMax("player")
    end
    if maxStat == 0 then maxStat = 1 end
    
    local pct = (amount / maxStat) * 100
    local restoreAmount = pct * 6.5
    if restoreAmount > 100 then restoreAmount = 100 end
    if restoreAmount < 15 then restoreAmount = 15 end
    
    return math.floor(restoreAmount)
end

local function IsNearCampfire()
    for i=1, 40 do
        local name, _, icon, _, _, _, _, _, _, _, spellId = UnitAura("player", i)
        if not name then break end
        local lName = name:lower()
        local lIcon = (icon and icon:lower()) or ""
        
        if lName:find("campfire") or lName:find("cozy") or lName:find("fire") or lName:find("ateşi") or lIcon:find("campfire") or lIcon:find("spell_fire_fire") or spellId == 818 or spellId == 24858 then
            return true
        end
    end
    return false
end

local function GetBagFullness()
    local totalSlots = 0
    local usedSlots = 0
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        if slots and slots > 0 then
            totalSlots = totalSlots + slots
            for slot = 1, slots do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    usedSlots = usedSlots + 1
                end
            end
        end
    end
    if totalSlots == 0 then return 0 end
    return usedSlots / totalSlots
end

local coreFrame = CreateFrame("Frame")
coreFrame:RegisterEvent("VARIABLES_LOADED")
coreFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
coreFrame:RegisterEvent("PLAYER_LOGOUT")
coreFrame:RegisterEvent("UNIT_AURA")
coreFrame:RegisterEvent("UNIT_HEALTH")
coreFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
coreFrame:RegisterEvent("PLAYER_STARTED_MOVING")
coreFrame:RegisterEvent("PLAYER_REGEN_DISABLED")

local isForcedSit = false

hooksecurefunc("DoEmote", function(emote)
    if type(emote) == "string" then
        emote = emote:upper()
        if (emote == "SLEEP" or emote == "SIT") and not isForcedSit then
            isSleeping = true
        elseif emote == "STAND" then
            isSleeping = false
        end
    end
end)

if SlashCmdList["SLEEP"] then hooksecurefunc(SlashCmdList, "SLEEP", function() isSleeping = true end) end
if SlashCmdList["SIT"] then hooksecurefunc(SlashCmdList, "SIT", function() isSleeping = true end) end
if SlashCmdList["STAND"] then hooksecurefunc(SlashCmdList, "STAND", function() isSleeping = false end) end

hooksecurefunc("JumpOrAscendStart", function() isSleeping = false end)
hooksecurefunc("SitStandOrDescendStart", function() isSleeping = false end)
if ToggleSit then hooksecurefunc("ToggleSit", function() isSleeping = false end) end

-- =========================================
-- VISUAL UI (DRAGGABLE BARS)
-- =========================================
local uiFrame = CreateFrame("Frame", "BreadAndBloodUIFrame", UIParent)
uiFrame:SetWidth(180)
uiFrame:SetHeight(96)
uiFrame:SetPoint("CENTER", 0, -150)
uiFrame:SetMovable(true)
uiFrame:EnableMouse(true)
uiFrame:RegisterForDrag("LeftButton")
uiFrame:SetScript("OnDragStart", uiFrame.StartMoving)
uiFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
    if BreadAndBloodDB then
        BreadAndBloodDB.pos = {point = point, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs}
    end
end)

-- Removed backdrop for completely borderless floating bars

local function CreateNicerBar(parent, yOffset, r, g, b, label, iconTex, tooltipText)
    local iconFrame = CreateFrame("Frame", nil, parent)
    iconFrame:SetSize(24, 24)
    iconFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", -4, yOffset + 4)
    iconFrame:EnableMouse(true)

    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
    icon:SetTexture(iconTex)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    
    local iconBorder = CreateFrame("Frame", nil, iconFrame)
    iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
    iconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    iconBorder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    iconBorder:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetWidth(140)
    bar:SetHeight(14)
    bar:SetPoint("LEFT", iconFrame, "RIGHT", 2, 0)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(r, g, b)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(100)
    bar:EnableMouse(true)
    
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bg:SetVertexColor(0, 0, 0, 0.5)
    
    local border = CreateFrame("Frame", nil, bar)
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    border:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local font, size, flags = text:GetFont()
    text:SetFont(font, size, "OUTLINE")
    text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    text:SetText(label .. ": 100%")
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 1)
    
    bar.UpdateVisibility = function(self)
        local alwaysShow = (BreadAndBloodDB and BreadAndBloodDB.config and BreadAndBloodDB.config.alwaysShowBars == "enabled")
        if alwaysShow or self.isHoveredIcon or self.isHoveredBar or self:GetValue() < 85 then
            self:SetAlpha(1)
        else
            self:SetAlpha(0)
        end
    end
    
    iconFrame:SetScript("OnEnter", function()
        bar.isHoveredIcon = true
        bar:UpdateVisibility()
        GameTooltip:SetOwner(iconFrame, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        if tooltipText then GameTooltip:AddLine(tooltipText, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    iconFrame:SetScript("OnLeave", function()
        bar.isHoveredIcon = false
        bar:UpdateVisibility()
        GameTooltip:Hide()
    end)
    
    bar:SetScript("OnEnter", function()
        bar.isHoveredBar = true
        bar:UpdateVisibility()
        GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        if tooltipText then GameTooltip:AddLine(tooltipText, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function()
        bar.isHoveredBar = false
        bar:UpdateVisibility()
        GameTooltip:Hide()
    end)
    
    local function OnDragStart()
        parent:StartMoving()
    end
    
    local function OnDragStop()
        parent:StopMovingOrSizing()
        local point, relativeTo, relativePoint, xOfs, yOfs = parent:GetPoint()
        if BreadAndBloodDB then
            BreadAndBloodDB.pos = {point = point, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs}
        end
    end

    iconFrame:RegisterForDrag("LeftButton")
    iconFrame:SetScript("OnDragStart", OnDragStart)
    iconFrame:SetScript("OnDragStop", OnDragStop)
    
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", OnDragStart)
    bar:SetScript("OnDragStop", OnDragStop)
    
    bar:UpdateVisibility()
    
    return bar, text
end

local hungerBar, hungerText = CreateNicerBar(uiFrame, 0, 0.9, 0.4, 0.2, "Hunger", "Interface\\Icons\\INV_Misc_Food_15", "Represents your need for food. Depletes over time. Affected by extreme cold and minor wounds. If it gets too low, your stomach will growl and you may starve.")
local thirstBar, thirstText = CreateNicerBar(uiFrame, -20, 0.2, 0.6, 1.0, "Thirst", "Interface\\Icons\\INV_Drink_08", "Represents your need for water. Depletes over time. Affected by extreme heat and severe wounds. Keeps you hydrated.")
local fatigueBar, fatigueText = CreateNicerBar(uiFrame, -40, 0.8, 0.8, 0.3, "Fatigue", "Interface\\Icons\\Spell_Nature_Sleep", "Represents your energy levels. Depletes slowly, but faster when running or swimming. Replenish by sleeping, sitting, or resting near a campfire.")
local bloodBar, bloodText = CreateNicerBar(uiFrame, -60, 0.9, 0.2, 0.2, "Blood", "Interface\\Icons\\Ability_Rogue_Rupture", "Represents your physical integrity. Drops when taking sudden massive damage. Drops steadily if wounded. Bandage yourself to heal wounds and stop bleeding.")

local function AddTooltip(frame, title, r, g, b, textFunc)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, r, g, b)
        if type(textFunc) == "function" then
            GameTooltip:AddLine(textFunc(), nil, nil, nil, true)
        else
            GameTooltip:AddLine(textFunc, nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
end

local swimStatusIcon = CreateFrame("Frame", "BnBSwimStatus", uiFrame)
swimStatusIcon:SetSize(24, 24)
swimStatusIcon:SetPoint("TOPRIGHT", uiFrame, "BOTTOMRIGHT", -4, -4)
swimStatusIcon:SetAlpha(0)
swimStatusIcon:Hide()
local swimStatusTex = swimStatusIcon:CreateTexture(nil, "ARTWORK")
swimStatusTex:SetAllPoints()
swimStatusTex:SetTexture("Interface\\Icons\\Ability_Druid_AquaticForm")
AddTooltip(swimStatusIcon, "Swimming", 0.1, 0.5, 0.9, "Swimming drains your fatigue twice as fast.")

local weightStatusIcon = CreateFrame("Frame", "BnBWeightStatus", uiFrame)
weightStatusIcon:SetSize(24, 24)
weightStatusIcon:SetPoint("TOPLEFT", uiFrame, "BOTTOMLEFT", 4, -4)
weightStatusIcon:SetAlpha(0)
weightStatusIcon:Hide()
local weightStatusTex = weightStatusIcon:CreateTexture(nil, "ARTWORK")
weightStatusTex:SetAllPoints()
weightStatusTex:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
AddTooltip(weightStatusIcon, "Heavy Load", 0.6, 0.4, 0.2, function()
    local text = "Your bags are heavily loaded. Your stats drain faster."
    if BreadAndBloodDB.config.heavyLoadPenalty == "enabled" and GetBagFullness() >= 0.9 then
        text = text .. "\n\n|cffff0000WARNING: Running with a full bag will rapidly drain your fatigue!|r"
    end
    return text
end)

local woundStatusIcon = CreateFrame("Frame", "BnBWoundStatus", uiFrame)
woundStatusIcon:SetSize(24, 24)
woundStatusIcon:SetPoint("TOP", uiFrame, "BOTTOM", 0, -4)
woundStatusIcon:SetAlpha(0)
woundStatusIcon:Hide()
local woundStatusTex = woundStatusIcon:CreateTexture(nil, "ARTWORK")
woundStatusTex:SetAllPoints()
woundStatusTex:SetTexture("Interface\\Icons\\Ability_Rogue_Rupture")
AddTooltip(woundStatusIcon, "Wounded", 1, 0, 0, "You are bleeding! Your thirst drains 3x faster and running exhausts you quickly.\n\nApply a bandage or take a long rest to recover.")

local tempStatusIcon = CreateFrame("Frame", "BnBTempStatus", uiFrame)
tempStatusIcon:SetSize(24, 24)
tempStatusIcon:SetPoint("TOPRIGHT", swimStatusIcon, "TOPLEFT", -4, 0)
tempStatusIcon:SetAlpha(0)
tempStatusIcon:Hide()
local tempStatusTex = tempStatusIcon:CreateTexture(nil, "ARTWORK")
tempStatusTex:SetAllPoints()
tempStatusTex:SetTexture("Interface\\Icons\\Spell_Fire_Fire")
tempStatusIcon:EnableMouse(true)
tempStatusIcon:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

local blinkFrame = CreateFrame("Frame", "BreadAndBloodBlinkFrame", WorldFrame)
blinkFrame:SetAllPoints(WorldFrame)
blinkFrame:SetFrameStrata("TOOLTIP")
blinkFrame:SetAlpha(0)
blinkFrame:Hide()
local blinkTexture = blinkFrame:CreateTexture(nil, "BACKGROUND")
blinkTexture:SetAllPoints(blinkFrame)
blinkTexture:SetTexture(0, 0, 0, 1)

local bloodPulseFrame = CreateFrame("Frame", "BnBBloodPulseFrame", UIParent)
bloodPulseFrame:SetAllPoints(UIParent)
bloodPulseFrame:SetFrameStrata("BACKGROUND")
bloodPulseFrame:SetAlpha(0)
bloodPulseFrame:Hide()
local bloodPulseTex = bloodPulseFrame:CreateTexture(nil, "BACKGROUND")
bloodPulseTex:SetAllPoints()
bloodPulseTex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
bloodPulseTex:SetBlendMode("ADD")

local hungerWarningIcon = CreateFrame("Frame", "BnBHungerWarning", UIParent)
hungerWarningIcon:SetSize(64, 64)
hungerWarningIcon:SetPoint("CENTER", -80, 150)
hungerWarningIcon:SetAlpha(0)
hungerWarningIcon:Hide()
local hwTexture = hungerWarningIcon:CreateTexture(nil, "ARTWORK")
hwTexture:SetAllPoints()
hwTexture:SetTexture("Interface\\Icons\\INV_Misc_Food_15")
AddTooltip(hungerWarningIcon, "Starving", 1, 0.5, 0, "You are extremely hungry! Find food immediately.")

local thirstWarningIcon = CreateFrame("Frame", "BnBThirstWarning", UIParent)
thirstWarningIcon:SetSize(64, 64)
thirstWarningIcon:SetPoint("CENTER", 0, 150)
thirstWarningIcon:SetAlpha(0)
thirstWarningIcon:Hide()
local twTexture = thirstWarningIcon:CreateTexture(nil, "ARTWORK")
twTexture:SetAllPoints()
twTexture:SetTexture("Interface\\Icons\\INV_Drink_08")
AddTooltip(thirstWarningIcon, "Dehydrated", 0.1, 0.5, 0.9, "You are extremely thirsty! Find something to drink immediately.")

local fatigueWarningIcon = CreateFrame("Frame", "BnBFatigueWarning", UIParent)
fatigueWarningIcon:SetSize(64, 64)
fatigueWarningIcon:SetPoint("CENTER", 80, 150)
fatigueWarningIcon:SetAlpha(0)
fatigueWarningIcon:Hide()
local fwTexture = fatigueWarningIcon:CreateTexture(nil, "ARTWORK")
fwTexture:SetAllPoints()
fwTexture:SetTexture("Interface\\Icons\\Spell_Nature_Sleep")
AddTooltip(fatigueWarningIcon, "Exhausted", 0.7, 0.7, 0.2, "You are extremely tired! Rest in an inn or near a campfire to recover.")

local function UpdateUIBars()
    if not BreadAndBloodDB then return end
    hungerBar:SetValue(BreadAndBloodDB.hunger)
    hungerText:SetText("Hunger: " .. math.floor(BreadAndBloodDB.hunger) .. "%")
    hungerBar:UpdateVisibility()
    
    thirstBar:SetValue(BreadAndBloodDB.thirst)
    thirstText:SetText("Thirst: " .. math.floor(BreadAndBloodDB.thirst) .. "%")
    thirstBar:UpdateVisibility()
    
    fatigueBar:SetValue(BreadAndBloodDB.fatigue)
    fatigueText:SetText("Fatigue: " .. math.floor(BreadAndBloodDB.fatigue) .. "%")
    fatigueBar:UpdateVisibility()
    
    bloodBar:SetValue(BreadAndBloodDB.blood)
    bloodText:SetText("Blood: " .. math.floor(BreadAndBloodDB.blood) .. "%")
    bloodBar:UpdateVisibility()
end

-- =========================================
-- OPTIONS MENU (INTERFACE)
-- =========================================
local optionsPanel = CreateFrame("Frame", "BreadAndBloodOptionsPanel", UIParent)
optionsPanel.name = "BreadAndBlood"

local title = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Bread & Blood Settings")

local sourceOptions = {"hunger", "thirst", "fatigue", "none"}
local sourceLabels = {hunger = "Hunger", thirst = "Thirst", fatigue = "Fatigue", none = "Disabled"}

local function CreateCycleButton(name, parent, labelText, dbKey, yOffset, xOffset, tooltipText)
    local btn = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    
    btn:SetPoint("TOPLEFT", xOffset or 16, yOffset)
    btn:SetSize(100, 22)
    
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    btn:SetBackdropColor(0.2, 0.2, 0.2, 1)
    btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 2)
    label:SetText(labelText)
    
    btn:SetScript("OnShow", function(self)
        if BreadAndBloodDB and BreadAndBloodDB.config then
            local val = BreadAndBloodDB.config[dbKey] or "none"
            self:SetText(sourceLabels[val])
        end
    end)
    btn:SetScript("OnClick", function(self)
        if BreadAndBloodDB and BreadAndBloodDB.config then
            local currentVal = BreadAndBloodDB.config[dbKey] or "none"
            local nextIdx = 1
            for i, v in ipairs(sourceOptions) do
                if v == currentVal then nextIdx = i + 1 break end
            end
            if nextIdx > #sourceOptions then nextIdx = 1 end
            local newVal = sourceOptions[nextIdx]
            BreadAndBloodDB.config[dbKey] = newVal
            self:SetText(sourceLabels[newVal])
            ApplyPenalties()
        end
    end)
    
    -- Initialize text to prevent empty red bars on first load
    local initVal = "none"
    if defaultDB and defaultDB.config then initVal = defaultDB.config[dbKey] or "none" end
    btn:SetText(sourceLabels[initVal])

    if tooltipText then
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end
    return btn
end

local function CreateSlider(name, parent, labelText, dbKey, minVal, maxVal, yOffset, xOffset, tooltipText)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", xOffset or 16, yOffset)
    slider:SetSize(140, 17)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(1)
    
    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    slider:SetBackdropColor(0.1, 0.1, 0.1, 1)
    slider:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local thumb = slider:GetThumbTexture()
    if not thumb then
        thumb = slider:CreateTexture(nil, "ARTWORK")
        thumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
        thumb:SetSize(16, 16)
        slider:SetThumbTexture(thumb)
    end
    
    if _G[slider:GetName() .. "Low"] then _G[slider:GetName() .. "Low"]:SetText(minVal) end
    if _G[slider:GetName() .. "High"] then _G[slider:GetName() .. "High"]:SetText(maxVal) end

    local textObj = _G[slider:GetName() .. "Text"]
    if not textObj then
        textObj = slider:CreateFontString(slider:GetName() .. "Text", "OVERLAY", "GameFontNormal")
        textObj:SetPoint("BOTTOM", slider, "TOP", 0, 2)
    end

    slider:SetScript("OnShow", function(self)
        if BreadAndBloodDB and BreadAndBloodDB.config then
            local val = BreadAndBloodDB.config[dbKey] or minVal
            self:SetValue(val)
            _G[self:GetName() .. "Text"]:SetText(labelText .. ": " .. val)
        end
    end)

    slider:SetScript("OnValueChanged", function(self, value)
        local val = math.floor(value)
        if BreadAndBloodDB and BreadAndBloodDB.config then
            BreadAndBloodDB.config[dbKey] = val
        end
        _G[self:GetName() .. "Text"]:SetText(labelText .. ": " .. val)
    end)
    if tooltipText then
        slider:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        slider:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end
    return slider
end

-- Penalties Checkboxes (Left Column)
local cb1 = CreateCycleButton("BnBOptCB1", optionsPanel, "Action Bars", "sourceActionBars", -50, 16, "Select which stat controls the fading of your action bars.")
local cb2 = CreateCycleButton("BnBOptCB2", optionsPanel, "Unit Frames", "sourceUnitFrames", -85, 16, "Select which stat controls the fading of player and target frames.")
local cb3 = CreateCycleButton("BnBOptCB3", optionsPanel, "Minimap", "sourceMinimap", -120, 16, "Select which stat controls the fading of the minimap.")
local cb4 = CreateCycleButton("BnBOptCB4", optionsPanel, "World Map", "sourceWorldMap", -155, 16, "Select which stat prevents you from opening the world map.")
local cb5 = CreateCycleButton("BnBOptCB5", optionsPanel, "Combat Errors", "sourceCombatError", -190, 16, "Select which stat causes random spellcasting failures (fizzles).")

-- Thresholds Sliders (Right Column)
local s5 = CreateSlider("BnBOptS5", optionsPanel, "Threshold (%)", "threshActionBars", 5, 90, -50, 250, "If the stat falls below this %, your action bars will completely fade out.")
local s6 = CreateSlider("BnBOptS6", optionsPanel, "Threshold (%)", "threshUnitFrames", 5, 90, -85, 250, "If the stat falls below this %, your unit frames will completely fade out.")
local s7 = CreateSlider("BnBOptS7", optionsPanel, "Threshold (%)", "threshMinimap", 5, 90, -120, 250, "If the stat falls below this %, your minimap will completely fade out.")
local s8 = CreateSlider("BnBOptS8", optionsPanel, "Threshold (%)", "threshWorldMap", 5, 90, -155, 250, "If the stat falls below this %, opening the world map will fail.")
local s9 = CreateSlider("BnBOptS9", optionsPanel, "Threshold (%)", "threshCombatError", 5, 90, -190, 250, "If the stat falls below this %, your spells have a chance to fizzle.")

-- Global Rates (Bottom Rows)
local rateTitle = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
rateTitle:SetPoint("TOPLEFT", 16, -230)
rateTitle:SetText("Global Drop Rates & Effects")

local s1 = CreateSlider("BnBOptS1", optionsPanel, "Hunger Drain Speed", "hungerRate", 1, 10, -255, 16, "1 = Slowest, 10 = Fastest hunger drain speed.")
local s2 = CreateSlider("BnBOptS2", optionsPanel, "Thirst Drain Speed", "thirstRate", 1, 10, -255, 250, "1 = Slowest, 10 = Fastest thirst drain speed.")
local s3 = CreateSlider("BnBOptS3", optionsPanel, "Fatigue Drain Speed", "fatigueRate", 1, 10, -300, 16, "1 = Slowest, 10 = Fastest fatigue drain speed when not resting.")
local s4 = CreateSlider("BnBOptS4", optionsPanel, "Global Effect Threshold", "effectThreshold", 5, 50, -300, 250, "At what % the character starts groaning, seeing red vignettes, or blinking.")

local function CreateCheckBox(name, parent, labelText, dbKey, yOffset, xOffset, tooltipText)
    local cb = CreateFrame("CheckButton", name, parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", xOffset or 16, yOffset)
    _G[cb:GetName() .. "Text"]:SetText(labelText)
    
    cb:SetScript("OnShow", function(self)
        if BreadAndBloodDB and BreadAndBloodDB.config then
            self:SetChecked(BreadAndBloodDB.config[dbKey] == "enabled")
        end
    end)
    
    cb:SetScript("OnClick", function(self)
        if BreadAndBloodDB and BreadAndBloodDB.config then
            BreadAndBloodDB.config[dbKey] = self:GetChecked() and "enabled" or "none"
        end
    end)
    
    if tooltipText then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end
    return cb
end

local cb6 = CreateCheckBox("BnBOptCB6", optionsPanel, "Heavy Load Run Penalty", "heavyLoadPenalty", -340, 16, "If your bags are >90% full and you run, fatigue drains incredibly fast.")
local cb7 = CreateCheckBox("BnBOptCB7", optionsPanel, "Wound System", "woundSystem", -365, 16, "Enables the wound system (bleeding from massive damage, requires bandaging).")
local cb11 = CreateCheckBox("BnBOptCB11", optionsPanel, "Always Show Bars", "alwaysShowBars", -390, 16, "If disabled, bars will fade out when above 85% until hovered.")

local cb8 = CreateCheckBox("BnBOptCB8", optionsPanel, "Zone Weather", "zoneWeather", -340, 250, "Hot zones increase thirst drain. Cold zones increase hunger & fatigue drain.")
local cb9 = CreateCheckBox("BnBOptCB9", optionsPanel, "Combat Effort", "combatPenalty", -365, 250, "Being in combat increases thirst and fatigue drain.")
local cb10 = CreateCheckBox("BnBOptCB10", optionsPanel, "Movement Effort", "movementPenalty", -390, 250, "Running increases fatigue drain. Using a mount stops natural fatigue drain.")

InterfaceOptions_AddCategory(optionsPanel)

-- =========================================
-- LOGIC
-- =========================================

local function GetStatValue(sourceStr)
    if sourceStr == "hunger" then return BreadAndBloodDB.hunger end
    if sourceStr == "thirst" then return BreadAndBloodDB.thirst end
    if sourceStr == "fatigue" then return BreadAndBloodDB.fatigue end
    return 100
end

local function CalculateAlpha(statValue, threshold)
    local fadeStart = threshold + 25
    if statValue >= fadeStart then return 1.0 end
    if statValue <= threshold then return 0.0 end
    return (statValue - threshold) / 25.0
end

function ApplyPenalties()
    if not BreadAndBloodDB or not BreadAndBloodDB.config then return end

    UpdateUIBars()

    local abSource = BreadAndBloodDB.config.sourceActionBars or "none"
    if abSource ~= "none" then
        local val = GetStatValue(abSource)
        local a = CalculateAlpha(val, BreadAndBloodDB.config.threshActionBars)
        if MainMenuBar then MainMenuBar:SetAlpha(a) end
        if MultiBarBottomLeft then MultiBarBottomLeft:SetAlpha(a) end
        if MultiBarBottomRight then MultiBarBottomRight:SetAlpha(a) end
        if MultiBarRight then MultiBarRight:SetAlpha(a) end
        if MultiBarLeft then MultiBarLeft:SetAlpha(a) end
    else
        if MainMenuBar then MainMenuBar:SetAlpha(1.0) end
        if MultiBarBottomLeft then MultiBarBottomLeft:SetAlpha(1.0) end
        if MultiBarBottomRight then MultiBarBottomRight:SetAlpha(1.0) end
        if MultiBarRight then MultiBarRight:SetAlpha(1.0) end
        if MultiBarLeft then MultiBarLeft:SetAlpha(1.0) end
    end

    local ufSource = BreadAndBloodDB.config.sourceUnitFrames or "none"
    if ufSource ~= "none" then
        local val = GetStatValue(ufSource)
        local a = CalculateAlpha(val, BreadAndBloodDB.config.threshUnitFrames)
        if PlayerFrame then PlayerFrame:SetAlpha(a) end
        if TargetFrame then TargetFrame:SetAlpha(a) end
    else
        if PlayerFrame then PlayerFrame:SetAlpha(1.0) end
        if TargetFrame then TargetFrame:SetAlpha(1.0) end
    end

    if BreadAndBloodDB.hunger <= 10 then
        if ChatFrame1 then ChatFrame1:SetAlpha(0) end
    else
        if ChatFrame1 then ChatFrame1:SetAlpha(1.0) end
    end

    local mmSource = BreadAndBloodDB.config.sourceMinimap or "none"
    if mmSource ~= "none" then
        local val = GetStatValue(mmSource)
        local a = CalculateAlpha(val, BreadAndBloodDB.config.threshMinimap)
        if MinimapCluster then MinimapCluster:SetAlpha(a) end
    else
        if MinimapCluster then MinimapCluster:SetAlpha(1.0) end
    end
    
    local wmSource = BreadAndBloodDB.config.sourceWorldMap or "none"
    if wmSource ~= "none" then
        local val = GetStatValue(wmSource)
        if val <= BreadAndBloodDB.config.threshWorldMap and WorldMapFrame and WorldMapFrame:IsVisible() then
            HideUIPanel(WorldMapFrame)
            if UIErrorsFrame then UIErrorsFrame:AddMessage("You are too exhausted to focus on the map!", 1.0, 0.1, 0.1, 1.0) end
        end
    end
end

WorldMapFrame:HookScript("OnShow", function(self)
    if BreadAndBloodDB and BreadAndBloodDB.config then
        local wmSource = BreadAndBloodDB.config.sourceWorldMap or "none"
        if wmSource ~= "none" then
            local val = GetStatValue(wmSource)
            if val <= BreadAndBloodDB.config.threshWorldMap then
                HideUIPanel(WorldMapFrame)
                UIErrorsFrame:AddMessage("You are too exhausted to focus on the map!", 1.0, 0.1, 0.1, 1.0)
            end
        end
    end
end)

local activeEating = { active = false, perSec = 0, lastInt = 0, expirationTime = nil }
local activeDrinking = { active = false, perSec = 0, lastInt = 0, expirationTime = nil }
local lastHealthCache = 0

coreFrame:SetScript("OnEvent", function(self, event, ...)
    local function InitDB()
        if type(BreadAndBloodDB) ~= "table" then
            BreadAndBloodDB = {}
        end
        for k, v in pairs(defaultDB) do
            if type(v) == "table" then
                if type(BreadAndBloodDB[k]) ~= "table" then
                    BreadAndBloodDB[k] = {}
                end
                for k2, v2 in pairs(v) do
                    if BreadAndBloodDB[k][k2] == nil then
                        BreadAndBloodDB[k][k2] = v2
                    end
                end
            elseif BreadAndBloodDB[k] == nil then
                BreadAndBloodDB[k] = v
            end
        end
        
        if BreadAndBloodDB.config.hideActionBars ~= nil then
            BreadAndBloodDB.config.sourceActionBars = BreadAndBloodDB.config.hideActionBars and "hunger" or "none"
            BreadAndBloodDB.config.hideActionBars = nil
        end
        if BreadAndBloodDB.config.hideUnitFrames ~= nil then
            BreadAndBloodDB.config.sourceUnitFrames = BreadAndBloodDB.config.hideUnitFrames and "hunger" or "none"
            BreadAndBloodDB.config.hideUnitFrames = nil
        end
        if BreadAndBloodDB.config.hideMinimap ~= nil then
            BreadAndBloodDB.config.sourceMinimap = BreadAndBloodDB.config.hideMinimap and "thirst" or "none"
            BreadAndBloodDB.config.hideMinimap = nil
        end
        if BreadAndBloodDB.config.disableWorldMap ~= nil then
            BreadAndBloodDB.config.sourceWorldMap = BreadAndBloodDB.config.disableWorldMap and "thirst" or "none"
            BreadAndBloodDB.config.disableWorldMap = nil
        end
        if BreadAndBloodDB.config.fakeCombatErrors ~= nil then
            BreadAndBloodDB.config.sourceCombatError = BreadAndBloodDB.config.fakeCombatErrors and "hunger" or "none"
            BreadAndBloodDB.config.fakeCombatErrors = nil
        end
        if BreadAndBloodDB.isWounded ~= nil then BreadAndBloodDB.isWounded = nil end
    end

    if event == "VARIABLES_LOADED" then
        math.randomseed(time())
        isNearCampfireCached = IsNearCampfire()
        InitDB()
            if BreadAndBloodDB.pos then
                uiFrame:ClearAllPoints()
                uiFrame:SetPoint(BreadAndBloodDB.pos.point, UIParent, BreadAndBloodDB.pos.relativePoint, BreadAndBloodDB.pos.xOfs, BreadAndBloodDB.pos.yOfs)
            end

            print("|cff00ff00Bread & Blood Loaded!|r Type /bnb or go to Interface -> AddOns.")
            uiFrame:Show()
            ApplyPenalties()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not BreadAndBloodDB then InitDB() end
        uiFrame:Show()
        ApplyPenalties()
    elseif event == "PLAYER_LOGOUT" then
        -- Auto-saves
    elseif event == "UNIT_SPELLCAST_SENT" then
        local unit = ...
        if unit == "player" then
            isSleeping = false
            if BreadAndBloodDB and BreadAndBloodDB.config then
                local ceSource = BreadAndBloodDB.config.sourceCombatError or "none"
                if ceSource ~= "none" then
                    local val = GetStatValue(ceSource)
                    if val <= BreadAndBloodDB.config.threshCombatError then
                        if math.random(1, 100) <= 30 then
                            UIErrorsFrame:AddMessage("Your hands are shaking...", 1.0, 0.1, 0.1, 1.0)
                            PlaySound("SPELL_FAILED_FIZZLE")
                        end
                    end
                end
            end
        end
    elseif event == "PLAYER_STARTED_MOVING" or event == "PLAYER_REGEN_DISABLED" then
        isSleeping = false
    elseif event == "UNIT_HEALTH" then
        local unit = ...
        if unit == "player" then
            local currentHealth = UnitHealth("player")
            local maxHealth = UnitHealthMax("player")
            if maxHealth > 0 and lastHealthCache > 0 then
                if currentHealth < lastHealthCache then
                    local dmg = lastHealthCache - currentHealth
                    local pctLost = dmg / maxHealth
                    
                    if pctLost >= 0.05 then
                        local bloodLost = (pctLost * 100) * 0.15
                        local oldBlood = BreadAndBloodDB.blood
                        BreadAndBloodDB.blood = math.max(0, BreadAndBloodDB.blood - bloodLost)
                        UpdateUIBars()
                        
                        if oldBlood >= 50 and BreadAndBloodDB.blood < 50 and BreadAndBloodDB.config.woundSystem == "enabled" then
                            print("|cff00ff00[Bread & Blood]|r You sustained a deep wound! You are bleeding over time. Apply a bandage!")
                        elseif oldBlood >= 25 and BreadAndBloodDB.blood < 25 and BreadAndBloodDB.config.woundSystem == "enabled" then
                            print("|cff00ff00[Bread & Blood]|r You are critically wounded! You are going into shock!")
                        end
                    end
                end
            end
            lastHealthCache = currentHealth
        end
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            isNearCampfireCached = IsNearCampfire()
            local isWounded = (BreadAndBloodDB.blood < 25)
            for i=1, 40 do
                local name, _, _, _, _, _, expirationTime, _, _, _, spellId = UnitDebuff("player", i)
                if not name then break end
                if name == "Recently Bandaged" or spellId == 11196 then
                    if not lastBandageExpiration or expirationTime ~= lastBandageExpiration then
                        lastBandageExpiration = expirationTime
                        BreadAndBloodDB.blood = math.min(100, BreadAndBloodDB.blood + 30)
                        UpdateUIBars()
                        print("|cff00ff00[Bread & Blood]|r Bandage applied! Restored 30% Blood.")
                        if BreadAndBloodDB.blood >= 25 and isWounded then
                            print("|cff00ff00[Bread & Blood]|r Your wounds are closed and bleeding stopped.")
                        end
                    end
                    break
                end
            end
            
            local eating, eatIdx, drinking, drinkIdx = CheckConsumables()
            
            if eating then
                local _, _, _, _, _, duration, expirationTime = UnitAura("player", eatIdx)
                if expirationTime ~= activeEating.expirationTime then
                    local amount = GetAuraRestorePercent(eatIdx, false)
                    if not duration or duration <= 0 then duration = 15 end
                    activeEating.active = true
                    activeEating.perSec = amount / duration
                    activeEating.lastInt = math.floor(BreadAndBloodDB.hunger)
                    activeEating.expirationTime = expirationTime
                    print("|cff00ff00[Bread & Blood]|r You started eating. Replenishing hunger over " .. duration .. "s...")
                end
            elseif activeEating.active then
                activeEating.active = false
                activeEating.expirationTime = nil
            end
            
            if drinking then
                local _, _, _, _, _, duration, expirationTime = UnitAura("player", drinkIdx)
                if expirationTime ~= activeDrinking.expirationTime then
                    local amount = GetAuraRestorePercent(drinkIdx, true)
                    if not duration or duration <= 0 then duration = 15 end
                    activeDrinking.active = true
                    activeDrinking.perSec = amount / duration
                    activeDrinking.lastInt = math.floor(BreadAndBloodDB.thirst)
                    activeDrinking.expirationTime = expirationTime
                    print("|cff00ff00[Bread & Blood]|r You started drinking. Replenishing thirst over " .. duration .. "s...")
                end
            elseif activeDrinking.active then
                activeDrinking.active = false
                activeDrinking.expirationTime = nil
            end
        end
    end
end)

local isNetherEffectActive = false
local activeFatigueInt = 100
local activeBloodInt = 100
local cachedFullness = 0
local lastRunWarningTimer = 0
local lastBandageExpiration = nil
local isNearCampfireCached = false
local campfireTimer = 0

coreFrame:SetScript("OnUpdate", function(self, elapsed)
    if not BreadAndBloodDB or not BreadAndBloodDB.config then return end
    
    campfireTimer = campfireTimer + elapsed
    if campfireTimer >= 1.0 then
        isNearCampfireCached = IsNearCampfire()
        campfireTimer = 0
    end
    
    local oldHunger = math.floor(BreadAndBloodDB.hunger)
    local oldThirst = math.floor(BreadAndBloodDB.thirst)
    local oldFatigue = math.floor(BreadAndBloodDB.fatigue)
    local oldBlood = math.floor(BreadAndBloodDB.blood)
    
    local isMinorWound = (BreadAndBloodDB.config.woundSystem == "enabled" and BreadAndBloodDB.blood < 75)
    local isBleeding = (BreadAndBloodDB.config.woundSystem == "enabled" and BreadAndBloodDB.blood < 50)
    local isWounded = (BreadAndBloodDB.config.woundSystem == "enabled" and BreadAndBloodDB.blood < 25)
    
    if activeEating.active and BreadAndBloodDB.hunger < 100 then
        BreadAndBloodDB.hunger = math.min(100, BreadAndBloodDB.hunger + (activeEating.perSec * elapsed))
    end
    if activeDrinking.active and BreadAndBloodDB.thirst < 100 then
        BreadAndBloodDB.thirst = math.min(100, BreadAndBloodDB.thirst + (activeDrinking.perSec * elapsed))
    end
    
    local fRate = 0
    if IsResting() then
        fRate = 2.0
        if isSleeping then fRate = 3.0 end
    elseif isSleeping then
        fRate = 1.0
    elseif isNearCampfireCached then
        fRate = 0.5
    end
    
    local bRate = 0
    if isSleeping then
        bRate = 0.4
    end
    
    if fRate > 0 and BreadAndBloodDB.fatigue < 100 then
        BreadAndBloodDB.fatigue = math.min(100, BreadAndBloodDB.fatigue + (fRate * elapsed))
    end
    
    if bRate > 0 and BreadAndBloodDB.blood < 100 then
        BreadAndBloodDB.blood = math.min(100, BreadAndBloodDB.blood + (bRate * elapsed))
    end

    -- Smooth Drain System
    local zone = GetRealZoneText() or ""
    local isHot = hotZones[zone]
    local isCold = coldZones[zone]
    local speed = 0
    if type(GetUnitSpeed) == "function" then speed = GetUnitSpeed("player") end
    
    local isFlying = false
    if type(IsFlying) == "function" then isFlying = IsFlying() end
    local isMounted = IsMounted() or isFlying or UnitOnTaxi("player")
    
    local inCombat = InCombatLockdown()

    local weightMultiplier = 1.0 + (cachedFullness * 0.5)
    
    local hMultiplier = weightMultiplier
    local tMultiplier = weightMultiplier
    local fMultiplier = weightMultiplier

    if BreadAndBloodDB.config.zoneWeather == "enabled" then
        if isHot then tMultiplier = tMultiplier * 1.5 end
        if isCold then 
            hMultiplier = hMultiplier * 1.5
            fMultiplier = fMultiplier * 1.5
        end
    end
    
    if BreadAndBloodDB.config.combatPenalty == "enabled" then
        if inCombat then
            fMultiplier = fMultiplier * 1.5
            tMultiplier = tMultiplier * 1.5
        end
    end

    if BreadAndBloodDB.config.movementPenalty == "enabled" then
        if isMounted then
            fMultiplier = 0 -- No natural fatigue drain while mounted
        elseif speed > 0 then
            fMultiplier = fMultiplier * 1.2
        end
    end
    
    if isMinorWound then
        hMultiplier = hMultiplier * 1.2
    end
    if isBleeding then
        fMultiplier = fMultiplier * 1.5
    end
    if isWounded then
        tMultiplier = tMultiplier * 3
    end
    
    if isBleeding then
        local bleedDrainRate = 3.0 / 60.0
        BreadAndBloodDB.blood = math.max(0, BreadAndBloodDB.blood - (bleedDrainRate * elapsed))
    end

    local hDrainPerSec = (BreadAndBloodDB.config.hungerRate * hMultiplier) / 60.0
    local tDrainPerSec = (BreadAndBloodDB.config.thirstRate * tMultiplier) / 60.0
    local fDrainPerSec = (BreadAndBloodDB.config.fatigueRate * fMultiplier) / 60.0

    BreadAndBloodDB.hunger = math.max(0, BreadAndBloodDB.hunger - (hDrainPerSec * elapsed))
    BreadAndBloodDB.thirst = math.max(0, BreadAndBloodDB.thirst - (tDrainPerSec * elapsed))
    
    if fRate == 0 and fMultiplier > 0 then
        BreadAndBloodDB.fatigue = math.max(0, BreadAndBloodDB.fatigue - (fDrainPerSec * elapsed))
    end

    local isSwimming = false
    if type(IsSwimming) == "function" then isSwimming = IsSwimming() end

    if isSwimming and fRate == 0 then
        local extraDrainRate = (BreadAndBloodDB.config.fatigueRate * 2.0) / 60.0
        BreadAndBloodDB.fatigue = math.max(0, BreadAndBloodDB.fatigue - (extraDrainRate * elapsed))
    end

    local isHeavy = (BreadAndBloodDB.config.heavyLoadPenalty == "enabled" and cachedFullness >= 0.9)
    if (isHeavy or isWounded) and speed > 4.0 and not isMounted then
        local heavyDrainRate = 5.0 
        BreadAndBloodDB.fatigue = math.max(0, BreadAndBloodDB.fatigue - (heavyDrainRate * elapsed))
        
        local t = GetTime()
        if t - lastRunWarningTimer > 5 then
            lastRunWarningTimer = t
            if isWounded then
                UIErrorsFrame:AddMessage("Running while wounded causes extreme pain and exhausts you rapidly!", 1.0, 0.1, 0.1, 1.0)
            else
                UIErrorsFrame:AddMessage("Running with such a heavy load is exhausting you! You must walk!", 1.0, 0.1, 0.1, 1.0)
            end
        end
    end

    if BreadAndBloodDB.fatigue <= 15 or BreadAndBloodDB.thirst <= 15 then
        if not isNetherEffectActive then
            isNetherEffectActive = true
            SetCVar("ffxDeath", "1")
        end
    else
        if isNetherEffectActive then
            isNetherEffectActive = false
            SetCVar("ffxDeath", "0")
        end
    end

    -- Warning Icons Logic
    local thresh = BreadAndBloodDB.config.effectThreshold
    local timeSec = GetTime()
    local pulseAlpha = 0.5 + 0.5 * math.sin(timeSec * 4) 

    local isSwimmingNow = false
    if type(IsSwimming) == "function" then isSwimmingNow = IsSwimming() end
    
    if isSwimmingNow then
        if not swimStatusIcon:IsShown() then swimStatusIcon:Show() end
        swimStatusIcon:SetAlpha(pulseAlpha)
    else
        if swimStatusIcon:IsShown() then swimStatusIcon:Hide() end
    end
    
    if cachedFullness > 0.5 then
        if not weightStatusIcon:IsShown() then weightStatusIcon:Show() end
        if cachedFullness >= 0.9 then
            weightStatusIcon:SetAlpha(pulseAlpha)
        else
            weightStatusIcon:SetAlpha(0.4 + (cachedFullness - 0.5))
        end
    else
        if weightStatusIcon:IsShown() then weightStatusIcon:Hide() end
    end

    if isWounded then
        if not woundStatusIcon:IsShown() then woundStatusIcon:Show() end
        woundStatusIcon:SetAlpha(pulseAlpha)
    else
        if woundStatusIcon:IsShown() then woundStatusIcon:Hide() end
    end

    if BreadAndBloodDB.config.zoneWeather == "enabled" and (isHot or isCold) then
        if not tempStatusIcon:IsShown() then tempStatusIcon:Show() end
        tempStatusIcon:SetAlpha(pulseAlpha)
        if isHot then
            tempStatusTex:SetTexture("Interface\\Icons\\Spell_Fire_Fire")
            tempStatusIcon:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Scorching Heat", 1, 0.5, 0)
                GameTooltip:AddLine("The extreme heat drains your thirst much faster.", nil, nil, nil, true)
                GameTooltip:Show()
            end)
        else
            tempStatusTex:SetTexture("Interface\\Icons\\Spell_Frost_Frost")
            tempStatusIcon:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Freezing Cold", 0.5, 0.8, 1)
                GameTooltip:AddLine("The extreme cold drains your hunger and fatigue faster.", nil, nil, nil, true)
                GameTooltip:Show()
            end)
        end
    else
        if tempStatusIcon:IsShown() then tempStatusIcon:Hide() end
    end

    if isBleeding or BreadAndBloodDB.hunger <= (thresh + 5) then
        if not bloodPulseFrame:IsShown() then bloodPulseFrame:Show() end
        bloodPulseFrame:SetAlpha(0.2 + 0.5 * math.abs(math.sin(timeSec * 3)))
    else
        if bloodPulseFrame:IsShown() then bloodPulseFrame:Hide() end
    end

    if BreadAndBloodDB.hunger <= (thresh + 5) then
        if not hungerWarningIcon:IsShown() then hungerWarningIcon:Show() end
        hungerWarningIcon:SetAlpha(pulseAlpha)
    else
        if hungerWarningIcon:IsShown() then hungerWarningIcon:Hide() end
    end

    if BreadAndBloodDB.thirst <= (thresh + 5) then
        if not thirstWarningIcon:IsShown() then thirstWarningIcon:Show() end
        thirstWarningIcon:SetAlpha(pulseAlpha)
    else
        if thirstWarningIcon:IsShown() then thirstWarningIcon:Hide() end
    end

    if BreadAndBloodDB.fatigue <= (thresh + 5) then
        if not fatigueWarningIcon:IsShown() then fatigueWarningIcon:Show() end
        fatigueWarningIcon:SetAlpha(pulseAlpha)
    else
        if fatigueWarningIcon:IsShown() then fatigueWarningIcon:Hide() end
    end
    
    if isBlinking then
        blinkTimer = blinkTimer - elapsed
        if blinkTimer <= 0 then
            isBlinking = false
            blinkFrame:SetAlpha(0)
            blinkFrame:Hide()
        else
            local passed = 2.0 - blinkTimer
            local alpha = 0
            if passed < 0.6 then
                alpha = passed / 0.6
            elseif passed < 0.8 then
                alpha = 1.0
            else
                alpha = 1.0 - ((passed - 0.8) / 1.2)
            end
            if alpha > 1 then alpha = 1 end
            if alpha < 0 then alpha = 0 end
            blinkFrame:SetAlpha(alpha)
        end
    end

    effectTimer = effectTimer + elapsed
    if effectTimer >= 5 then
        effectTimer = 0
        cachedFullness = GetBagFullness()
        local thresh = BreadAndBloodDB.config.effectThreshold
        
        if isWounded then
            if math.random(1, 100) <= 15 then
                PlaySoundFile("Interface\\AddOns\\BreadAndBlood\\Sounds\\wound.wav")
                UIErrorsFrame:AddMessage("Your wounds are bleeding... You need a bandage or a long rest!", 1.0, 0.0, 0.0, 1.0)
            end
        end
        
        if BreadAndBloodDB.hunger <= thresh then
            local roll = math.random(1, 100)
            if roll <= 20 then
                PlaySoundFile("Interface\\AddOns\\BreadAndBlood\\Sounds\\hunger.wav")
                UIErrorsFrame:AddMessage("Your stomach growls loudly...", 1.0, 0.5, 0.0, 1.0)
            elseif roll <= 35 then
                PlaySoundFile("Interface\\AddOns\\BreadAndBlood\\Sounds\\hunger.wav")
                UIErrorsFrame:AddMessage("You are starving!", 1.0, 0.5, 0.0, 1.0)
            end
        end

        if BreadAndBloodDB.thirst <= thresh then
            if math.random(1, 100) <= 20 then
                PlaySoundFile("Interface\\AddOns\\BreadAndBlood\\Sounds\\thirst.wav")
                UIErrorsFrame:AddMessage("You are extremely thirsty!", 1.0, 0.5, 0.0, 1.0)
            end
        end
        
        if BreadAndBloodDB.fatigue <= 0 then
            if not InCombatLockdown() and not isSleeping then
                PlaySoundFile("Interface\\AddOns\\BreadAndBlood\\Sounds\\fatigue.wav")
                isForcedSit = true
                DoEmote("SIT")
                isSleeping = false
                isForcedSit = false
                UIErrorsFrame:AddMessage("You collapse from exhaustion!", 1.0, 0.0, 0.0, 1.0)
            end
        elseif BreadAndBloodDB.fatigue <= 10 then
            if not InCombatLockdown() and not isSleeping then
                if math.random(1, 100) <= 15 then
                    PlaySoundFile("Interface\\AddOns\\BreadAndBlood\\Sounds\\fatigue.wav")
                    DoEmote("YAWN")
                    isForcedSit = true
                    DoEmote("SIT")
                    isSleeping = false
                    isForcedSit = false
                    UIErrorsFrame:AddMessage("You are too exhausted to stand...", 1.0, 0.0, 0.0, 1.0)
                end
            end
        end
        
        if BreadAndBloodDB.fatigue <= (thresh + 10) then
            if not isBlinking and math.random(1, 100) <= 20 then
                PlaySoundFile("Interface\\AddOns\\BreadAndBlood\\Sounds\\fatigue.wav")
                isBlinking = true
                blinkTimer = 2.0
                blinkFrame:SetAlpha(0)
                blinkFrame:Show()
                UIErrorsFrame:AddMessage("Your eyes are starting to close from exhaustion...", 1.0, 0.5, 0.0, 1.0)
            end
        end
        
    end

    if math.floor(BreadAndBloodDB.hunger) ~= oldHunger or
       math.floor(BreadAndBloodDB.thirst) ~= oldThirst or
       math.floor(BreadAndBloodDB.fatigue) ~= oldFatigue or
       math.floor(BreadAndBloodDB.blood) ~= oldBlood then
        ApplyPenalties()
    end
    
    if BreadAndBloodDB.config.sourceWorldMap and BreadAndBloodDB.config.sourceWorldMap ~= "none" then
        local val = GetStatValue(BreadAndBloodDB.config.sourceWorldMap)
        if val <= BreadAndBloodDB.config.threshWorldMap and WorldMapFrame:IsVisible() then
            HideUIPanel(WorldMapFrame)
        end
    end
end)

SLASH_BREADANDBLOOD1 = "/bnb"
SlashCmdList["BREADANDBLOOD"] = function(msg)
    local cmd, arg1, arg2, arg3 = strsplit(" ", msg)
    if cmd == "test" then
        if arg1 and arg2 and arg3 then
            BreadAndBloodDB.hunger = tonumber(arg1) or BreadAndBloodDB.hunger
            BreadAndBloodDB.thirst = tonumber(arg2) or BreadAndBloodDB.thirst
            BreadAndBloodDB.fatigue = tonumber(arg3) or BreadAndBloodDB.fatigue
            print("|cff00ff00[Bread & Blood]|r Test values applied.")
            ApplyPenalties()
        else
            print("|cff00ff00[Bread & Blood]|r Example: /bnb test 45 45 45")
        end
    elseif cmd == "reset" then
        BreadAndBloodDB = nil
        print("|cff00ff00[Bread & Blood]|r Settings and position reset. Reloading UI...")
        ReloadUI()
    else
        print("|cff00ff00[Bread & Blood]|r Options:")
        print(" /bnb test <hunger> <thirst> <fatigue> - Set test values")
        print(" /bnb reset - Reset all settings and UI positions")
        print(" Or go to ESC -> Interface -> AddOns -> BreadAndBlood for settings.")
    end
end
