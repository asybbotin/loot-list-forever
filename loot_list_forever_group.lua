local _, addon = ...
local WIDTH, HEIGHT, GAP = 320, 88, 5
local active, pool = {}, {}
local anchor, heading, resizeHandle, eventFrame, ticking, dragging, resizing
local MIN_SCALE, MAX_SCALE = 0.65, 1.75
local choices = {
    { "Need", 1, "lootroll-toast-icon-need-up" },
    { "Greed", 2, "lootroll-toast-icon-greed-up" },
    { "Pass", 0, "lootroll-toast-icon-pass-up" },
}
local RESULT_DURATION, RESULT_GRACE = 10, 5
local updateHistory
local timerGeneration = 0
local defaultRollStates, defaultRollHooks = {}, {}

-- Verified client: /dump GetBuildInfo(): 1.60.1, 70205, Oct 2 2026, 16001.
-- Reference: Gethe/wow-ui-source forever e3ecc27, LootDocumentation,
-- LootHistoryDocumentation and GroupLootFrame. Live behavior still needs testing.
local function public(value)
    return not issecretvalue or not issecretvalue(value)
end

local function number(value)
    return public(value) and type(value) == "number" and value == value
end

local function savePosition()
    anchor:StopMovingOrSizing()
    local point, _, relativePoint, x, y = anchor:GetPoint(1)
    LootListDB.groupPosition = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function stopDrag()
    if not dragging then return end
    dragging = nil
    savePosition()
end

local function stopResize()
    if not resizing then return end
    resizing = nil
    resizeHandle:SetScript("OnUpdate", nil)
    LootListDB.groupScale = anchor:GetScale()
    savePosition()
end

local function startResize()
    stopDrag()
    local x, y = GetCursorPosition()
    local effective = anchor:GetEffectiveScale()
    local height = math.max(HEIGHT, #active * (HEIGHT + GAP) - GAP)
    resizing = { x = x, y = y, scale = anchor:GetScale(), effective = effective,
        height = height, left = anchor:GetLeft() * effective, top = anchor:GetTop() * effective }
    resizeHandle:SetScript("OnUpdate", function()
        local cursorX, cursorY = GetCursorPosition()
        local dx = (cursorX - resizing.x) / resizing.effective
        local dy = (resizing.y - cursorY) / resizing.effective
        local ratio = 1 + (dx * WIDTH + dy * resizing.height) / (WIDTH * WIDTH + resizing.height * resizing.height)
        anchor:SetScale(math.max(MIN_SCALE, math.min(MAX_SCALE, resizing.scale * ratio)))
        anchor:ClearAllPoints()
        local currentEffective = anchor:GetEffectiveScale()
        anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            resizing.left / currentEffective, resizing.top / currentEffective)
    end)
end

local function classIcon(class)
    if not public(class) or type(class) ~= "string" then return "" end
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class:upper()]
    if not coords then return "" end
    -- Same class texture and coordinates as the target client's PortraitFrame.
    return string.format("|TInterface/TargetingFrame/UI-Classes-Circles:16:16:0:0:256:256:%d:%d:%d:%d|t ",
        coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256)
end

