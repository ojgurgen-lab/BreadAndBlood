-- Bread and Blood Addon for WoW 3.3.5a

local defaultDB = {
    hunger = 100,
    thirst = 100,
    fatigue = 100,
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
    }
}

local UPDATE_INTERVAL = 60
local timeSinceLastUpdate = 0
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
        
        if not isEating and (name:find("Food") or (icon and (icon:find("INV_Misc_Food") or icon:find("Spell_Misc_Food")))) then
            isEating = true
            eatIdx = i
        end
        
        if not isDrinking and (name:find("Drink") or (icon and icon:find("INV_Drink"))) then
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
        local name, _, icon = UnitAura("player", i)
        if not name then break end
        local lName = name:lower()
        local lIcon = (icon and icon:lower()) or ""
        
        if lName:find("campfire") or lName:find("cozy") or lName:find("fire") or lIcon:find("campfire") then
            return true
        end
    end
    return false
end

local coreFrame = CreateFrame("Frame")
coreFrame:RegisterEvent("ADDON_LOADED")
coreFrame:RegisterEvent("PLAYER_LOGOUT")
coreFrame:RegisterEvent("UNIT_AURA")
coreFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
coreFrame:RegisterEvent("PLAYER_STARTED_MOVING")
coreFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
coreFrame:RegisterEvent("CHAT_MSG_TEXT_EMOTE")

local isForcedSit = false

hooksecurefunc("DoEmote", function(emote)
    if type(emote) == "string" then
        emote = emote:upper()
        if (emote == "SLEEP" or emote == "SIT") and not isForcedSit then
            isSleeping = true
        end
    end
end)

if SlashCmdList["SLEEP"] then hooksecurefunc(SlashCmdList, "SLEEP", function() isSleeping = true end) end
if SlashCmdList["SIT"] then hooksecurefunc(SlashCmdList, "SIT", function() isSleeping = true end) end

-- =========================================
-- VISUAL UI (DRAGGABLE BARS)
-- =========================================
local uiFrame = CreateFrame("Frame", "BreadAndBloodUIFrame", UIParent)
uiFrame:SetWidth(164)
uiFrame:SetHeight(68)
uiFrame:SetPoint("CENTER", 0, 0)
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

uiFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
uiFrame:SetBackdropColor(0, 0, 0, 0.7)

local function CreateNicerBar(parent, yOffset, r, g, b, label)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetWidth(148)
    bar:SetHeight(14)
    bar:SetPoint("TOP", parent, "TOP", 0, yOffset)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(r, g, b)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(100)
    
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bg:SetVertexColor(r * 0.3, g * 0.3, b * 0.3, 0.8)
    
    local border = CreateFrame("Frame", nil, bar)
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    border:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    text:SetText(label .. ": 100%")
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 1)
    
    return bar, text
end

local hungerBar, hungerText = CreateNicerBar(uiFrame, -8, 0.8, 0.3, 0.1, "Hunger")
local thirstBar, thirstText = CreateNicerBar(uiFrame, -28, 0.1, 0.5, 0.9, "Thirst")
local fatigueBar, fatigueText = CreateNicerBar(uiFrame, -48, 0.7, 0.7, 0.2, "Fatigue")

local blinkFrame = CreateFrame("Frame", "BreadAndBloodBlinkFrame", WorldFrame)
blinkFrame:SetAllPoints(WorldFrame)
blinkFrame:SetFrameStrata("TOOLTIP")
blinkFrame:SetAlpha(0)
blinkFrame:Hide()
local blinkTexture = blinkFrame:CreateTexture(nil, "BACKGROUND")
blinkTexture:SetAllPoints(blinkFrame)
blinkTexture:SetTexture(0, 0, 0, 1)

local hungerWarningIcon = CreateFrame("Frame", "BnBHungerWarning", UIParent)
hungerWarningIcon:SetSize(64, 64)
hungerWarningIcon:SetPoint("CENTER", -80, 150)
hungerWarningIcon:SetAlpha(0)
hungerWarningIcon:Hide()
local hwTexture = hungerWarningIcon:CreateTexture(nil, "ARTWORK")
hwTexture:SetAllPoints()
hwTexture:SetTexture("Interface\\Icons\\INV_Misc_Food_15")

local thirstWarningIcon = CreateFrame("Frame", "BnBThirstWarning", UIParent)
thirstWarningIcon:SetSize(64, 64)
thirstWarningIcon:SetPoint("CENTER", 0, 150)
thirstWarningIcon:SetAlpha(0)
thirstWarningIcon:Hide()
local twTexture = thirstWarningIcon:CreateTexture(nil, "ARTWORK")
twTexture:SetAllPoints()
twTexture:SetTexture("Interface\\Icons\\INV_Drink_08")

