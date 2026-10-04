local _, addon = ...
local WIDTH, HEIGHT, GAP = 320, 58, 5
local FADE_TIME = 0.7
local MAX_ENTRIES = 6
local active, pool, waiting = {}, {}, {}
local MAX_WAITING = 48
local anchor, mover, resizeHandle, unlocked, resizing
local MIN_SCALE, MAX_SCALE = 0.65, 1.75
local ROW_STEP = HEIGHT + GAP
local LIST_HEIGHT = MAX_ENTRIES * ROW_STEP - GAP

local function hideTooltip(row)
    if GameTooltip:IsOwned(row) then
        GameTooltip:Hide()
    end
end

local function removeRow(index)
    local row = table.remove(active, index)
    hideTooltip(row)
    row:Hide()
    row.item, row.hovered, row.tint = nil, nil, nil
    pool[#pool + 1] = row
end

local function savePosition()
    anchor:StopMovingOrSizing()
    local point, _, relativePoint, x, y = anchor:GetPoint(1)
    LootListDB.position = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function stopResize()
    if not resizing then return end
    resizing = nil
    resizeHandle:SetScript("OnUpdate", nil)
    LootListDB.scale = anchor:GetScale()
    savePosition()
end

local function startResize()
    if not unlocked then return end
    anchor:StopMovingOrSizing()
    local x, y = GetCursorPosition()
    local effective = anchor:GetEffectiveScale()
    resizing = { x = x, y = y, scale = anchor:GetScale(), effective = effective,
        left = anchor:GetLeft() * effective, top = anchor:GetTop() * effective }
    resizeHandle:SetScript("OnUpdate", function()
        local cursorX, cursorY = GetCursorPosition()
        local dx = (cursorX - resizing.x) / resizing.effective
        local dy = (resizing.y - cursorY) / resizing.effective
        local ratio = 1 + (dx * WIDTH + dy * LIST_HEIGHT) / (WIDTH * WIDTH + LIST_HEIGHT * LIST_HEIGHT)
        local scale = math.max(MIN_SCALE, math.min(MAX_SCALE, resizing.scale * ratio))
        anchor:SetScale(scale)
        anchor:ClearAllPoints()
        -- Keep the top-left fixed in screen pixels as the list grows/shrinks.
        local currentEffective = anchor:GetEffectiveScale()
        anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            resizing.left / currentEffective, resizing.top / currentEffective)
    end)
end

local function startDrag()
    if unlocked then
        stopResize()
        anchor:StartMoving()
    end
end

local function applyRowOpacity(row)
    local opacity = addon.GetOpacity()
    local color = row.tint
    if color then
        row:SetBackdropColor(0.02 + color[1] * 0.18, 0.02 + color[2] * 0.18,
            0.02 + color[3] * 0.18, 0.9 * opacity)
        row:SetBackdropBorderColor(color[1], color[2], color[3], 0.65 * opacity)
    end
    row.name:SetAlpha(opacity)
    row.details:SetAlpha(opacity)
end

function addon.ApplyOpacity()
    for _, row in ipairs(active) do applyRowOpacity(row) end
end

