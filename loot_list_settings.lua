local _, addon = ...
addon.ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local panel, durationSlider, durationLabel, opacitySlider, opacityLabel
local checks = {}
local MIN_DURATION, MAX_DURATION, DEFAULT_DURATION = 1, 30, 5
local MIN_OPACITY, MAX_OPACITY, DEFAULT_OPACITY = 10, 100, 100
local QUALITY_NAMES = { [0] = "Poor / Junk", "Common", "Uncommon", "Rare", "Epic",
    "Legendary" }

local function normalizeNumber(value, minimum, maximum, default)
    if type(value) ~= "number" or value ~= value then return default end
    return math.max(minimum, math.min(maximum, math.floor(value + 0.5)))
end

function addon.InitializeSettingsData()
    LootListDB.duration = normalizeNumber(LootListDB.duration, MIN_DURATION, MAX_DURATION, DEFAULT_DURATION)
    LootListDB.opacity = normalizeNumber(LootListDB.opacity, MIN_OPACITY, MAX_OPACITY, DEFAULT_OPACITY)
    if type(LootListDB.qualities) ~= "table" then LootListDB.qualities = {} end
    for quality = 0, 5 do
        if type(LootListDB.qualities[quality]) ~= "boolean" then
            LootListDB.qualities[quality] = quality > 0
        end
    end
    LootListDB.qualities[6], LootListDB.qualities[7], LootListDB.qualities[8] = nil, nil, nil
    local angle = LootListDB.minimapAngle
    if type(angle) ~= "number" or angle ~= angle or math.abs(angle) == math.huge then angle = 225 end
    LootListDB.minimapAngle = angle % 360
end

function addon.GetDuration()
    return LootListDB.duration
end

function addon.GetOpacity()
    return LootListDB.opacity / 100
end

function addon.SetOpacity(value)
    if type(value) ~= "number" or value ~= value then return end
    value = normalizeNumber(value, MIN_OPACITY, MAX_OPACITY, DEFAULT_OPACITY)
    LootListDB.opacity = value
    addon.ApplyOpacity()
    if opacitySlider and opacitySlider:GetValue() ~= value then opacitySlider:SetValue(value) end
    if opacityLabel then opacityLabel:SetText("List opacity: " .. value .. "%") end
end

function addon.IsQualityEnabled(quality)
    return LootListDB.qualities[quality] ~= false
end

function addon.SetQualityEnabled(quality, enabled)
    LootListDB.qualities[quality] = not not enabled
    if checks[quality] then checks[quality]:SetChecked(enabled) end
    addon.ApplyQualityFilters()
end

function addon.SetDuration(value)
    if type(value) ~= "number" or value ~= value then return end
    value = normalizeNumber(value, MIN_DURATION, MAX_DURATION, DEFAULT_DURATION)
    if LootListDB.duration ~= value then
        LootListDB.duration = value
        addon.ApplyDuration()
    end
    if durationSlider and durationSlider:GetValue() ~= value then durationSlider:SetValue(value) end
    if durationLabel then durationLabel:SetText("Display duration: " .. value .. " seconds") end
end

local function label(parent, text, x, y, font)
    local textFrame = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    textFrame:SetPoint("TOPLEFT", x, y)
    textFrame:SetText(text)
    return textFrame
end

local function createSlider(name, y, minimum, maximum, lowText, highText, value, onChange)
    local control = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
    control:SetSize(300, 17)
    control:SetPoint("TOPLEFT", 28, y)
    control:SetMinMaxValues(minimum, maximum)
    local low = control.Low or _G[name .. "Low"]
    local high = control.High or _G[name .. "High"]
    if low then low:SetText(lowText) end
    if high then high:SetText(highText) end
    control:SetValueStep(1)
    if control.SetObeyStepOnDrag then control:SetObeyStepOnDrag(true) end
    control:SetScript("OnValueChanged", function(_, newValue) onChange(newValue) end)
    control:SetValue(value)
    return control
end

function addon.InitializeSettingsUI()
    panel = CreateFrame("Frame", "LootListSettingsPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetSize(360, 445)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true,
        tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", 20, -18)
    icon:SetTexture(addon.ICON)
    label(panel, "Loot List Forever", 58, -23, "GameFontNormalLarge")
    label(panel, "Item qualities to display", 24, -65, "GameFontNormal")
    for quality = 0, 5 do
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetSize(26, 26)
        check:SetPoint("TOPLEFT", 22, -88 - quality * 25)
        check:SetChecked(addon.IsQualityEnabled(quality))
        local name = quality == 0 and QUALITY_NAMES[0] or _G["ITEM_QUALITY" .. quality .. "_DESC"] or QUALITY_NAMES[quality]
        local caption = label(check, name, 30, -5)
        local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if color then caption:SetTextColor(color.r, color.g, color.b) end
        check:SetScript("OnClick", function(self) addon.SetQualityEnabled(quality, self:GetChecked()) end)
        checks[quality] = check
    end
    durationLabel = label(panel, "", 24, -255, "GameFontNormal")
    durationSlider = createSlider("LootListDurationSlider", -283, MIN_DURATION, MAX_DURATION,
        "1 sec", "30 sec", addon.GetDuration(), addon.SetDuration)
    addon.SetDuration(addon.GetDuration())
    opacityLabel = label(panel, "", 24, -325, "GameFontNormal")
    opacitySlider = createSlider("LootListOpacitySlider", -353, MIN_OPACITY, MAX_OPACITY,
        "10%", "100%", LootListDB.opacity, addon.SetOpacity)
    addon.SetOpacity(LootListDB.opacity)
    local done = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    done:SetSize(100, 24)
    done:SetPoint("BOTTOMRIGHT", -24, 23)
    done:SetText("Done")
    done:SetScript("OnClick", function() panel:Hide() end)
    panel:Hide()
    panel:SetScript("OnHide", function() addon.SetUnlocked(false) end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "LootListSettingsPanel" end
end

function addon.OpenSettings()
    addon.SetUnlocked(true)
    panel:Show()
    addon.ShowPreview()
end

function addon.CloseSettings()
    panel:Hide()
end

function addon.InitializeMinimap()
    if not Minimap then return end
    local button = CreateFrame("Button", "LootListMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(addon.ICON)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    local function position()
        local angle = math.rad(LootListDB.minimapAngle)
        local x, y = math.cos(angle), math.sin(angle)
        if GetMinimapShape and GetMinimapShape() == "SQUARE" then
            local edge = math.max(math.abs(x), math.abs(y))
            x, y = x / edge, y / edge
        end
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER",
            x * (Minimap:GetWidth() / 2 + 10), y * (Minimap:GetHeight() / 2 + 10))
    end
    local function stopDrag(self) self:SetScript("OnUpdate", nil) end
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local cx, cy = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            LootListDB.minimapAngle = math.deg(math.atan2(y / scale - cy, x / scale - cx)) % 360
            position()
        end)
    end)
    button:SetScript("OnDragStop", stopDrag)
    button:SetScript("OnHide", stopDrag)
    button:SetScript("OnClick", function() addon.OpenSettings() end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Loot List Forever")
        GameTooltip:AddLine("Click to configure and unlock the list.", 1, 1, 1)
        GameTooltip:AddLine("Drag to move this minimap button.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if Minimap.HookScript then Minimap:HookScript("OnSizeChanged", position) end
    position()
    button:Show()
end
