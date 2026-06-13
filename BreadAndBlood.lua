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
        hideActionBars = true,
        hideUnitFrames = true,
        hideMinimap = true,
        disableWorldMap = true,
        fakeCombatErrors = true,
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

local function IsEating()
    for i=1, 40 do
        local name, _, icon = UnitAura("player", i)
        if not name then break end
        if name:find("Food") or (icon and (icon:find("INV_Misc_Food") or icon:find("Spell_Misc_Food"))) then
            return true
        end
    end
    return false
end

local function IsDrinking()
    for i=1, 40 do
        local name, _, icon = UnitAura("player", i)
        if not name then break end
        if name:find("Drink") or (icon and icon:find("INV_Drink")) then
            return true
        end
    end
    return false
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

hooksecurefunc("DoEmote", function(emote)
    if type(emote) == "string" then
        emote = emote:upper()
        if emote == "SLEEP" or emote == "SIT" then
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
uiFrame:SetWidth(150)
uiFrame:SetHeight(56)
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

local hungerBar = CreateFrame("StatusBar", nil, uiFrame)
hungerBar:SetWidth(138)
hungerBar:SetHeight(12)
hungerBar:SetPoint("TOP", uiFrame, "TOP", 0, -6)
hungerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
hungerBar:SetStatusBarColor(0.8, 0.4, 0.1)
hungerBar:SetMinMaxValues(0, 100)
hungerBar:SetValue(100)

local hungerText = hungerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hungerText:SetPoint("CENTER", hungerBar, "CENTER", 0, 0)
hungerText:SetText("Hunger: 100%")

local thirstBar = CreateFrame("StatusBar", nil, uiFrame)
thirstBar:SetWidth(138)
thirstBar:SetHeight(12)
thirstBar:SetPoint("TOP", hungerBar, "BOTTOM", 0, -4)
thirstBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
thirstBar:SetStatusBarColor(0.1, 0.5, 0.9)
thirstBar:SetMinMaxValues(0, 100)
thirstBar:SetValue(100)

local thirstText = thirstBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
thirstText:SetPoint("CENTER", thirstBar, "CENTER", 0, 0)
thirstText:SetText("Thirst: 100%")

local fatigueBar = CreateFrame("StatusBar", nil, uiFrame)
fatigueBar:SetWidth(138)
fatigueBar:SetHeight(12)
fatigueBar:SetPoint("TOP", thirstBar, "BOTTOM", 0, -4)
fatigueBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
fatigueBar:SetStatusBarColor(0.8, 0.8, 0.2)
fatigueBar:SetMinMaxValues(0, 100)
fatigueBar:SetValue(100)

local fatigueText = fatigueBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fatigueText:SetPoint("CENTER", fatigueBar, "CENTER", 0, 0)
fatigueText:SetText("Fatigue: 100%")

local blinkFrame = CreateFrame("Frame", "BreadAndBloodBlinkFrame", UIParent)
blinkFrame:SetAllPoints()
blinkFrame:SetFrameStrata("TOOLTIP")
blinkFrame:SetAlpha(0)
blinkFrame:Hide()
local blinkTexture = blinkFrame:CreateTexture(nil, "BACKGROUND")
blinkTexture:SetAllPoints()
blinkTexture:SetTexture(0, 0, 0, 1)

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
title:SetText("Bread and Blood Settings")

local function CreateCheckButton(name, parent, labelText, dbKey, yOffset, xOffset)
    local cb = CreateFrame("CheckButton", name, parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", xOffset or 16, yOffset)
    _G[cb:GetName() .. "Text"]:SetText(labelText)
    cb:SetScript("OnShow", function(self)
        if BreadAndBloodDB and BreadAndBloodDB.config then
            self:SetChecked(BreadAndBloodDB.config[dbKey])
        end
    end)
    cb:SetScript("OnClick", function(self)
        if BreadAndBloodDB and BreadAndBloodDB.config then
            BreadAndBloodDB.config[dbKey] = self:GetChecked() and true or false
            ApplyPenalties()
        end
    end)
    return cb
end

local function CreateSlider(name, parent, labelText, dbKey, minVal, maxVal, yOffset, xOffset)
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
    return slider
end

-- Penalties Checkboxes (Left Column)
local cb1 = CreateCheckButton("BnBOptCB1", optionsPanel, "Hide Action Bars", "hideActionBars", -60, 16)
local cb2 = CreateCheckButton("BnBOptCB2", optionsPanel, "Hide Unit Frames", "hideUnitFrames", -110, 16)
local cb3 = CreateCheckButton("BnBOptCB3", optionsPanel, "Hide Minimap", "hideMinimap", -160, 16)
local cb4 = CreateCheckButton("BnBOptCB4", optionsPanel, "Disable World Map", "disableWorldMap", -210, 16)
local cb5 = CreateCheckButton("BnBOptCB5", optionsPanel, "Fake Combat Errors", "fakeCombatErrors", -260, 16)

-- Thresholds Sliders (Right Column)
local s5 = CreateSlider("BnBOptS5", optionsPanel, "Threshold (%)", "threshActionBars", 5, 90, -65, 250)
local s6 = CreateSlider("BnBOptS6", optionsPanel, "Threshold (%)", "threshUnitFrames", 5, 90, -115, 250)
local s7 = CreateSlider("BnBOptS7", optionsPanel, "Threshold (%)", "threshMinimap", 5, 90, -165, 250)
local s8 = CreateSlider("BnBOptS8", optionsPanel, "Threshold (%)", "threshWorldMap", 5, 90, -215, 250)
local s9 = CreateSlider("BnBOptS9", optionsPanel, "Threshold (%)", "threshCombatError", 5, 90, -265, 250)

-- Global Rates (Bottom Rows)
local rateTitle = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
rateTitle:SetPoint("TOPLEFT", 16, -310)
rateTitle:SetText("Global Drop Rates & Effects")

local s1 = CreateSlider("BnBOptS1", optionsPanel, "Hunger Rate (/min)", "hungerRate", 1, 10, -340, 16)
local s2 = CreateSlider("BnBOptS2", optionsPanel, "Thirst Rate (/min)", "thirstRate", 1, 10, -340, 180)
local s3 = CreateSlider("BnBOptS3", optionsPanel, "Fatigue Rate (/min)", "fatigueRate", 1, 10, -340, 340)
local s4 = CreateSlider("BnBOptS4", optionsPanel, "Global Effect Threshold", "effectThreshold", 5, 50, -390, 16)

InterfaceOptions_AddCategory(optionsPanel)

-- =========================================
-- LOGIC
-- =========================================

function ApplyPenalties()
    if not BreadAndBloodDB or not BreadAndBloodDB.config then return end
    local h = BreadAndBloodDB.hunger
    local t = BreadAndBloodDB.thirst

    UpdateUIBars()

    if BreadAndBloodDB.config.hideActionBars and h <= BreadAndBloodDB.config.threshActionBars then
        MainMenuBar:SetAlpha(0.1)
        MultiBarBottomLeft:SetAlpha(0.1)
        MultiBarBottomRight:SetAlpha(0.1)
        MultiBarRight:SetAlpha(0.1)
        MultiBarLeft:SetAlpha(0.1)
    else
        MainMenuBar:SetAlpha(1.0)
        MultiBarBottomLeft:SetAlpha(1.0)
        MultiBarBottomRight:SetAlpha(1.0)
        MultiBarRight:SetAlpha(1.0)
        MultiBarLeft:SetAlpha(1.0)
    end

    if BreadAndBloodDB.config.hideUnitFrames and h <= BreadAndBloodDB.config.threshUnitFrames then
        PlayerFrame:SetAlpha(0)
        TargetFrame:SetAlpha(0)
    else
        PlayerFrame:SetAlpha(1.0)
        TargetFrame:SetAlpha(1.0)
    end

    if h <= 10 then
        ChatFrame1:SetAlpha(0)
    else
        ChatFrame1:SetAlpha(1.0)
    end

    if BreadAndBloodDB.config.hideMinimap and t <= BreadAndBloodDB.config.threshMinimap then
        MinimapCluster:SetAlpha(0)
    else
        MinimapCluster:SetAlpha(1.0)
    end
    
    if BreadAndBloodDB.config.disableWorldMap and t <= BreadAndBloodDB.config.threshWorldMap then
        if WorldMapFrame:IsVisible() then
            HideUIPanel(WorldMapFrame)
            UIErrorsFrame:AddMessage("You are too dehydrated to focus on the map!", 1.0, 0.1, 0.1, 1.0)
        end
    end
end

WorldMapFrame:HookScript("OnShow", function(self)
    if BreadAndBloodDB and BreadAndBloodDB.config and BreadAndBloodDB.config.disableWorldMap and BreadAndBloodDB.thirst <= BreadAndBloodDB.config.threshWorldMap then
        HideUIPanel(WorldMapFrame)
        UIErrorsFrame:AddMessage("You are too dehydrated to focus on the map!", 1.0, 0.1, 0.1, 1.0)
    end
end)

local isEatingNow = false
local isDrinkingNow = false

coreFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "BreadAndBlood" then
            if not BreadAndBloodDB then BreadAndBloodDB = defaultDB end
            if not BreadAndBloodDB.config then BreadAndBloodDB.config = defaultDB.config end
            for k, v in pairs(defaultDB.config) do
                if BreadAndBloodDB.config[k] == nil then
                    BreadAndBloodDB.config[k] = v
                end
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
        if lmsg:find("sleep") or lmsg:find("sit") or lmsg:find("uyku") or lmsg:find("otur") then
            isSleeping = true
        end
    elseif event == "UNIT_SPELLCAST_SENT" then
        local unit = ...
        if unit == "player" and BreadAndBloodDB and BreadAndBloodDB.config and BreadAndBloodDB.config.fakeCombatErrors then
            if BreadAndBloodDB.hunger <= BreadAndBloodDB.config.threshCombatError then
                if math.random(1, 100) <= 30 then
                    UIErrorsFrame:AddMessage("Your hands are shaking from starvation...", 1.0, 0.1, 0.1, 1.0)
                    PlaySound("SPELL_FAILED_FIZZLE")
                end
            end
        end
    elseif event == "PLAYER_STARTED_MOVING" or event == "PLAYER_REGEN_DISABLED" then
        isSleeping = false
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            local eating = IsEating()
            local drinking = IsDrinking()
            
            if eating and not isEatingNow then
                BreadAndBloodDB.hunger = math.min(100, BreadAndBloodDB.hunger + 25)
                print("|cff00ff00[Bread & Blood]|r You ate some food. Hunger: " .. BreadAndBloodDB.hunger .. "%")
                ApplyPenalties()
            end
            isEatingNow = eating
            
            if drinking and not isDrinkingNow then
                BreadAndBloodDB.thirst = math.min(100, BreadAndBloodDB.thirst + 25)
                print("|cff00ff00[Bread & Blood]|r You drank something. Thirst: " .. BreadAndBloodDB.thirst .. "%")
                ApplyPenalties()
            end
            isDrinkingNow = drinking
        end
    end
end)

coreFrame:SetScript("OnUpdate", function(self, elapsed)
    if not BreadAndBloodDB or not BreadAndBloodDB.config then return end
    
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
        
        if BreadAndBloodDB.hunger <= thresh or BreadAndBloodDB.thirst <= thresh or BreadAndBloodDB.fatigue <= thresh then
            PlaySound("Heartbeat")
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
                isBlinking = true
                blinkTimer = 1.0
                blinkFrame:Show()
                blinkFrame:SetAlpha(1)
            end
        end
        
        if IsResting() or IsNearCampfire() or isSleeping then
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
    
    if BreadAndBloodDB.config.disableWorldMap and BreadAndBloodDB.thirst <= BreadAndBloodDB.config.threshWorldMap and WorldMapFrame:IsVisible() then
        HideUIPanel(WorldMapFrame)
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