local function createRow()
    local row = CreateFrame("Button", nil, anchor, BackdropTemplateMixin and "BackdropTemplate" or nil)
    row:SetSize(WIDTH, HEIGHT)
    row:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    row:SetBackdropColor(0.055, 0.045, 0.035, 0.9)
    row:RegisterForDrag("LeftButton")
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnDragStart", startDrag)
    row:SetScript("OnDragStop", savePosition)
    row:SetScript("OnEnter", function(self)
        if self.item then
            self.hovered = true
            self:SetAlpha(1)
            if self.item.itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetHyperlink(self.item.itemLink)
                GameTooltip:Show()
            end
        end
    end)
    row:SetScript("OnLeave", function(self)
        hideTooltip(self)
        self.hovered = nil
        if self.item then
            -- An entry held beyond its deadline gets a final fade on release.
            self.expires = math.max(self.expires, GetTime() + FADE_TIME)
        end
    end)
    row:SetScript("OnClick", function(self)
        if self.item and self.item.itemLink and IsShiftKeyDown() and ChatEdit_InsertLink then
            ChatEdit_InsertLink(self.item.itemLink)
        end
    end)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(40, 40)
    row.icon:SetPoint("LEFT", 9, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", 59, -11)
    row.name:SetSize(WIDTH - 72, 17)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetShadowOffset(1, -1)
    row.details = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.details:SetPoint("TOPLEFT", 59, -32)
    row.details:SetSize(WIDTH - 72, 15)
    row.details:SetJustifyH("LEFT")
    row.details:SetTextColor(0.78, 0.73, 0.63)
    return row
end

local function restartRow(row)
    row.expires = GetTime() + addon.GetDuration()
    row:SetAlpha(1)
end

local function rowIsHeld(row)
    return row.hovered or (unlocked and row.item.isPreview)
end

local function slotIsBlocked(slot)
    local target = -slot * ROW_STEP
    -- Reserve the hovered row's actual position, including mid-animation.
    for _, row in ipairs(active) do
        if row.hovered and math.abs(target - row.y) < ROW_STEP then return true end
    end
    return false
end

local function update(_, elapsed)
    local now = GetTime()
    for i = #active, 1, -1 do
        local row = active[i]
        if not rowIsHeld(row) and now >= row.expires then
            removeRow(i)
        end
    end
    while #active < MAX_ENTRIES and #waiting > 0 do
        addon.ShowItem(table.remove(waiting, 1))
    end
    local nextSlot = 0
    for _, row in ipairs(active) do
        if not row.hovered then
            while slotIsBlocked(nextSlot) do nextSlot = nextSlot + 1 end
            local target = -nextSlot * ROW_STEP
            nextSlot = nextSlot + 1
            row.y = row.y + (target - row.y) * math.min(1, elapsed * 18)
            if math.abs(target - row.y) < 0.2 then row.y = target end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, row.y)
        end
        row:SetAlpha(rowIsHeld(row) and 1 or math.min(1, (row.expires - now) / FADE_TIME))
    end
    -- Only run while notifications exist: smooth movement and independent fades.
    if #active == 0 then anchor:SetScript("OnUpdate", nil) end
end

function addon.InitializeUI()
    anchor = CreateFrame("Frame", "LootListAnchor", UIParent)
    addon.lootAnchor = anchor
    anchor:SetSize(WIDTH, LIST_HEIGHT)
    local scale = LootListDB.scale
    if type(scale) ~= "number" or scale ~= scale then scale = 1 end
    anchor:SetScale(math.max(MIN_SCALE, math.min(MAX_SCALE, scale)))
    anchor:SetFrameStrata("MEDIUM")
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    local points = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true,
        CENTER = true, RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
    local pos = LootListDB.position
    if type(pos) == "table" and points[pos.point] and points[pos.relativePoint]
        and type(pos.x) == "number" and type(pos.y) == "number" then
        anchor:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        anchor:SetPoint("TOPRIGHT", UIParent, "RIGHT", -70, HEIGHT * 2)
    end
    mover = CreateFrame("Button", nil, anchor)
    mover:SetSize(WIDTH, 24)
    mover:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 3)
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", startDrag)
    mover:SetScript("OnDragStop", savePosition)
    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.06, 0.03, 0.9)
    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText("Loot List Forever — drag to move; /lootlist lock")
    mover:Hide()
    resizeHandle = CreateFrame("Button", "LootListResizeHandle", anchor)
    resizeHandle:SetSize(22, 22)
    resizeHandle:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -2, 2)
    resizeHandle:RegisterForDrag("LeftButton")
    resizeHandle:SetScript("OnDragStart", startResize)
    resizeHandle:SetScript("OnDragStop", stopResize)
    resizeHandle:SetScript("OnMouseUp", stopResize)
    resizeHandle:SetScript("OnHide", stopResize)
    local grip = resizeHandle:CreateTexture(nil, "ARTWORK")
    grip:SetAllPoints()
    grip:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    local resizeLabel = resizeHandle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resizeLabel:SetPoint("RIGHT", resizeHandle, "LEFT", -4, 0)
    resizeLabel:SetText("Resize")
    resizeHandle:Hide()
    for i = 1, MAX_ENTRIES do
        pool[i] = createRow()
        pool[i]:Hide()
    end
end