local function layout()
    anchor:SetSize(WIDTH, math.max(HEIGHT, #active * (HEIGHT + GAP) - GAP))
    for i, row in ipairs(active) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -(i - 1) * (HEIGHT + GAP))
    end
    if #active > 0 then heading:Show(); resizeHandle:Show()
    else heading:Hide(); resizeHandle:Hide() end
end

local function removeRow(index)
    local row = table.remove(active, index)
    if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
    row:Hide()
    row.roll = nil
    pool[#pool + 1] = row
    layout()
end

local function timeLeft(roll)
    if roll.preview then return math.max(0, roll.expires - GetTime()) end
    local left = GetLootRollTimeLeft(roll.id)
    if number(left) then return math.max(0, left / 1000) end
end

local function finish(roll, text, class, hasWinner)
    if roll.result then return end
    roll.result = classIcon(class) .. text
    roll.resultExpires = GetTime() + math.max(RESULT_DURATION, addon.GetDuration())
    -- Use Blizzard's positive group-roll cue; respect the normal sound settings.
    if hasWinner and PlaySound and SOUNDKIT and SOUNDKIT.UI_NEED_ROLL_POSITIVE then
        PlaySound(SOUNDKIT.UI_NEED_ROLL_POSITIVE)
    end
end

local function finishWinner(roll, name, method, value, class)
    local icon = ""
    for _, choice in ipairs(choices) do
        if choice[1] == method then
            icon = "|A:" .. choice[3] .. ":18:18|a "
            break
        end
    end
    finish(roll, name .. "\n" .. icon .. method .. " • Roll " .. value, class, true)
end

local function stopAnimations(row)
    row.voteAnimation:Stop()
    row.resultAnimation:Stop()
    row.voteGlow:Hide()
    row.resultGlow:Hide()
    row.animationState = nil
end

local function animateStatus(row, left)
    local roll = row.roll
    local state = roll.result and "finished"
        or (left and left > 0 and not roll.votingComplete and "voting")
        or "waiting"
    if row.animationState == state then return end
    stopAnimations(row)
    row.animationState = state
    local opacity = addon.GetOpacity()
    if state == "voting" then
        row.voteGlow:SetColorTexture(1, 0.72, 0.12, opacity)
        row.voteGlow:Show()
        row.voteAnimation:Play()
    elseif state == "finished" then
        row.resultGlow:SetColorTexture(0.25, 1, 0.45, 0.22 * opacity)
        row.resultGlow:Show()
        row.resultAnimation:Play()
    end
end

local function renderStatus(row, left)
    local roll = row.roll
    local text = roll.result
    if not text then
        if roll.votingComplete then
            text = "Voting complete • awaiting result"
        elseif left and left > 0 then
            text = "Voting ongoing"
            if roll.voted then text = text .. " • " .. roll.voted .. "/" .. roll.total end
            text = text .. " • " .. math.ceil(left) .. "s"
        else
            text = "Voting closed • awaiting result"
        end
    end
    row.details:ClearAllPoints()
    if roll.result then
        row.name:Hide()
        row.resultText:SetText(roll.result)
        row.resultText:SetAlpha(addon.GetOpacity())
        row.resultText:Show()
        row.details:SetPoint("TOPLEFT", 59, -65)
        row.details:SetSize(WIDTH - 72, 15)
        row.details:SetText((roll.preview and "Test • " or "") .. (roll.displayName or "Item"))
        row.details:SetTextColor(0.78, 0.73, 0.63)
    else
        row.name:Show()
        row.resultText:Hide()
        row.details:SetPoint("TOPLEFT", 59, -32)
        row.details:SetSize(WIDTH - 72, 20)
        row.details:SetText((roll.preview and "Test • " or "") .. text)
        row.details:SetTextColor(1, 0.82, 0)
    end
    for _, button in ipairs(row.buttons) do
        if roll.result then button:Hide() else button:Show() end
        if roll.result or roll.closed or roll.votingComplete or roll.selfVoted or not left or left <= 0 then button:Disable() end
    end
    animateStatus(row, left)
end

local function refresh(row)
    local roll = row.roll
    if roll.result then
        renderStatus(row)
        return GetTime() < roll.resultExpires
    end
    local left = timeLeft(roll)
    if not left or left <= 0 or roll.closed then
        if roll.preview then return false end
        roll.closed = roll.closed or GetTime()
        if GetTime() >= roll.resultDeadline then
            finish(roll, "Roll ended • result unavailable")
        end
        -- A local vote may close Blizzard's roll window before the group is done.
        renderStatus(row, math.max(0, roll.votingEnds - GetTime()))
        return true
    end
    local icon, name, count, quality, canNeed, canGreed
    if roll.preview then
        icon, name, count, quality = roll.icon, roll.name, 1, roll.quality
        canNeed, canGreed = true, true
    else
        local bop
        icon, name, count, quality, bop, canNeed, canGreed = GetLootRollItemInfo(roll.id)
        if not public(icon) or not public(name) or not public(count) or not public(quality)
            or not public(canNeed) or not public(canGreed) then
            for _, button in ipairs(row.buttons) do button:Disable() end
            return true
        end
        local link = GetLootRollItemLink(roll.id)
        if public(link) and type(link) == "string" then roll.link = link end
    end
    local color = number(quality) and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    local r, g, b = 1, 1, 1
    if color then r, g, b = color.r, color.g, color.b end
    local opacity = addon.GetOpacity()
    row:SetBackdropColor(0.02 + r * 0.18, 0.02 + g * 0.18, 0.02 + b * 0.18, 0.9 * opacity)
    row:SetBackdropBorderColor(r, g, b, 0.65 * opacity)
    row.name:SetTextColor(r, g, b)
    row.name:SetAlpha(opacity)
    row.details:SetAlpha(opacity)
    row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    roll.displayName = (type(name) == "string" and name or "Loading item…")
        .. (number(count) and count > 1 and (" x" .. count) or "")
    row.name:SetText(roll.displayName)
    for i, button in ipairs(row.buttons) do
        local allowed = (i == 1 and canNeed) or (i == 2 and canGreed) or i == 3
        if allowed then button:Enable() else button:Disable() end
    end
    renderStatus(row, left)
    return true
end

local function choose(row, choice)
    if not addon.IsGroupLootEnabled() then return end
    local roll = row.roll
    if not roll or roll.result or roll.closed or roll.votingComplete or roll.selfVoted then return end
    -- Recheck eligibility and expiry at click time, including default-UI choices.
    if not refresh(row) then return end
    if roll.result or roll.closed or roll.votingComplete or roll.selfVoted then return end
    local left = timeLeft(roll)
    if not left or left <= 0 then return end
    if not roll.preview then
        local _, _, _, _, _, canNeed, canGreed = GetLootRollItemInfo(roll.id)
        if not public(canNeed) or not public(canGreed) then return end
        if choice[2] == 1 and not canNeed or choice[2] == 2 and not canGreed then return end
        -- Blizzard owns any bind-on-pickup confirmation. Never auto-confirm.
        RollOnLoot(roll.id, choice[2])
    else
        print("Loot List Forever: test selected " .. choice[1] .. ".")
        if choice[2] == 0 then finish(roll, "Everyone passed")
        else finishWinner(roll, "Testplayer", choice[1], choice[2] == 1 and 97 or 84,
            choice[2] == 1 and "WARRIOR" or "MAGE") end
        refresh(row)
    end
end

local function createRow()
    local row = CreateFrame("Button", nil, anchor, BackdropTemplateMixin and "BackdropTemplate" or nil)
    row:SetSize(WIDTH, HEIGHT)
    row:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16,
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    row.voteGlow = row:CreateTexture(nil, "ARTWORK")
    row.voteGlow:SetSize(WIDTH - 16, 2)
    row.voteGlow:SetPoint("TOPLEFT", 8, -5)
    row.voteGlow:Hide()
    row.resultGlow = row:CreateTexture(nil, "BACKGROUND")
    row.resultGlow:SetPoint("TOPLEFT", 5, -5)
    row.resultGlow:SetPoint("BOTTOMRIGHT", -5, 5)
    row.resultGlow:SetAlpha(0)
    row.resultGlow:Hide()
    local function alphaAnimation(group, from, to, duration, order)
        local animation = group:CreateAnimation("Alpha")
        animation:SetFromAlpha(from)
        animation:SetToAlpha(to)
        animation:SetDuration(duration)
        animation:SetOrder(order)
        animation:SetSmoothing("IN_OUT")
    end
    row.voteAnimation = row.voteGlow:CreateAnimationGroup()
    row.voteAnimation:SetLooping("REPEAT")
    alphaAnimation(row.voteAnimation, 0.25, 0.85, 0.9, 1)
    alphaAnimation(row.voteAnimation, 0.85, 0.25, 0.9, 2)
    row.resultAnimation = row.resultGlow:CreateAnimationGroup()
    alphaAnimation(row.resultAnimation, 0, 1, 0.18, 1)
    alphaAnimation(row.resultAnimation, 1, 0, 0.85, 2)
    row.resultAnimation:SetScript("OnFinished", function() row.resultGlow:Hide() end)
    row:SetScript("OnHide", function(self) stopAnimations(self) end)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(40, 40)
    row.icon:SetPoint("TOPLEFT", 9, -9)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", 59, -11)
    row.name:SetSize(WIDTH - 72, 17)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetShadowOffset(1, -1)
    row.resultText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.resultText:SetPoint("TOPLEFT", 59, -9)
    row.resultText:SetSize(WIDTH - 72, 50)
    row.resultText:SetJustifyH("LEFT")
    row.resultText:SetJustifyV("TOP")
    row.resultText:SetWordWrap(true)
    row.resultText:SetTextColor(0.35, 1, 0.45)
    row.resultText:SetShadowOffset(1, -1)
    row.resultText:Hide()
    row.details = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.details:SetPoint("TOPLEFT", 59, -32)
    row.details:SetSize(WIDTH - 72, 43)
    row.details:SetWordWrap(true)
    row.details:SetJustifyH("LEFT")
    row.details:SetTextColor(0.78, 0.73, 0.63)
    row:SetScript("OnEnter", function(self)
        if self.roll and self.roll.link then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetHyperlink(self.roll.link)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
        if self.roll and self.roll.link and IsShiftKeyDown() and ChatEdit_InsertLink then
            ChatEdit_InsertLink(self.roll.link)
        end
    end)
    row.buttons = {}
    for i, choice in ipairs(choices) do
        local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        button:SetSize(92, 24)
        button:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 12 + (i - 1) * 102, 8)
        button:SetText("|A:" .. choice[3] .. ":18:18|a " .. choice[1])
        button:SetScript("OnClick", function() choose(row, choice) end)
        row.buttons[i] = button
    end
    return row
end

local function tick(generation)
    if generation ~= timerGeneration or not addon.IsGroupLootEnabled() then return end
    for i = #active, 1, -1 do
        if not refresh(active[i]) then removeRow(i) end
    end
    if #active > 0 then C_Timer.After(0.25, function() tick(generation) end) else ticking = nil end
end

local function historyAvailable()
    return C_LootHistory and C_LootHistory.GetAllEncounterInfos
        and C_LootHistory.GetSortedDropsForEncounter and C_LootHistory.GetLootHistoryTime
end

-- History uses encounter/drop keys, not roll IDs. Bind only a unique recent
-- full hyperlink match; never guess the winner of identical simultaneous drops.
updateHistory = function()
    if not historyAvailable() then return end
    local encounters = C_LootHistory.GetAllEncounterInfos()
    if not public(encounters) or type(encounters) ~= "table" then return end
    local drops = {}
    for _, encounter in ipairs(encounters) do
        if public(encounter) and type(encounter) == "table" and number(encounter.encounterID) then
            local entries = C_LootHistory.GetSortedDropsForEncounter(encounter.encounterID)
            if public(entries) and type(entries) == "table" then
                for _, drop in ipairs(entries) do
                    if public(drop) and type(drop) == "table" and number(drop.lootListKey)
                        and number(drop.startTime) and public(drop.itemHyperlink)
                        and type(drop.itemHyperlink) == "string" then
                        drops[#drops + 1] = { encounterID = encounter.encounterID, info = drop }
                    end
                end
            end
        end
    end
    for _, row in ipairs(active) do
        local roll = row.roll
        if not roll.preview and not roll.result then
            local matched, candidates = nil, 0
            for _, entry in ipairs(drops) do
                local drop = entry.info
                local same = roll.historyKey and roll.historyKey == drop.lootListKey
                    and roll.encounterID == entry.encounterID
                if not roll.historyKey and roll.link and number(roll.historyStart)
                    and roll.link == drop.itemHyperlink and math.abs(roll.historyStart - drop.startTime) <= 3 then
                    local competing = false
                    for _, other in ipairs(active) do
                        local otherRoll = other.roll
                        if otherRoll ~= roll and not otherRoll.preview and not otherRoll.result
                            and otherRoll.link == roll.link and number(otherRoll.historyStart)
                            and math.abs(otherRoll.historyStart - drop.startTime) <= 3 then
                            competing = true; break
                        end
                        if otherRoll.historyKey == drop.lootListKey and otherRoll.encounterID == entry.encounterID then
                            competing = true; break
                        end
                    end
                    same = not competing
                end
                if same then matched = entry; candidates = candidates + 1 end
            end
            if candidates == 1 then
                roll.historyKey, roll.encounterID = matched.info.lootListKey, matched.encounterID
                local drop = matched.info
                if public(drop.allPassed) and drop.allPassed then
                    finish(roll, "Everyone passed")
                elseif public(drop.winner) and type(drop.winner) == "table" then
                    local winner = drop.winner
                    if public(winner.playerName) and type(winner.playerName) == "string"
                        and number(winner.state) and number(winner.roll) then
                        local method = ({ [0] = "Need", [1] = "Need", [2] = "Transmog", [3] = "Greed" })[winner.state]
                        if method then finishWinner(roll, winner.playerName, method, winner.roll, winner.playerClass) end
                    end
                end
                if public(drop.rollInfos) and type(drop.rollInfos) == "table" then
                    local voted, total, selfVoted = 0, 0, false
                    for _, vote in ipairs(drop.rollInfos) do
                        if public(vote) and type(vote) == "table" and number(vote.state) then
                            total = total + 1
                            if vote.state ~= 4 then voted = voted + 1 end
                            if public(vote.isSelf) and vote.isSelf and vote.state ~= 4 then selfVoted = true end
                        end
                    end
                    if total > 0 then
                        roll.voted, roll.total = voted, total
                        roll.votingComplete, roll.selfVoted = voted == total, selfVoted
                    end
                end
                refresh(row)
            end
        end
    end
end

local function addRoll(roll)
    if not addon.IsGroupLootEnabled() then return end
    local row = table.remove(pool) or createRow()
    row.roll = roll
    row.name:SetText("Loading item…")
    row.name:Show()
    row.resultText:Hide()
    row.details:SetText("")
    row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    for _, button in ipairs(row.buttons) do button:Disable() end
    active[#active + 1] = row
    row:Show()
    refresh(row)
    layout()
    if not ticking then
        ticking = true
        local generation = timerGeneration
        C_Timer.After(0.25, function() tick(generation) end)
    end
end

function addon.ShowGroupPreview()
    if not addon.IsGroupLootEnabled() then
        print("Loot List Forever: group loot is disabled. Enable it in /lootlist settings.")
        return
    end
    for i = #active, 1, -1 do
        if active[i].roll.preview then removeRow(i) end
    end
    local info = C_Item and C_Item.GetItemInfo or GetItemInfo
    for _, sample in ipairs({ { 774, "Malachite", 2 }, { 5191, "Cruel Barb", 3 }, { 2825, "Bow of Searing Arrows", 4 } }) do
        local name, link, quality, _, _, _, _, _, _, icon = info(sample[1])
        if not public(name) or type(name) ~= "string" then name = sample[2] end
        if not number(quality) then quality = sample[3] end
        if not public(icon) then icon = nil end
        if not public(link) or type(link) ~= "string" then link = nil end
        addRoll({ preview = true, name = name, link = link, quality = quality,
            icon = icon, expires = GetTime() + 60 })
    end
end

local function canChangeDefaultFrame(frame)
    return not (InCombatLockdown and InCombatLockdown() and frame.IsProtected and frame:IsProtected())
end

local function suppressDefaultFrame(frame, isRoot)
    if not frame or not canChangeDefaultFrame(frame) then return end
    local saved = defaultRollStates[frame] or {}
    defaultRollStates[frame] = saved
    if isRoot and frame.GetAlpha and frame.SetAlpha then
        if saved.alpha == nil then
            local alpha = frame:GetAlpha()
            if number(alpha) then saved.alpha = alpha end
        end
        if saved.alpha ~= nil then frame:SetAlpha(0) end
    end
    if frame.IsMouseEnabled and frame.EnableMouse then
        if saved.mouse == nil then
            local enabled = frame:IsMouseEnabled()
            if public(enabled) and type(enabled) == "boolean" then saved.mouse = enabled end
        end
        if saved.mouse ~= nil then frame:EnableMouse(false) end
    end
    if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do suppressDefaultFrame(child, false) end
    end
end

function addon.ApplyDefaultGroupRollVisibility()
    -- Do not Hide these frames: their OnHide handlers unregister roll events.
    -- Leave Blizzard's event processing and confirmation dialogs intact.
    local enabled = addon.IsGroupLootEnabled()
        and GetLootRollItemInfo and GetLootRollItemLink and GetLootRollTimeLeft and RollOnLoot
    local roots = { "GroupLootContainer", "GroupLootFrame1", "GroupLootFrame2",
        "GroupLootFrame3", "GroupLootFrame4", "GamepadGroupLootRollFrame" }
    for _, name in ipairs(roots) do
        local frame = _G[name]
        if frame then
            if not defaultRollHooks[frame] and frame.HookScript and canChangeDefaultFrame(frame) then
                frame:HookScript("OnShow", function() addon.ApplyDefaultGroupRollVisibility() end)
                defaultRollHooks[frame] = true
            end
            if enabled then suppressDefaultFrame(frame, true) end
        end
    end
    if not enabled then
        for frame, saved in pairs(defaultRollStates) do
            if canChangeDefaultFrame(frame) then
                if saved.alpha ~= nil then frame:SetAlpha(saved.alpha) end
                if saved.mouse ~= nil then frame:EnableMouse(saved.mouse) end
                defaultRollStates[frame] = nil
            end
        end
    end
end

function addon.ApplyGroupLootEnabled()
    if not eventFrame then return end
    addon.ApplyDefaultGroupRollVisibility()
    eventFrame:UnregisterAllEvents()
    if not addon.IsGroupLootEnabled() then
        timerGeneration = timerGeneration + 1
        ticking = nil
        stopDrag()
        stopResize()
        for i = #active, 1, -1 do removeRow(i) end
        return
    end
    if GetLootRollItemInfo and GetLootRollItemLink and GetLootRollTimeLeft and RollOnLoot then
        for _, event in ipairs({ "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS" }) do
            eventFrame:RegisterEvent(event)
        end
        if historyAvailable() then
            eventFrame:RegisterEvent("LOOT_HISTORY_UPDATE_DROP")
            eventFrame:RegisterEvent("LOOT_HISTORY_UPDATE_ENCOUNTER")
        end
    end
end

function addon.InitializeGroupLoot()
    anchor = CreateFrame("Frame", "LootListGroupAnchor", UIParent)
    anchor:SetSize(WIDTH, HEIGHT)
    anchor:SetFrameStrata("MEDIUM")
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    local scale = LootListDB.groupScale
    if not number(scale) then scale = addon.lootAnchor:GetScale() end
    anchor:SetScale(math.max(MIN_SCALE, math.min(MAX_SCALE, scale)))
    local points = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true,
        CENTER = true, RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
    local pos = LootListDB.groupPosition
    if type(pos) == "table" and type(pos.point) == "string" and points[pos.point]
        and type(pos.relativePoint) == "string" and points[pos.relativePoint]
        and number(pos.x) and number(pos.y) and math.abs(pos.x) ~= math.huge and math.abs(pos.y) ~= math.huge then
        anchor:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        anchor:SetPoint("TOPRIGHT", addon.lootAnchor, "TOPLEFT", -16, 0)
    end
    heading = CreateFrame("Button", "LootListGroupMover", anchor)
    heading:SetSize(WIDTH, 24)
    heading:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 3)
    heading:RegisterForDrag("LeftButton")
    heading:SetScript("OnDragStart", function() stopResize(); dragging = true; anchor:StartMoving() end)
    heading:SetScript("OnDragStop", stopDrag)
    heading:SetScript("OnMouseUp", stopDrag)
    heading:SetScript("OnHide", stopDrag)
    local background = heading:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.08, 0.06, 0.03, 0.9)
    local label = heading:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText("Group loot — drag to move")
    heading:Hide()
    resizeHandle = CreateFrame("Button", "LootListGroupResizeHandle", anchor)
    resizeHandle:SetSize(22, 22)
    resizeHandle:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
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
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, id, duration)
        if not addon.IsGroupLootEnabled() then return end
        if event == "START_LOOT_ROLL" then
            if not number(id) or not number(duration) or duration <= 0 then return end
            for _, row in ipairs(active) do if not row.roll.preview and row.roll.id == id then return end end
            local historyStart = historyAvailable() and C_LootHistory.GetLootHistoryTime()
            local votingEnds = GetTime() + duration / 1000
            addRoll({ id = id, votingEnds = votingEnds, resultDeadline = votingEnds + RESULT_GRACE,
                historyStart = number(historyStart) and historyStart or nil })
            updateHistory()
        elseif event == "LOOT_HISTORY_UPDATE_DROP" or event == "LOOT_HISTORY_UPDATE_ENCOUNTER" then
            updateHistory()
        else
            if event == "CANCEL_LOOT_ROLL" and not number(id) then return end
            updateHistory()
            for i = #active, 1, -1 do
                local roll = active[i].roll
                if not roll.preview and not roll.result and (event == "CANCEL_ALL_LOOT_ROLLS" or roll.id == id) then
                    roll.closed = roll.closed or GetTime()
                    refresh(active[i])
                end
            end
        end
    end)
    addon.ApplyGroupLootEnabled()
    local defaultFrame = CreateFrame("Frame")
    for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "START_LOOT_ROLL" }) do
        defaultFrame:RegisterEvent(event)
    end
    defaultFrame:SetScript("OnEvent", function(_, event)
        if event == "START_LOOT_ROLL" then
            -- Also catch children created after Blizzard handles this event.
            C_Timer.After(0, addon.ApplyDefaultGroupRollVisibility)
        else
            addon.ApplyDefaultGroupRollVisibility()
        end
    end)
end
