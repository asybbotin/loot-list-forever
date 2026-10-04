local _, addon = ...
local panel, title, summary, empty, scroll, content, eventFrame, session, preview
local rows = {}
local WIDTH, ROW_HEIGHT = 446, 78
local methods = { [0] = "Need", [1] = "Need", [2] = "Transmog", [3] = "Greed" }

-- Verified against Forever 1.60.1.70205: InstanceDocumentation,
-- LootHistoryDocumentation and Blizzard_SharedXML/SecureScrollTemplates.xml.
local function public(value)
    return not issecretvalue or not issecretvalue(value)
end

local function number(value)
    return public(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function text(value)
    return public(value) and type(value) == "string"
end

local function available()
    return C_LootHistory and C_LootHistory.GetAllEncounterInfos
        and C_LootHistory.GetSortedDropsForEncounter and C_LootHistory.GetLootHistoryTime
end

local function classIcon(class)
    local coords = text(class) and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class:upper()]
    if not coords then return "" end
    return string.format("|TInterface/TargetingFrame/UI-Classes-Circles:16:16:0:0:256:256:%d:%d:%d:%d|t ",
        coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256)
end

local function resultText(entry)
    if entry.winner and entry.method and entry.roll then
        return classIcon(entry.class) .. entry.winner .. "\n|A:lootroll-toast-icon-"
            .. entry.method:lower() .. "-up:18:18|a " .. entry.method .. " • Roll " .. entry.roll
    end
    if entry.allPassed then return "Everyone passed" end
    if entry.total and entry.total > 0 then
        if entry.voted == entry.total then return "Voting complete • awaiting result" end
        return "Voting ongoing • " .. entry.voted .. "/" .. entry.total
    end
    return "Awaiting result"
end