local function moneyColor(amount)
    if amount >= 10000 then return 1, 0.82, 0 end
    if amount >= 100 then return 0.75, 0.75, 0.8 end
    return 0.8, 0.5, 0.2
end

local function applyRowColor(row, r, g, b)
    row.tint = { r, g, b }
    row.name:SetTextColor(r, g, b)
    applyRowOpacity(row)
end

function addon.ShowItem(item)
    if item.kind == "money" then
        for i, row in ipairs(active) do
            if row.item.kind == "money" then
                if not row.hovered and GetTime() >= row.expires then
                    removeRow(i)
                    break
                end
                row.item.amount = row.item.amount + item.amount
                row.name:SetText(addon.FormatMoney(row.item.amount))
                applyRowColor(row, moneyColor(row.item.amount))
                restartRow(row)
                return
            end
        end
    end
    if #active == MAX_ENTRIES then
        if item.kind ~= "money" then
            if #waiting < MAX_WAITING then waiting[#waiting + 1] = item end
            return
        end
        -- Money takes the top slot; defer the bottommost unhovered item rather than lose it.
        local deferred
        for i = #active, 1, -1 do
            if not active[i].hovered and active[i].item.kind ~= "money" then deferred = i; break end
        end
        if not deferred then return end
        if #waiting == MAX_WAITING then table.remove(waiting) end
        table.insert(waiting, 1, active[deferred].item)
        removeRow(deferred)
    end
    local row = table.remove(pool)
    row.item = item
    local r, g, b = 1, 1, 1
    row.name:ClearAllPoints()
    if item.kind == "money" then
        r, g, b = moneyColor(item.amount)
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
        row.name:SetPoint("LEFT", row, "LEFT", 59, 0)
        row.name:SetText(addon.FormatMoney(item.amount))
        row.details:SetText("")
        row.details:Hide()
    else
        local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.itemQuality]
        if color then r, g, b = color.r, color.g, color.b end
        row.icon:SetTexture(item.itemIcon)
        row.name:SetPoint("TOPLEFT", 59, -11)
        row.name:SetText(item.itemName .. (item.quantity > 1 and (" x" .. item.quantity) or ""))
        row.details:SetText("ilvl " .. item.itemLevel .. "   Vendor: " .. addon.FormatMoney(item.vendorSellPrice * item.quantity))
        row.details:Show()
    end
    applyRowColor(row, r, g, b)
    local index = item.kind == "money" and 1 or (#active + 1)
    if item.kind ~= "money" then
        -- Stable descending rarity: equal qualities retain their display order.
        for i, existing in ipairs(active) do
            if existing.item.kind ~= "money" and existing.item.itemQuality < item.itemQuality then
                index = i
                break
            end
        end
    end
    row.y, row.hovered = -(index - 1) * ROW_STEP, nil
    restartRow(row)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, row.y)
    table.insert(active, index, row)
    row:Show()
    anchor:SetScript("OnUpdate", update)
end

function addon.SetUnlocked(value)
    stopResize()
    unlocked = value
    if unlocked then
        mover:Show()
        resizeHandle:Show()
    else
        for _, row in ipairs(active) do
            if row.item.isPreview then row.expires = GetTime() + addon.GetDuration() end
        end
        savePosition()
        mover:Hide()
        resizeHandle:Hide()
    end
end

function addon.ResetPosition()
    stopResize()
    anchor:StopMovingOrSizing()
    anchor:ClearAllPoints()
    anchor:SetPoint("TOPRIGHT", UIParent, "RIGHT", -70, HEIGHT * 2)
    LootListDB.position = nil
end

function addon.ApplyDuration()
    for _, row in ipairs(active) do
        restartRow(row)
    end
end

function addon.ApplyQualityFilters()
    for i = #waiting, 1, -1 do
        if not addon.IsQualityEnabled(waiting[i].itemQuality) then table.remove(waiting, i) end
    end
    for i = #active, 1, -1 do
        local item = active[i].item
        if item.kind ~= "money" and not addon.IsQualityEnabled(item.itemQuality) then
            removeRow(i)
        end
    end
end

function addon.ClearPreviews()
    for i = #waiting, 1, -1 do
        if waiting[i].isPreview then table.remove(waiting, i) end
    end
    for i = #active, 1, -1 do
        if active[i].item.isPreview then removeRow(i) end
    end
end
