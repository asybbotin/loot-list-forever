local addonName, addon = ...
local eventFrame = CreateFrame("Frame")
local patterns, batch, batchOrder, pending = {}, {}, {}, {}
local seenFormats = {}
local debugEnabled = false
local stats = { events = 0, parsed = 0, displayed = 0, poor = 0, expired = 0, money = 0, filtered = 0 }
local lastResult = "No loot event received since reload."
-- Only IDs and expected tiers are fixed; all displayed metadata comes from WoW.
local PREVIEW_ITEMS = { { 7073, 0 }, { 2589, 1 }, { 774, 2 },
    { 5191, 3, 13033 }, { 871, 4, { 2825, 1980, 14551, 2244, 14555, 18832 } }, { 19019, 5, 17182 } }
local FORMAT_KEYS = { "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
    "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }

local function diagnostic(text)
    lastResult = text
    if debugEnabled then print("Loot List: " .. text) end
end
local batchScheduled, retryScheduled, initialized
local MAX_PENDING, MAX_ATTEMPTS = 48, 10
local getItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local requestItem = C_Item and C_Item.RequestLoadItemDataByID
local detailedLevel = C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo

local function public(value)
    return not issecretvalue or not issecretvalue(value)
end

function addon.FormatMoney(copper)
    if not copper or copper <= 0 then return "-" end
    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local coins = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if coins > 0 then parts[#parts + 1] = coins .. "c" end
    return table.concat(parts, " ")
end

-- Compile the client's localized self-loot formats, including positional tokens.
local function compileFormat(format)
    if type(format) ~= "string" or seenFormats[format] or #patterns >= 32 then return end
    seenFormats[format] = true
    local parts, captures, index = { "^" }, {}, 1
    while index <= #format do
        local tail = format:sub(index)
        local token, kind = tail:match("^(%%(%d+)%$[sd])")
        if token then
            kind = token:sub(-1)
        else
            token, kind = tail:match("^(%%([sd]))")
        end
        if token then
            captures[#captures + 1] = kind
            parts[#parts + 1] = kind == "s" and "(.-)" or "(%d+)"
            index = index + #token
        elseif tail:sub(1, 2) == "%%" then
            parts[#parts + 1] = "%%"
            index = index + 2
        else
            parts[#parts + 1] = tail:sub(1, 1):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
            index = index + 1
        end
    end
    parts[#parts + 1] = "$"
    patterns[#patterns + 1] = { pattern = table.concat(parts), captures = captures }
end

local function refreshFormats()
    -- Localization addons may replace globals after this addon loads. Retain
    -- both the original formats and any later translations.
    for _, key in ipairs(FORMAT_KEYS) do compileFormat(_G[key]) end
end

local function itemIDFromLink(link)
    -- Color decoration is not part of the item hyperlink. Accept legacy hex,
    -- named quality, named global colors, and undecorated hyperlinks alike.
    local plain = link:gsub("|cn[%w_]+:", "")
        :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if plain:match("^|Hitem:%d+:[^|]*|h.-|h$") then
        return tonumber(plain:match("^|Hitem:(%d+):"))
    end
end

function addon.ParseLoot(message, senderGUID)
    if not public(message) or type(message) ~= "string" then return end
    refreshFormats()
    for _, format in ipairs(patterns) do
        local values = { message:match(format.pattern) }
        if #values > 0 then
            local link, quantity
            for i, kind in ipairs(format.captures) do
                if kind == "s" then link = values[i] else quantity = tonumber(values[i]) end
            end
            -- A single-item format can also match a stack message; reject the
            -- trailing quantity so the multiple-item format gets to parse it.
            if link then
                local itemID = itemIDFromLink(link)
                if itemID then return itemID, link, quantity or 1 end
            end
        end
    end
    -- A verified player GUID allows acquisition messages whose surrounding
    -- wording was changed by the client/addons. Never infer ownership from
    -- the mere presence of an item link.
    local playerGUID = UnitGUID and UnitGUID("player")
    if public(senderGUID) and public(playerGUID) and playerGUID
        and senderGUID == playerGUID then
        local link = message:match("(|cn[%w_]+:|Hitem:[^|]*|h.-|h|r)")
            or message:match("(|c%x%x%x%x%x%x%x%x|Hitem:[^|]*|h.-|h|r)")
            or message:match("(|Hitem:[^|]*|h.-|h)")
        if link then
            local _, last = message:find(link, 1, true)
            local quantity = tonumber(message:sub(last + 1):match("^%s*x(%d+)")) or 1
            return itemIDFromLink(link), link, quantity
        end
    end
end

local function previewFallback(record)
    local candidates = record.previewFallbacks
    local nextIndex = (record.previewFallbackIndex or 0) + 1
    if not candidates or not candidates[nextIndex] then return false end
    -- Prefer a candidate already recognized by this exact client build.
    for i = nextIndex, #candidates do
        local name, _, quality = getItemInfo(candidates[i])
        if public(name) and public(quality) and name and quality == record.previewQuality then
            nextIndex = i
            break
        end
    end
    record.itemID = candidates[nextIndex]
    record.itemLink = "item:" .. record.itemID
    record.previewFallbackIndex = nextIndex
    record.attempts = 0
    diagnostic("Trying fallback preview item " .. record.itemID .. ".")
    if requestItem then requestItem(record.itemID) end
    return true
end

local function hasPreviewFallback(record)
    return record.previewFallbacks and record.previewFallbacks[(record.previewFallbackIndex or 0) + 1] ~= nil
end

local function resolve(record)
    if not getItemInfo then return false end
    if record.previewQuality and not addon.IsQualityEnabled(record.previewQuality) then return true end
    local name, cachedLink, quality, level, _, _, _, _, _, icon, price = getItemInfo(record.isPreview and record.itemID or record.itemLink)
    if not public(name) or not public(quality) or not public(level)
        or not public(icon) or not public(price) then
        record.waitReason = "restricted item metadata"
        return false
    end
    if quality ~= nil and record.previewQuality and quality ~= record.previewQuality then
        if previewFallback(record) then return resolve(record) end
        print("Loot List: preview item " .. record.itemID .. " does not match its expected rarity; skipped.")
        return true
    end
    if quality ~= nil and not addon.IsQualityEnabled(quality) then
        stats.filtered = stats.filtered + 1
        if quality == 0 then stats.poor = stats.poor + 1 end
        diagnostic("Skipped disabled quality " .. quality .. " item " .. record.itemID .. ".")
        return true
    end
    if not name or not quality or not level or not icon or price == nil then
        record.waitReason = "incomplete item metadata"
        return false
    end
    if detailedLevel then
        local actual = detailedLevel(record.itemLink)
        if public(actual) and type(actual) == "number" then level = actual end
    end
    if record.isPreview then
        if not public(cachedLink) or type(cachedLink) ~= "string" then return false end
        record.itemLink = cachedLink
    end
    record.itemName, record.itemQuality, record.itemLevel = name, quality, level
    record.itemIcon, record.vendorSellPrice = icon, price
    for i = 1, record.previewCount or 1 do addon.ShowItem(record) end
    stats.displayed = stats.displayed + (record.previewCount or 1)
    diagnostic("Displayed item " .. record.itemID .. " x" .. record.quantity .. ".")
    return true
end

local scheduleRetry
local function retryPending(itemID)
    local i = 1
    while i <= #pending do
        local record = pending[i]
        if (not itemID or record.itemID == itemID) and resolve(record) then
            table.remove(pending, i)
        else
            i = i + 1
        end
    end
end

scheduleRetry = function()
    if retryScheduled or #pending == 0 then return end
    retryScheduled = true
    C_Timer.After(1, function()
        retryScheduled = false
        retryPending()
        for i = #pending, 1, -1 do
            local record = pending[i]
            record.attempts = record.attempts + 1
            if record.attempts >= 3 and hasPreviewFallback(record) then
                previewFallback(record)
            elseif record.attempts >= MAX_ATTEMPTS then
                stats.expired = stats.expired + 1
                diagnostic("Dropped item " .. record.itemID .. ": " .. (record.waitReason or "unavailable metadata") .. ".")
                if record.isPreview then
                    print("Loot List: preview metadata unavailable for item " .. record.itemID .. "; skipped.")
                end
                table.remove(pending, i)
            elseif requestItem then
                requestItem(record.itemID)
            end
        end
        scheduleRetry()
    end)
end

local function flushBatch()
    batchScheduled = false
    local records = batchOrder
    batch, batchOrder = {}, {}
    for _, record in ipairs(records) do
        if not resolve(record) then
            record.attempts = 0
            diagnostic("Waiting for item " .. record.itemID .. ": " .. (record.waitReason or "unavailable metadata") .. ".")
            if #pending >= MAX_PENDING then table.remove(pending, 1) end
            pending[#pending + 1] = record
            if requestItem then requestItem(record.itemID) end
        end
    end
    scheduleRetry()
end

local function queueLoot(itemID, link, quantity, previewCount)
    -- A brief batch combines identical links from a single burst, not later loots.
    local key = previewCount and ("preview:" .. link) or link
    local record = batch[key]
    if record then
        if previewCount then record.previewCount = record.previewCount + previewCount
        else record.quantity = record.quantity + quantity end
    else
        if #batchOrder >= MAX_PENDING then
            local oldest = table.remove(batchOrder, 1)
            batch[oldest.batchKey] = nil
        end
        record = { itemID = itemID, itemLink = link, quantity = quantity,
            previewCount = previewCount, isPreview = previewCount ~= nil, batchKey = key }
        batch[key] = record
        batchOrder[#batchOrder + 1] = record
    end
    if not batchScheduled then
        batchScheduled = true
        C_Timer.After(0.1, flushBatch)
    end
    return record
end

function addon.ShowPreview()
    addon.ClearPreviews()
    for i = #pending, 1, -1 do
        if pending[i].isPreview then table.remove(pending, i) end
    end
    for i = #batchOrder, 1, -1 do
        if batchOrder[i].isPreview then
            batch[batchOrder[i].batchKey] = nil
            table.remove(batchOrder, i)
        end
    end
    local samples, disabled = {}, {}
    for _, sample in ipairs(PREVIEW_ITEMS) do
        if addon.IsQualityEnabled(sample[2]) then
            samples[#samples + 1] = sample
        else
            disabled[#disabled + 1] = _G["ITEM_QUALITY" .. sample[2] .. "_DESC"] or tostring(sample[2])
        end
    end
    if #disabled > 0 then print("Loot List: preview excludes unchecked rarities: " .. table.concat(disabled, ", ") .. ".") end
    if #samples == 0 then
        print("Loot List: enable at least one item rarity to preview the list.")
    else
        table.sort(samples, function(a, b) return a[2] > b[2] end)
        diagnostic("Showing sample-item rarity previews.")
        for i = 1, math.max(5, #samples) do
            local sample = samples[(i - 1) % #samples + 1]
            local id = sample[1]
            local fallbacks = type(sample[3]) == "table" and sample[3] or sample[3] and { sample[3] }
            if sample[2] == 4 then
                -- Avoid a retry delay when an Epic alternative is already cached.
                local candidates = { id }
                for _, candidate in ipairs(fallbacks or {}) do candidates[#candidates + 1] = candidate end
                for _, candidate in ipairs(candidates) do
                    local name, link, quality, level, _, _, _, _, _, icon, price = getItemInfo(candidate)
                    if public(name) and public(link) and public(quality) and public(level)
                        and public(icon) and public(price) and name and link and quality == 4
                        and level and icon and price ~= nil then id = candidate; break end
                end
                fallbacks = {}
                for _, candidate in ipairs(candidates) do
                    if candidate ~= id then fallbacks[#fallbacks + 1] = candidate end
                end
            end
            local record = queueLoot(id, "item:" .. id, 1, 1)
            record.previewQuality = sample[2]
            record.previewFallbacks = fallbacks
            record.previewFallbackIndex = 0
            -- Request all candidates once, then resolve whichever the
            -- client can supply. Normal loot still requests only its ID.
            if requestItem then
                requestItem(sample[1])
                for _, candidate in ipairs(record.previewFallbacks or {}) do requestItem(candidate) end
            end
        end
    end
end

local function initialize()
    if initialized then return end
    if not C_Timer or not C_Timer.After or not getItemInfo then
        print("Loot List: required item/timer APIs are unavailable on this client.")
        return
    end
    initialized = true
    if type(LootListDB) ~= "table" then LootListDB = {} end
    LootListDB.version = 2
    addon.InitializeSettingsData()
    refreshFormats()
    addon.InitializeUI()
    addon.InitializeMoney()
    addon.InitializeSettingsUI()
    addon.InitializeMinimap()
    eventFrame:RegisterEvent("CHAT_MSG_LOOT")
    eventFrame:RegisterEvent("CHAT_MSG_MONEY")
    eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    SLASH_LOOTLIST1 = "/lootlist"
    SLASH_LOOTLIST2 = "/lootdisplay"
    SLASH_LOOTLIST3 = "/lloot"
    SlashCmdList.LOOTLIST = function(command)
        command = command:lower():match("^%s*(.-)%s*$")
        if command == "" or command == "settings" then addon.OpenSettings()
        elseif command == "unlock" then addon.SetUnlocked(true)
        elseif command == "lock" then addon.CloseSettings(); addon.SetUnlocked(false)
        elseif command == "reset" then addon.ResetPosition()
        elseif command == "debug" then
            debugEnabled = not debugEnabled
            print("Loot List: debug " .. (debugEnabled and "on" or "off") .. ".")
        elseif command == "status" then
            print(string.format("Loot List: events=%d parsed=%d displayed=%d gray=%d pending=%d expired=%d formats=%d money=%d filtered=%d",
                stats.events, stats.parsed, stats.displayed, stats.poor, #pending, stats.expired, #patterns, stats.money, stats.filtered))
            print("Loot List: " .. lastResult)
        elseif command == "test" then
            addon.ShowPreview()
        else print("Loot List: /lootlist settings, unlock, lock, reset, test, debug, or status.") end
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == addonName then initialize() end
    elseif event == "CHAT_MSG_LOOT" then
        stats.events = stats.events + 1
        local message = ...
        local senderGUID = select(12, ...)
        local itemID, link, quantity = addon.ParseLoot(message, senderGUID)
        if itemID and quantity > 0 then
            stats.parsed = stats.parsed + 1
            diagnostic("Received item " .. itemID .. " x" .. quantity .. ".")
            queueLoot(itemID, link, quantity)
        elseif not public(message) then
            diagnostic("Loot event has restricted text; cannot parse it safely.")
        else
            diagnostic("Loot event did not match a self-item message.")
        end
        if debugEnabled and public(message) and type(message) == "string" then
            -- Escape markup so diagnostics show actual hyperlink syntax.
            print("Loot List raw: " .. message:gsub("|", "||"))
        end
    elseif event == "CHAT_MSG_MONEY" then
        stats.events = stats.events + 1
        local message = ...
        local amount = addon.ParseMoney(message)
        if amount then
            stats.money = stats.money + 1
            stats.parsed = stats.parsed + 1
            stats.displayed = stats.displayed + 1
            addon.ShowItem({ kind = "money", amount = amount })
            diagnostic("Collected money: " .. addon.FormatMoney(amount) .. ".")
        else
            diagnostic("Money event has restricted text or an unrecognized amount.")
        end
        if debugEnabled and public(message) and type(message) == "string" then
            print("Loot List raw money: " .. message:gsub("|", "||"))
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
        local itemID, success = ...
        if public(itemID) and public(success) and success then retryPending(itemID) end
    end
end)