local fatigueWarningIcon = CreateFrame("Frame", "BnBFatigueWarning", UIParent)
fatigueWarningIcon:SetSize(64, 64)
fatigueWarningIcon:SetPoint("CENTER", 80, 150)
fatigueWarningIcon:SetAlpha(0)
fatigueWarningIcon:Hide()
local fwTexture = fatigueWarningIcon:CreateTexture(nil, "ARTWORK")
fwTexture:SetAllPoints()
fwTexture:SetTexture("Interface\\Icons\\Spell_Nature_Sleep")

local function UpdateUIBars()
    if not BreadAndBloodDB then return end
    hungerBar:SetValue(BreadAndBloodDB.hunger)
    hungerText:SetText("Hunger: " .. BreadAndBloodDB.hunger .. "%")
    
    thirstBar:SetValue(BreadAndBloodDB.thirst)
    thirstText:SetText("Thirst: " .. BreadAndBloodDB.thirst .. "%")
    
    fatigueBar:SetValue(BreadAndBloodDB.fatigue)
    fatigueText:SetText("Fatigue: " .. BreadAndBloodDB.fatigue .. "%")
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
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(1)
    _G[slider:GetName() .. "Low"]:SetText(minVal)
    _G[slider:GetName() .. "High"]:SetText(maxVal)

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
local cb2 = CreateCycleButton("BnBOptCB2", optionsPanel, "Unit Frames", "sourceUnitFrames", -95, 16, "Select which stat controls the fading of player and target frames.")
local cb3 = CreateCycleButton("BnBOptCB3", optionsPanel, "Minimap", "sourceMinimap", -140, 16, "Select which stat controls the fading of the minimap.")
local cb4 = CreateCycleButton("BnBOptCB4", optionsPanel, "World Map", "sourceWorldMap", -185, 16, "Select which stat prevents you from opening the world map.")
local cb5 = CreateCycleButton("BnBOptCB5", optionsPanel, "Combat Errors", "sourceCombatError", -230, 16, "Select which stat causes random spellcasting failures (fizzles).")

-- Thresholds Sliders (Right Column)
local s5 = CreateSlider("BnBOptS5", optionsPanel, "Threshold (%)", "threshActionBars", 5, 90, -55, 250, "If the stat falls below this %, your action bars will completely fade out.")
local s6 = CreateSlider("BnBOptS6", optionsPanel, "Threshold (%)", "threshUnitFrames", 5, 90, -100, 250, "If the stat falls below this %, your unit frames will completely fade out.")
local s7 = CreateSlider("BnBOptS7", optionsPanel, "Threshold (%)", "threshMinimap", 5, 90, -145, 250, "If the stat falls below this %, your minimap will completely fade out.")
local s8 = CreateSlider("BnBOptS8", optionsPanel, "Threshold (%)", "threshWorldMap", 5, 90, -190, 250, "If the stat falls below this %, opening the world map will fail.")
local s9 = CreateSlider("BnBOptS9", optionsPanel, "Threshold (%)", "threshCombatError", 5, 90, -235, 250, "If the stat falls below this %, your spells have a chance to fizzle.")

-- Global Rates (Bottom Rows)
local rateTitle = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
rateTitle:SetPoint("TOPLEFT", 16, -280)
rateTitle:SetText("Global Drop Rates & Effects")