local function createRow()
    local row = CreateFrame("Button", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
    row:SetSize(WIDTH, ROW_HEIGHT - 4)
    row:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16,
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(40, 40)
    row.icon:SetPoint("TOPLEFT", 9, -10)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.resultText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.resultText:SetPoint("TOPLEFT", 59, -8)
    row.resultText:SetSize(WIDTH - 72, 43)
    row.resultText:SetJustifyH("LEFT")
    row.resultText:SetJustifyV("TOP")
    row.resultText:SetWordWrap(true)
    row.itemName = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.itemName:SetPoint("TOPLEFT", 59, -54)
    row.itemName:SetSize(WIDTH - 72, 16)
    row.itemName:SetJustifyH("LEFT")
    row.itemName:SetWordWrap(false)
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnEnter", function(self)
        if self.historyEntry and self.historyEntry.link then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetHyperlink(self.historyEntry.link)
            GameTooltip:Show()
        end
    end)
    local function hideTooltip(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    row:SetScript("OnLeave", hideTooltip)
    row:SetScript("OnHide", hideTooltip)
    row:SetScript("OnClick", function(self)
        if self.historyEntry and self.historyEntry.link and IsShiftKeyDown() and ChatEdit_InsertLink then
            ChatEdit_InsertLink(self.historyEntry.link)
        end
    end)
    return row
end

local function render()
    if not panel or not panel:IsShown() then return end
    local entries = preview or (session and session.entries) or {}
    title:SetText(preview and "Group loot history — Preview" or "Group loot history")
    summary:SetText(preview and "Sample results • not saved" or session
        and (session.name .. " • " .. #entries .. " items • newest first")
        or "Enter a dungeon or raid to start a loot history.")
    empty:SetText(not available() and not preview and "Loot history is unavailable on this client."
        or "No group rolls recorded yet.")
    if #entries == 0 then empty:Show() else empty:Hide() end
    content:SetSize(WIDTH, math.max(1, #entries * ROW_HEIGHT))
    local info = C_Item and C_Item.GetItemInfo or GetItemInfo
    for i = 1, math.max(#entries, #rows) do
        if i <= #entries then
            local row = rows[i] or createRow()
            rows[i] = row
            local entry = entries[#entries - i + 1]
            row.historyEntry = entry
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
            local name, _, quality, _, _, _, _, _, _, icon
            if info and entry.link then name, _, quality, _, _, _, _, _, _, icon = info(entry.link) end
            if not text(name) then name = entry.link and entry.link:match("%[([^%]]+)%]") or "Item" end
            local color = number(quality) and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            local r, g, b = 1, 1, 1
            if color then r, g, b = color.r, color.g, color.b end
            row:SetBackdropColor(0.02 + r * 0.18, 0.02 + g * 0.18, 0.02 + b * 0.18, 0.9)
            row:SetBackdropBorderColor(r, g, b, 0.65)
            row.icon:SetTexture(public(icon) and icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.itemName:SetText(name or "Item")
            row.itemName:SetTextColor(r, g, b)
            row.resultText:SetText(resultText(entry))
            if entry.winner or entry.allPassed then row.resultText:SetTextColor(0.35, 1, 0.45)
            else row.resultText:SetTextColor(1, 0.82, 0) end
            row:Show()
        elseif rows[i] then
            rows[i]:Hide()
            rows[i].historyEntry = nil
        end
    end
end

local function sanitizeEntries(entries)
    local clean = {}
    if type(entries) ~= "table" then return clean end
    local seen = {}
    for _, entry in ipairs(entries) do
        if type(entry) == "table" and text(entry.key) and text(entry.link) and not seen[entry.key] then
            local copy = { key = entry.key, link = entry.link, allPassed = entry.allPassed == true }
            if number(entry.startTime) then copy.startTime = entry.startTime end
            if text(entry.winner) and text(entry.method) and number(entry.roll)
                and (entry.method == "Need" or entry.method == "Greed" or entry.method == "Transmog") then
                copy.winner, copy.method, copy.roll = entry.winner, entry.method, entry.roll
                if text(entry.class) then copy.class = entry.class end
            end
            if number(entry.voted) and number(entry.total) and entry.voted >= 0 and entry.total >= entry.voted then
                copy.voted, copy.total = entry.voted, entry.total
            end
            seen[entry.key] = true
            clean[#clean + 1] = copy
        end
    end
    return clean
end

local function updateInstance()
    if not IsInInstance or not GetInstanceInfo then return end
    local inside, kind = IsInInstance()
    if not public(inside) or not text(kind) then return end
    if not inside or (kind ~= "party" and kind ~= "raid") then
        session, preview, LootListDB.groupHistory = nil, nil, nil
        panel:Hide()
        for _, row in ipairs(rows) do row:Hide(); row.historyEntry = nil end
        scroll:SetVerticalScroll(0)
        return
    end
    local name, _, difficulty, _, _, _, _, id = GetInstanceInfo()
    if not text(name) or not number(difficulty) or not number(id) then return end
    local saved = LootListDB.groupHistory
    if type(saved) == "table" and saved.version == 1 and saved.instanceID == id
        and saved.difficulty == difficulty and saved.kind == kind and number(saved.startTime) then
        if saved ~= session then saved.entries = sanitizeEntries(saved.entries) end
        session = saved
    else
        local now = available() and C_LootHistory.GetLootHistoryTime()
        if not number(now) then now = nil end
        session = { version = 1, instanceID = id, difficulty = difficulty, kind = kind,
            name = name, startTime = now, entries = {} }
        LootListDB.groupHistory = session
        preview = nil
        for _, row in ipairs(rows) do row:Hide(); row.historyEntry = nil end
        scroll:SetVerticalScroll(0)
    end
    session.name = name
    addon.RefreshDungeonHistory()
    render()
end

function addon.RefreshDungeonHistory()
    if not session or not addon.IsGroupLootEnabled() or not available() or not number(session.startTime) then return end
    local encounters = C_LootHistory.GetAllEncounterInfos()
    if not public(encounters) or type(encounters) ~= "table" then return end
    local byKey = {}
    for _, entry in ipairs(session.entries) do byKey[entry.key] = entry end
    for _, encounter in ipairs(encounters) do
        if public(encounter) and type(encounter) == "table" and number(encounter.encounterID) then
            local drops = C_LootHistory.GetSortedDropsForEncounter(encounter.encounterID)
            if public(drops) and type(drops) == "table" then
                for _, drop in ipairs(drops) do
                    if public(drop) and type(drop) == "table" and number(drop.lootListKey)
                        and number(drop.startTime) and drop.startTime >= session.startTime and text(drop.itemHyperlink) then
                        local key = encounter.encounterID .. ":" .. drop.lootListKey
                        local entry = byKey[key]
                        if not entry then
                            entry = { key = key, link = drop.itemHyperlink, startTime = drop.startTime }
                            session.entries[#session.entries + 1] = entry
                            byKey[key] = entry
                        end
                        if public(drop.allPassed) and drop.allPassed then entry.allPassed = true end
                        if public(drop.winner) and type(drop.winner) == "table" then
                            local winner = drop.winner
                            if text(winner.playerName) and number(winner.state) and methods[winner.state] and number(winner.roll) then
                                entry.winner, entry.method, entry.roll = winner.playerName, methods[winner.state], winner.roll
                                if text(winner.playerClass) then entry.class = winner.playerClass end
                            end
                        end
                        if public(drop.rollInfos) and type(drop.rollInfos) == "table" then
                            local voted, total = 0, 0
                            for _, vote in ipairs(drop.rollInfos) do
                                if public(vote) and type(vote) == "table" and number(vote.state) then
                                    total = total + 1
                                    if vote.state ~= 4 then voted = voted + 1 end
                                end
                            end
                            entry.voted, entry.total = voted, total
                        end
                    end
                end
            end
        end
    end
    table.sort(session.entries, function(a, b)
        local aTime, bTime = a.startTime or 0, b.startTime or 0
        if aTime == bTime then return a.key < b.key end
        return aTime < bTime
    end)
    render()
end

function addon.OpenDungeonHistory()
    preview = nil
    addon.CloseSettings()
    panel:Show()
    addon.RefreshDungeonHistory()
    render()
end

function addon.ShowDungeonHistoryPreview()
    preview = {
        { link = "item:774", winner = "Testwarrior", class = "WARRIOR", method = "Need", roll = 97 },
        { link = "item:5191", winner = "Testmage", class = "MAGE", method = "Greed", roll = 84 },
        { link = "item:2825", allPassed = true },
        { link = "item:2589", voted = 2, total = 5 },
    }
    addon.CloseSettings()
    panel:Show()
    scroll:SetVerticalScroll(0)
    render()
end

function addon.InitializeDungeonHistory()
    panel = CreateFrame("Frame", "LootListHistoryPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetSize(510, 450)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 24, -22)
    title:SetText("Group loot history")
    summary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", 24, -49)
    summary:SetSize(WIDTH, 16)
    summary:SetJustifyH("LEFT")
    scroll = CreateFrame("ScrollFrame", "LootListHistoryScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 24, -76)
    scroll:SetPoint("BOTTOMRIGHT", -40, 58)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH, 1)
    scroll:SetScrollChild(content)
    empty = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("TOPLEFT", 12, -15)
    empty:SetSize(WIDTH - 24, 48)
    empty:SetJustifyH("LEFT")
    empty:SetWordWrap(true)
    local close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    close:SetSize(100, 24)
    close:SetPoint("BOTTOMRIGHT", -24, 23)
    close:SetText("Close")
    close:SetScript("OnClick", function() panel:Hide() end)
    panel:SetScript("OnHide", function()
        panel:StopMovingOrSizing()
        for _, row in ipairs(rows) do
            if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
        end
    end)
    panel:Hide()
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "LootListHistoryPanel" end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    if available() then
        eventFrame:RegisterEvent("LOOT_HISTORY_UPDATE_DROP")
        eventFrame:RegisterEvent("LOOT_HISTORY_UPDATE_ENCOUNTER")
    end
    eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then updateInstance()
        elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then render()
        else addon.RefreshDungeonHistory() end
    end)
end