local s1 = CreateSlider("BnBOptS1", optionsPanel, "Hunger Rate (/min)", "hungerRate", 1, 10, -310, 16, "How much hunger is lost per minute.")
local s2 = CreateSlider("BnBOptS2", optionsPanel, "Thirst Rate (/min)", "thirstRate", 1, 10, -310, 200, "How much thirst is lost per minute.")
local s3 = CreateSlider("BnBOptS3", optionsPanel, "Fatigue Rate (/min)", "fatigueRate", 1, 10, -360, 16, "How much fatigue is lost per minute when not resting.")
local s4 = CreateSlider("BnBOptS4", optionsPanel, "Global Effect Threshold", "effectThreshold", 5, 50, -360, 200, "At what % the character starts groaning, seeing red vignettes, or blinking.")

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
        MainMenuBar:SetAlpha(a)
        MultiBarBottomLeft:SetAlpha(a)
        MultiBarBottomRight:SetAlpha(a)
        MultiBarRight:SetAlpha(a)
        MultiBarLeft:SetAlpha(a)
    else
        MainMenuBar:SetAlpha(1.0)
        MultiBarBottomLeft:SetAlpha(1.0)
        MultiBarBottomRight:SetAlpha(1.0)
        MultiBarRight:SetAlpha(1.0)
        MultiBarLeft:SetAlpha(1.0)
    end

    local ufSource = BreadAndBloodDB.config.sourceUnitFrames or "none"
    if ufSource ~= "none" then
        local val = GetStatValue(ufSource)
        local a = CalculateAlpha(val, BreadAndBloodDB.config.threshUnitFrames)
        PlayerFrame:SetAlpha(a)
        TargetFrame:SetAlpha(a)
    else
        PlayerFrame:SetAlpha(1.0)
        TargetFrame:SetAlpha(1.0)
    end

    if BreadAndBloodDB.hunger <= 10 then
        ChatFrame1:SetAlpha(0)
    else
        ChatFrame1:SetAlpha(1.0)
    end

    local mmSource = BreadAndBloodDB.config.sourceMinimap or "none"
    if mmSource ~= "none" then
        local val = GetStatValue(mmSource)
        local a = CalculateAlpha(val, BreadAndBloodDB.config.threshMinimap)
        MinimapCluster:SetAlpha(a)
    else
        MinimapCluster:SetAlpha(1.0)
    end
    
    local wmSource = BreadAndBloodDB.config.sourceWorldMap or "none"
    if wmSource ~= "none" then
        local val = GetStatValue(wmSource)
        if val <= BreadAndBloodDB.config.threshWorldMap and WorldMapFrame:IsVisible() then
            HideUIPanel(WorldMapFrame)
            UIErrorsFrame:AddMessage("You are too exhausted to focus on the map!", 1.0, 0.1, 0.1, 1.0)
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

local isEatingNow = false
local isDrinkingNow = false

coreFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "BreadAndBlood" then
            if not BreadAndBloodDB then BreadAndBloodDB = defaultDB end
            -- Validate config
            if not BreadAndBloodDB.config then BreadAndBloodDB.config = defaultDB.config end
            -- Inject missing thresholds if updating from older version
            for k, v in pairs(defaultDB.config) do
                if BreadAndBloodDB.config[k] == nil then
                    BreadAndBloodDB.config[k] = v
                end
            end
            
            -- Migrate old boolean config to new string config
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
            
            if not BreadAndBloodDB.hunger then BreadAndBloodDB.hunger = 100 end
            if not BreadAndBloodDB.thirst then BreadAndBloodDB.thirst = 100 end
            if not BreadAndBloodDB.fatigue then BreadAndBloodDB.fatigue = 100 end
            
            if BreadAndBloodDB.pos then
                uiFrame:ClearAllPoints()
                uiFrame:SetPoint(BreadAndBloodDB.pos.point, UIParent, BreadAndBloodDB.pos.relativePoint, BreadAndBloodDB.pos.xOfs, BreadAndBloodDB.pos.yOfs)
            end

            print("|cff00ff00Bread & Blood Loaded!|r Type /bnb or go to Interface -> AddOns.")
            ApplyPenalties()
        end
    elseif event == "PLAYER_LOGOUT" then
        -- Auto-saves
    elseif event == "CHAT_MSG_TEXT_EMOTE" then
        local msg = ...
        local lmsg = msg:lower()
        if lmsg:find("sleep") or lmsg:find("sit") then
            isSleeping = true
        end
    elseif event == "UNIT_SPELLCAST_SENT" then
        local unit = ...
        if unit == "player" and BreadAndBloodDB and BreadAndBloodDB.config then
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
    elseif event == "PLAYER_STARTED_MOVING" or event == "PLAYER_REGEN_DISABLED" then
        isSleeping = false
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            local eating, eatIdx, drinking, drinkIdx = CheckConsumables()
            
            if eating and not isEatingNow then
                local amount = GetAuraRestorePercent(eatIdx, false)
                BreadAndBloodDB.hunger = math.min(100, BreadAndBloodDB.hunger + amount)
                print("|cff00ff00[Bread & Blood]|r You ate some food (Quality: +" .. amount .. "%). Hunger: " .. BreadAndBloodDB.hunger .. "%")
                ApplyPenalties()
            end
            isEatingNow = eating
            
            if drinking and not isDrinkingNow then
                local amount = GetAuraRestorePercent(drinkIdx, true)
                BreadAndBloodDB.thirst = math.min(100, BreadAndBloodDB.thirst + amount)
                print("|cff00ff00[Bread & Blood]|r You drank something (Quality: +" .. amount .. "%). Thirst: " .. BreadAndBloodDB.thirst .. "%")
                ApplyPenalties()
            end
            isDrinkingNow = drinking
        end
    end
end)

coreFrame:SetScript("OnUpdate", function(self, elapsed)
    if not BreadAndBloodDB or not BreadAndBloodDB.config then return end
    
    -- Warning Icons Logic
    local thresh = BreadAndBloodDB.config.effectThreshold
    local timeSec = GetTime()
    local pulseAlpha = 0.5 + 0.5 * math.sin(timeSec * 4) 

    if BreadAndBloodDB.hunger <= (thresh + 5) then
        hungerWarningIcon:Show()
        hungerWarningIcon:SetAlpha(pulseAlpha)
    else
        hungerWarningIcon:Hide()
    end

    if BreadAndBloodDB.thirst <= (thresh + 5) then
        thirstWarningIcon:Show()
        thirstWarningIcon:SetAlpha(pulseAlpha)
    else
        thirstWarningIcon:Hide()
    end

    if BreadAndBloodDB.fatigue <= (thresh + 5) then
        fatigueWarningIcon:Show()
        fatigueWarningIcon:SetAlpha(pulseAlpha)
    else
        fatigueWarningIcon:Hide()
    end
    
    if isBlinking then
        blinkTimer = blinkTimer - elapsed
        if blinkTimer <= 0 then
            isBlinking = false
            blinkFrame:SetAlpha(0)
            blinkFrame:Hide()
        end
    end

    effectTimer = effectTimer + elapsed
    if effectTimer >= 5 then
        effectTimer = 0
        local thresh = BreadAndBloodDB.config.effectThreshold
        
        if BreadAndBloodDB.hunger <= thresh then
            local roll = math.random(1, 100)
            if roll <= 20 then
                PlaySoundFile("Interface\\AddOns\\BreadAndBlood\\Sounds\\hunger.wav")
                DoEmote("GROAN")
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
                    isForcedSit = false
                    UIErrorsFrame:AddMessage("You are too exhausted to stand...", 1.0, 0.0, 0.0, 1.0)
                end
            end
        end
        
        if BreadAndBloodDB.hunger <= (thresh + 5) then
            if LowHealthFrame then
                LowHealthFrame:SetAlpha(1)
                LowHealthFrame:Show()
            end
        else
            if LowHealthFrame then
                LowHealthFrame:Hide()
            end
        end
        
        if BreadAndBloodDB.fatigue <= (thresh + 10) then
            if not isBlinking and math.random(1, 100) <= 20 then
                PlaySoundFile("Interface\\AddOns\\BreadAndBlood\\Sounds\\fatigue.wav")
                isBlinking = true
                blinkTimer = 1.0
                blinkFrame:Show()
                blinkFrame:SetAlpha(1)
                UIErrorsFrame:AddMessage("Your eyes are starting to close from exhaustion...", 1.0, 0.5, 0.0, 1.0)
            end
        end
        
        if IsResting() then
            if BreadAndBloodDB.fatigue < 100 then
                BreadAndBloodDB.fatigue = math.min(100, BreadAndBloodDB.fatigue + 10)
                UpdateUIBars()
            end
        elseif IsNearCampfire() or isSleeping then
            if BreadAndBloodDB.fatigue < 100 then
                BreadAndBloodDB.fatigue = math.min(100, BreadAndBloodDB.fatigue + 5)
                UpdateUIBars()
            end
        end
    end

    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate >= UPDATE_INTERVAL then
        timeSinceLastUpdate = 0
        
        BreadAndBloodDB.hunger = math.max(0, BreadAndBloodDB.hunger - BreadAndBloodDB.config.hungerRate)
        BreadAndBloodDB.thirst = math.max(0, BreadAndBloodDB.thirst - BreadAndBloodDB.config.thirstRate)
        
        if not (IsResting() or IsNearCampfire() or isSleeping) then
            BreadAndBloodDB.fatigue = math.max(0, BreadAndBloodDB.fatigue - BreadAndBloodDB.config.fatigueRate)
        end
        
        if BreadAndBloodDB.hunger == BreadAndBloodDB.config.threshActionBars then
            UIErrorsFrame:AddMessage("You are starving!", 1.0, 0.5, 0.0, 1.0)
        end
        if BreadAndBloodDB.thirst == BreadAndBloodDB.config.threshMinimap then
            UIErrorsFrame:AddMessage("You are extremely thirsty!", 1.0, 0.5, 0.0, 1.0)
        end
        if BreadAndBloodDB.fatigue == 25 then
            UIErrorsFrame:AddMessage("You are exhausted, your eyes are closing...", 1.0, 0.5, 0.0, 1.0)
        end
        
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
    else
        print("|cff00ff00[Bread & Blood]|r Go to ESC -> Interface -> AddOns -> BreadAndBlood for settings.")
    end
end
