-- Run from the addon directory: luajit tests/run.lua (or Lua 5.1).
local tests, passed = {}, 0
local function test(name, fn) tests[#tests + 1] = { name, fn } end
local function equal(actual, expected)
    assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end
local function link(id) return "|cffffffff|Hitem:" .. id .. ":0:0:0|h[Item " .. id .. "]|h|r" end

local function setup(options)
    options = options or {}
    local now, timers, frames, displayed, calls = 0, {}, {}, {}, 0
    local data, ready = {}, {}
    for id = 1, 80 do
        data[id] = { name = "Item " .. id, quality = id == 1 and 0 or 1,
            level = 24, icon = 12345, price = 32 }
        ready[id] = true
    end
    for quality, id in ipairs({ 7073, 2589, 774, 5191, 871, 19019 }) do
        data[id] = { name = "Sample " .. id, quality = quality - 1, level = 24, icon = 12345, price = 32 }
        ready[id] = true
    end
    for id, quality in pairs({ [13033] = 3, [18832] = 4, [17182] = 5, [873] = 4, [871] = 4, [2825] = 4, [1980] = 4, [14551] = 4, [14555] = 4 }) do
        data[id] = { name = "Fallback " .. id, quality = quality, level = 24, icon = 12345, price = 32 }
        ready[id] = true
    end
    for quality, name in ipairs({ "Poor / Junk", "Common", "Uncommon", "Rare", "Epic", "Legendary" }) do
        _G["ITEM_QUALITY" .. (quality - 1) .. "_DESC"] = name
    end
    local cursorX, cursorY = 400, 400
    GetCursorPosition = function() return cursorX, cursorY end
    LootListDB = options.db
    BackdropTemplateMixin = {}
    ITEM_QUALITY_COLORS = { [0] = { r = 0.5, g = 0.5, b = 0.5 },
        [1] = { r = 1, g = 1, b = 1 }, [2] = { r = 0.1, g = 1, b = 0 },
        [3] = { r = 0, g = 0.4, b = 1 }, [4] = { r = 0.65, g = 0.2, b = 0.93 },
        [5] = { r = 1, g = 0.5, b = 0 } }
    CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 } }
    LOOT_ITEM_SELF = options.single or "You receive loot: %s."
    LOOT_ITEM_SELF_MULTIPLE = options.multiple or "You receive loot: %sx%d."
    LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
    LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
    GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT = "%d Gold", "%d Silver", "%d Copper"
    YOU_LOOT_MONEY = "You loot %s"
    YOU_LOOT_MONEY_MOD = "You loot %s (+%s)"
    LOOT_MONEY_SPLIT = "Your share of the loot is %s."
    LOOT_MONEY_SPLIT_GUILD = "Your share of the loot is %s. (%s deposited in guild bank)"
    ERR_AUTOLOOT_MONEY_S = "You loot %s"
    SlashCmdList = {}
    UISpecialFrames = {}
    UnitGUID = function() return "Player-local" end
    GetInventoryItemLink = function(_, slot)
        if options.equipped then return options.equipped[slot] end
        return link(2)
    end
    local methods = {}
    for _, name in ipairs({ "SetSize", "SetFrameStrata", "SetMovable", "SetClampedToScreen",
        "RegisterForDrag", "RegisterForClicks", "SetBackdrop", "SetBackdropColor",
        "SetTexCoord", "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetShadowOffset", "SetAllPoints",
        "SetColorTexture", "ClearAllPoints", "StopMovingOrSizing", "EnableMouse", "SetFrameLevel",
        "SetHighlightTexture", "SetBlendMode", "SetDesaturated", "SetMinMaxValues", "SetValueStep", "SetObeyStepOnDrag" }) do methods[name] = function() end end
    for _, name in ipairs({ "SetFromAlpha", "SetToAlpha", "SetDuration", "SetOrder", "SetSmoothing", "SetLooping" }) do
        methods[name] = function() end
    end
    function methods:Play() self.playing = true; self.playCount = (self.playCount or 0) + 1 end
    function methods:Stop() self.playing = false end
    function methods:SetScale(value) self.scale = value end
    function methods:Enable() self.disabled = false end
    function methods:Disable() self.disabled = true end
    function methods:GetScale() return self.scale or 1 end
    function methods:GetEffectiveScale()
        return self:GetScale() * (self.parent and self.parent:GetEffectiveScale() or 1)
    end
    function methods:GetFrameLevel() return 3 end
    function methods:GetWidth() return 140 end
    function methods:GetHeight() return 140 end
    function methods:GetCenter() return 500, 500 end
    function methods:SetChecked(value) self.checked = value end
    function methods:GetChecked() return self.checked end
    function methods:GetValue() return self.value end
    function methods:SetValue(value)
        local previous = self.value
        self.value = value
        if previous ~= value and self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
    end
    function methods:GetLeft() return 100 end
    function methods:GetTop() return 800 end
    function methods:SetPoint(...) self.point = { ... } end
    function methods:GetPoint() return unpack(self.point) end
    function methods:SetText(value) self.text = value end
    function methods:SetTextColor(...) self.color = { ... } end
    function methods:SetBackdropBorderColor(...) self.border = { ... } end
    function methods:SetVertexColor(...) self.vertexColor = { ... } end
    function methods:SetBackdropColor(...) self.background = { ... } end
    function methods:SetTexture(value) self.texture = value end
    function methods:SetAlpha(value) self.alpha = value end
    function methods:GetAlpha() return self.alpha or 1 end
    function methods:EnableMouse(value) self.mouseEnabled = value end
    function methods:IsMouseEnabled() return self.mouseEnabled ~= false end
    function methods:IsProtected() return self.protected == true end
    function methods:GetChildren() return unpack(self.children) end
    function methods:HookScript(event, hook)
        local previous = self.scripts[event]
        self.scripts[event] = function(self, ...)
            if previous then previous(self, ...) end
            hook(self, ...)
        end
    end
    function methods:Show()
        local wasShown = self.shown
        self.shown = true
        if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function methods:IsShown() return self.shown == true end
    function methods:SetScrollChild(child) self.scrollChild = child end
    function methods:SetVerticalScroll(value) self.verticalScroll = value end
    function methods:Hide()
        local wasShown = self.shown
        self.shown = false
        if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function methods:SetScript(event, fn) self.scripts[event] = fn end
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:UnregisterAllEvents() self.events = {} end
    function methods:StartMoving() self.moving = true end
    local function object(kind, name, parent)
        local obj = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, events = {}, children = {} }, { __index = methods })
        frames[#frames + 1] = obj
        if parent then parent.children[#parent.children + 1] = obj end
        return obj
    end
    function methods:CreateTexture() return object("Texture") end
    function methods:CreateFontString() return object("FontString") end
    function methods:CreateAnimationGroup() return object("AnimationGroup") end
    function methods:CreateAnimation() return object("Animation") end
    CreateFrame = object
    UIParent = object("Frame")
    Minimap = object("Frame", "Minimap", UIParent)
    GameTooltip = {
        SetText = function(self, text) self.text = text end,
        AddLine = function() end,
        IsOwned = function(self, row) return self.owner == row end,
        SetOwner = function(self, row) self.owner = row end,
        SetHyperlink = function(self, value) self.link = value end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false; self.owner = nil end,
    }
    local inserted
    IsShiftKeyDown = function() return true end
    ChatEdit_InsertLink = function(value) inserted = value; return true end
    GetTime = function() return now end
    issecretvalue = function(value) return value == options.secret end
    C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end }
    C_Item = {
        GetItemInfo = function(value)
            calls = calls + 1
            local id = type(value) == "number" and value or tonumber(value:match("item:(%d+)"))
            if not ready[id] then return end
            local item = data[id]
            return item.name, link(id), item.quality, item.level, 0, "", "", 1, "", item.icon, item.price
        end,
        RequestLoadItemDataByID = function() end,
        GetDetailedItemLevelInfo = function(value)
            return data[tonumber(value:match("item:(%d+)"))].level
        end,
    }
    local addon = {}
    local rolls, selections = {}, {}
    local sounds = {}
    SOUNDKIT = options.noSound and nil or { UI_NEED_ROLL_POSITIVE = 123456 }
    PlaySound = not options.noSound and function(sound) sounds[#sounds + 1] = sound end or nil
    GetLootRollItemInfo = function(id)
        local roll = rolls[id]
        if not roll then return end
        return 12345, "Roll " .. id, 1, 3, false, roll.need, roll.greed
    end
    GetLootRollItemLink = function(id) return rolls[id] and link(rolls[id].itemID or 2) end
    GetLootRollTimeLeft = function(id)
        return rolls[id] and math.max(0, (rolls[id].expires - now) * 1000) or 0
    end
    RollOnLoot = function(id, choice) selections[#selections + 1] = { id, choice } end
    local combat = options.combat or false
    InCombatLockdown = function() return combat end
    local defaultNames = { "GroupLootContainer", "GroupLootFrame1", "GroupLootFrame2",
        "GroupLootFrame3", "GroupLootFrame4", "GamepadGroupLootRollFrame" }
    for _, name in ipairs(defaultNames) do _G[name] = nil end
    local defaultRoll, defaultButton, defaultHiddenButton
    if options.defaultRoll then
        defaultRoll = object("Frame", "GroupLootFrame1", UIParent)
        defaultRoll:SetAlpha(0.6)
        defaultRoll.protected = options.protectedDefault
        defaultRoll:Show()
        defaultButton = object("Button", nil, defaultRoll)
        defaultHiddenButton = object("Button", nil, defaultRoll)
        defaultHiddenButton:EnableMouse(false)
        _G.GroupLootFrame1 = defaultRoll
    end
    local instance = options.instance
    IsInInstance = function() return instance ~= nil, instance and instance.kind or "none" end
    GetInstanceInfo = function()
        return instance and instance.name or "Outside", instance and instance.kind or "none",
            instance and instance.difficulty or 1, "Normal", 5, 0, false, instance and instance.id or 0
    end
    local history = {}
    C_LootHistory = not options.noHistory and {
        GetAllEncounterInfos = function() return { { encounterID = 100 } } end,
        GetSortedDropsForEncounter = function() return history end,
        GetLootHistoryTime = function() return now + 1000 end,
    } or nil
    assert(loadfile("loot_list_forever_ui.lua"))("loot_list_forever", addon)
    assert(loadfile("loot_list_forever_settings.lua"))("loot_list_forever", addon)
    assert(loadfile("loot_list_forever_money.lua"))("loot_list_forever", addon)
    assert(loadfile("loot_list_forever_group.lua"))("loot_list_forever", addon)
    assert(loadfile("loot_list_forever_history.lua"))("loot_list_forever", addon)
    assert(loadfile("loot_list_forever.lua"))("loot_list_forever", addon)
    local show = addon.ShowItem
    addon.ShowItem = function(item) displayed[#displayed + 1] = item; show(item) end
    local function event(name, ...)
        for _, frame in ipairs(frames) do
            if frame.events[name] then frame.scripts.OnEvent(frame, name, ...) end
        end
    end
    event("ADDON_LOADED", "loot_list_forever")
    local function update(delta)
        for _, frame in ipairs(frames) do
            if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, delta) end
        end
    end
    local function advance(delta)
        if delta > 0.05 then
            local finish = now + delta
            while finish - now > 0.05 do advance(0.05) end
            advance(finish - now)
            return
        end
        local target = now + delta
        while true do
            local index, nextTimer
            for i, timer in ipairs(timers) do
                if timer.at <= target and (not nextTimer or timer.at < nextTimer.at) then index, nextTimer = i, timer end
            end
            if not index then break end
            local step = nextTimer.at - now
            now = nextTimer.at
            update(step)
            table.remove(timers, index)
            nextTimer.fn()
        end
        local step = target - now
        now = target
        update(step)
    end
    local function rows()
        local visible = {}
        for _, frame in ipairs(frames) do
            if frame.item and frame.shown then visible[#visible + 1] = frame end
        end
        return visible
    end
    return { addon = addon, event = event, advance = advance, data = data, ready = ready,
        displayed = displayed, rows = rows, frames = frames, rolls = rolls, selections = selections, history = history, sounds = sounds,
        setInstance = function(value) instance = value end,
        setCombat = function(value) combat = value end,
        defaultRoll = defaultRoll, defaultButton = defaultButton, defaultHiddenButton = defaultHiddenButton,
        historyRows = function()
            local result = {}
            for _, frame in ipairs(frames) do
                if frame.historyEntry and frame.shown then result[#result + 1] = frame end
            end
            return result
        end,
        groupRows = function()
            local result = {}
            for _, frame in ipairs(frames) do
                if frame.roll and frame.shown then result[#result + 1] = frame end
            end
            return result
        end,
        cursor = function(x, y) cursorX, cursorY = x, y end,
        calls = function() return calls end, inserted = function() return inserted end,
        loot = function(id, quantity)
            event("CHAT_MSG_LOOT", quantity and ("You receive loot: " .. link(id) .. "x" .. quantity .. ".") or ("You receive loot: " .. link(id) .. "."))
        end,
    }
end

test("acceptance scenario excludes poor and retains white/green/blue", function()
    local s = setup()
    s.data[3].quality, s.data[4].quality = 2, 3
    s.loot(1); s.loot(2, 3); s.loot(3); s.loot(4)
    s.advance(0.1)
    equal(#s.rows(), 3); equal(#s.displayed, 3)
    equal(s.displayed[1].quantity, 3)
    for _, row in ipairs(s.rows()) do
        equal(row.icon.texture, 12345)
        equal(row.item.itemLevel, 24)
        if row.item.itemID == 2 then equal(row.details.text, "ilvl 24   Vendor: 96c") end
        if row.item.itemID == 4 then equal(row.color, nil); equal(row.name.color[3], 1); equal(row.name.color[1], 0) end
    end
    s.advance(5); equal(#s.rows(), 0)
end)

test("other-player loot and non-item messages ignored", function()
    local s = setup()
    s.event("CHAT_MSG_LOOT", "Other receives loot: " .. link(2) .. ".")
    s.event("CHAT_MSG_LOOT", "You loot 4 Gold.")
    s.event("CHAT_MSG_LOOT", "You receive loot: |Hcurrency:1|h[Coin]|h.")
    s.advance(1); equal(#s.displayed, 0)
end)

test("localized positional formats and metacharacters", function()
    local s = setup({ single = "Beute (+): %1$s!", multiple = "Beute (+): %2$dx %1$s!" })
    local id, value, quantity = s.addon.ParseLoot("Beute (+): 3x " .. link(2) .. "!")
    equal(id, 2); equal(value, link(2)); equal(quantity, 3)
end)

test("same-burst duplicates aggregate; later loot has a fresh timer", function()
    local s = setup()
    s.loot(2, 3); s.loot(2); s.advance(0.1)
    equal(#s.rows(), 1); equal(s.displayed[1].quantity, 4)
    s.advance(1); s.loot(2); s.advance(0.1)
    equal(#s.rows(), 2); equal(s.displayed[2].quantity, 1)
    s.advance(3.5)
    local oldest
    for _, row in ipairs(s.rows()) do if row.item.quantity == 4 then oldest = row end end
    assert(oldest.alpha < 1 and oldest.alpha > 0)
    s.advance(0.4); equal(#s.rows(), 1)
    s.advance(1.1); equal(#s.rows(), 0)
end)

test("six-row limit queues overflow and reuses all frames", function()
    local s = setup()
    local initialFrames = #s.frames
    for id = 2, 9 do s.loot(id); s.advance(0.11) end
    equal(#s.rows(), 6); equal(#s.frames, initialFrames)
    for _, row in ipairs(s.rows()) do assert(row.item.itemID <= 7) end
    s.advance(11); equal(#s.rows(), 0)
    for _, frame in ipairs(s.frames) do assert(not frame.scripts.OnUpdate) end
end)

test("uncached item waits for metadata; lifetime begins on display", function()
    local s = setup()
    s.ready[2] = false
    s.loot(2, 3); s.advance(2); equal(#s.rows(), 0)
    s.ready[2] = true
    s.event("GET_ITEM_INFO_RECEIVED", 2, true)
    equal(#s.rows(), 1); equal(s.displayed[1].quantity, 3)
    s.event("ITEM_DATA_LOAD_RESULT", 2, true); equal(#s.displayed, 1)
    s.advance(4.9); equal(#s.rows(), 1)
    s.advance(0.2); equal(#s.rows(), 0)
end)

test("missing metadata stops retrying", function()
    local s = setup()
    s.ready[2] = false; s.loot(2); s.advance(12)
    local calls = s.calls()
    s.advance(100); equal(s.calls(), calls); equal(#s.rows(), 0)
    s.ready[2] = true; s.event("GET_ITEM_INFO_RECEIVED", 2, true)
    equal(#s.rows(), 0)
end)

test("currency formatting and no vendor value", function()
    local s = setup()
    equal(s.addon.FormatMoney(32), "32c")
    equal(s.addon.FormatMoney(418), "4s 18c")
    equal(s.addon.FormatMoney(21544), "2g 15s 44c")
    equal(s.addon.FormatMoney(10000), "1g")
    equal(s.addon.FormatMoney(0), "-")
    s.data[2].price = 0; s.loot(2); s.advance(0.1)
    equal(s.rows()[1].details.text, "ilvl 24   Vendor: -")
end)

test("tooltip, chat linking, moving and saved-position reload", function()
    local s = setup()
    s.loot(2); s.advance(0.1)
    local row = s.rows()[1]
    row.scripts.OnEnter(row); equal(GameTooltip.link, link(2)); assert(GameTooltip.shown)
    row.scripts.OnClick(row); equal(s.inserted(), link(2))
    row.scripts.OnLeave(row); assert(not GameTooltip.shown)
    SlashCmdList.LOOTLIST("unlock")
    local anchor = LootListAnchor
    -- Named frames are recorded in the mock rather than installed as globals.
    for _, frame in ipairs(s.frames) do if frame.name == "LootListAnchor" then anchor = frame end end
    anchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -150)
    row.scripts.OnDragStart(row); assert(anchor.moving)
    row.scripts.OnDragStop(row)
    equal(LootListDB.position.x, 120)
    local saved = LootListDB
    local nextSession = setup({ db = saved })
    for _, frame in ipairs(nextSession.frames) do
        if frame.name == "LootListAnchor" then equal(frame.point[4], 120); equal(frame.point[5], -150) end
    end
    SlashCmdList.LOOTLIST("reset"); equal(LootListDB.position, nil)
end)

test("secret chat text is ignored before parsing", function()
    local secret = "secret"
    local s = setup({ secret = secret })
    s.event("CHAT_MSG_LOOT", secret); s.advance(1); equal(#s.rows(), 0)
end)

test("pending metadata preserves batch order and remains bounded", function()
    local s = setup()
    for id = 2, 4 do s.ready[id] = false; s.loot(id) end
    s.advance(0.1)
    for id = 2, 4 do s.ready[id] = true end
    s.advance(1)
    equal(s.displayed[1].itemID, 2)
    equal(s.displayed[3].itemID, 4)
    local many = setup()
    for id = 2, 70 do many.ready[id] = false; many.loot(id) end
    many.advance(0.1)
    for id = 2, 70 do many.ready[id] = true end
    many.advance(1)
    equal(#many.displayed, 48)
    equal(many.displayed[1].itemID, 23)
    equal(#many.rows(), 6)
end)

test("pushed self loot works; incomplete metadata waits", function()
    local s = setup()
    s.data[2].price = nil
    s.event("CHAT_MSG_LOOT", "You receive item: " .. link(2) .. "x2.")
    s.advance(0.1); equal(#s.rows(), 0)
    s.data[2].price = 32
    s.event("ITEM_DATA_LOAD_RESULT", 2, true)
    equal(#s.rows(), 1); equal(s.displayed[1].quantity, 2)
end)

test("named-quality and named-global color links retain original markup", function()
    local s = setup()
    for _, prefix in ipairs({ "|cnIQ1:", "|cnWHITE_FONT_COLOR:" }) do
        local value = prefix .. "|Hitem:2:0:0:0|h[Item 2]|h|r"
        s.event("CHAT_MSG_LOOT", "You receive loot: " .. value .. "x3.")
        s.advance(0.11)
        equal(s.displayed[#s.displayed].quantity, 3)
        equal(s.displayed[#s.displayed].itemLink, value)
    end
    equal(#s.displayed, 2)
end)

test("formats changed by localization addons after loading are recognized", function()
    local s = setup()
    LOOT_ITEM_SELF = "Ваша здобич: %s."
    LOOT_ITEM_SELF_MULTIPLE = "Ваша здобич: %sx%d."
    s.event("CHAT_MSG_LOOT", "Ваша здобич: " .. link(2) .. "x4.")
    s.loot(3) -- Native event format still works after globals were replaced.
    s.advance(0.1)
    equal(#s.displayed, 2); equal(s.displayed[1].quantity, 4)
end)

test("unrecognized wording only falls back with confirmed self GUID", function()
    local s = setup()
    local value = "|cnIQ1:|Hitem:2:0|h[Item 2]|h|r"
    local message = "New acquisition format: " .. value .. "x3!"
    local id = s.addon.ParseLoot(message, "Player-other")
    equal(id, nil)
    id = s.addon.ParseLoot(message)
    equal(id, nil)
    local itemID, itemLink, quantity = s.addon.ParseLoot(message, "Player-local")
    equal(itemID, 2); equal(itemLink, value); equal(quantity, 3)
    s.event("CHAT_MSG_LOOT", message, "", "", "", "", "", 0, 0, "", 0, 1, "Player-local")
    s.advance(0.1); equal(#s.rows(), 1); equal(s.displayed[1].quantity, 3)
end)

test("test command exercises real item lookup and notification UI", function()
    local s = setup()
    SlashCmdList.LOOTLIST("test")
    s.advance(0.1)
    equal(#s.rows(), 5); equal(s.displayed[1].itemID, 19019)
    s.advance(5); equal(#s.rows(), 0)
end)

test("hover retains expired row, protects it from overflow, and fades on leave", function()
    local s = setup()
    s.loot(2); s.advance(0.1)
    local held = s.rows()[1]
    s.advance(4.5)
    held.scripts.OnEnter(held)
    equal(held.alpha, 1)
    s.loot(3); s.advance(0.1)
    s.advance(1)
    equal(#s.rows(), 2); assert(held.shown); equal(held.alpha, 1)
    for id = 4, 10 do s.loot(id); s.advance(0.11) end
    equal(#s.rows(), 6); assert(held.shown); equal(held.item.itemID, 2)
    s.advance(10); equal(#s.rows(), 1); assert(GameTooltip.shown)
    held.scripts.OnLeave(held); assert(not GameTooltip.shown)
    s.advance(0.35); assert(held.alpha > 0 and held.alpha < 1)
    s.advance(0.36); equal(#s.rows(), 0)
    s.loot(11); s.advance(0.1); s.advance(5)
    equal(#s.rows(), 0) -- Pooled rows never inherit a previous hover hold.
end)

test("hovered rows keep their position through expiration and new loot sorting", function()
    local s = setup()
    s.loot(3); s.advance(0.1)
    s.loot(2); s.advance(0.1)
    local held
    for _, row in ipairs(s.rows()) do if row.item.itemID == 2 then held = row end end
    local originalY = held.point[5]
    assert(originalY < 0)
    held.scripts.OnEnter(held)
    s.advance(6)
    equal(#s.rows(), 1); equal(held.point[5], originalY); equal(held.y, originalY)
    assert(GameTooltip.shown); equal(held.alpha, 1)
    s.loot(4); s.advance(0.1)
    s.event("CHAT_MSG_MONEY", "You loot 1 Copper")
    s.advance(0.2)
    equal(held.point[5], originalY)
    for _, row in ipairs(s.rows()) do
        if row ~= held then assert(math.abs(row.point[5] - originalY) >= 63) end
    end
    s.advance(6); equal(#s.rows(), 1); equal(held.point[5], originalY)
    held.scripts.OnLeave(held)
    s.advance(0.1); assert(held.point[5] > originalY)
    s.advance(0.61); equal(#s.rows(), 0)
end)

test("five test entries stay during editing, expire on lock, and do not aggregate real loot", function()
    local s = setup()
    SlashCmdList.LOOTLIST("unlock")
    SlashCmdList.LOOTLIST("test")
    s.loot(2, 3)
    s.advance(0.1); equal(#s.rows(), 6)
    local real
    for _, row in ipairs(s.rows()) do
        if not row.item.isPreview then real = row end
    end
    equal(real.item.quantity, 3)
    for _, row in ipairs(s.rows()) do if row.item.isPreview then equal(row.item.quantity, 1) end end
    s.advance(10); equal(#s.rows(), 5)
    SlashCmdList.LOOTLIST("lock")
    s.advance(4.9); equal(#s.rows(), 5)
    s.advance(0.2); equal(#s.rows(), 0)
end)

test("resize handle is edit-only, clamps scale, persists size and stops updating", function()
    local s = setup()
    local anchor, grip
    for _, frame in ipairs(s.frames) do
        if frame.name == "LootListAnchor" then anchor = frame end
        if frame.name == "LootListResizeHandle" then grip = frame end
    end
    assert(not grip.shown)
    grip.scripts.OnDragStart(grip); assert(not grip.scripts.OnUpdate)
    SlashCmdList.LOOTLIST("unlock"); assert(grip.shown)
    grip.scripts.OnDragStart(grip)
    s.cursor(560, 213.5); s.advance(0.01)
    equal(anchor:GetScale(), 1.5)
    grip.scripts.OnDragStop(grip)
    equal(LootListDB.scale, 1.5); assert(not grip.scripts.OnUpdate)
    local nextSession = setup({ db = LootListDB })
    for _, frame in ipairs(nextSession.frames) do
        if frame.name == "LootListAnchor" then equal(frame:GetScale(), 1.5) end
    end
    SlashCmdList.LOOTLIST("unlock")
    for _, frame in ipairs(nextSession.frames) do
        if frame.name == "LootListResizeHandle" then grip = frame end
        if frame.name == "LootListAnchor" then anchor = frame end
    end
    grip.scripts.OnDragStart(grip)
    nextSession.cursor(10000, -10000); nextSession.advance(0.01)
    equal(anchor:GetScale(), 1.75)
    SlashCmdList.LOOTLIST("lock"); assert(not grip.shown); assert(not grip.scripts.OnUpdate)
    SlashCmdList.LOOTLIST("unlock")
    nextSession.cursor(400, 400); grip.scripts.OnDragStart(grip)
    nextSession.cursor(-10000, 10000); nextSession.advance(0.01)
    equal(anchor:GetScale(), 0.65)
    grip.scripts.OnDragStop(grip)
    SlashCmdList.LOOTLIST("reset"); equal(anchor:GetScale(), 0.65)
end)

test("preview uses five real sample items without requiring equipped gear", function()
    local s = setup({ equipped = { [16] = link(2), [5] = link(3), [1] = link(4),
        [7] = link(5), [8] = link(6) } })
    SlashCmdList.LOOTLIST("test"); s.advance(0.1)
    equal(#s.rows(), 5)
    for i, item in ipairs(s.displayed) do equal(item.itemQuality, 6 - i); equal(item.quantity, 1) end
end)

test("money loot shows amount/icon without item-only details or interactions", function()
    local s = setup()
    s.event("CHAT_MSG_MONEY", "You loot 2 Gold, 15 Silver, 44 Copper")
    equal(#s.rows(), 1)
    local row = s.rows()[1]
    equal(row.name.text, "2g 15s 44c")
    equal(row.icon.texture, "Interface\\Icons\\INV_Misc_Coin_01")
    assert(not row.details.shown); equal(row.details.text, "")
    row.scripts.OnEnter(row); assert(not GameTooltip.shown)
    row.scripts.OnClick(row); equal(s.inserted(), nil)
    s.advance(10); equal(#s.rows(), 1)
    row.scripts.OnLeave(row); s.advance(0.71); equal(#s.rows(), 0)
    s.loot(2); s.advance(0.1)
    row = s.rows()[1]
    assert(row.details.shown); equal(row.details.text, "ilvl 24   Vendor: 32c")
end)

test("money parsing supports group shares, bonuses, textures and localized plurals", function()
    local s = setup()
    equal(s.addon.ParseMoney("Your share of the loot is 4 Silver, 18 Copper."), 418)
    equal(s.addon.ParseMoney("You loot 1 Gold (+2 Silver)"), 10200)
    equal(s.addon.ParseMoney("You loot 32 Copper (+4 Copper)"), 36)
    equal(s.addon.ParseMoney("Your share of the loot is 4 Silver. (1 Gold deposited in guild bank)"), 400)
    equal(s.addon.ParseMoney("You loot 2|TInterface\\MoneyFrame\\UI-GoldIcon:0:0|t 3|TInterface\\MoneyFrame\\UI-SilverIcon:0:0|t 4|TInterface\\MoneyFrame\\UI-CopperIcon:0:0|t"), 20304)
    GOLD_AMOUNT = "%d |4золота:золоті:золотих;"
    SILVER_AMOUNT = "%d |4срібна:срібні:срібних;"
    COPPER_AMOUNT = "%d |4мідна монета:мідні монети:мідних монет;"
    YOU_LOOT_MONEY = "Ваша здобич: %s"
    equal(s.addon.ParseMoney("Ваша здобич: 2 золоті, 3 срібні, 4 мідних монет"), 20304)
    equal(s.addon.ParseMoney("You loot 32 Copper"), 32)
    equal(s.addon.ParseMoney("You loot 1,234 Gold"), 12340000)
    equal(s.addon.ParseMoney("Someone else loots 1 Gold"), nil)
    equal(s.addon.ParseMoney("You pay 1 Gold"), nil)
    equal(s.addon.ParseMoney("You loot 0 Copper"), nil)
end)

test("money and item notifications share pooling but expire independently", function()
    local s = setup()
    s.event("CHAT_MSG_MONEY", "You loot 32 Copper")
    s.advance(2)
    s.loot(2); s.advance(0.1)
    equal(#s.rows(), 2)
    s.advance(3); equal(#s.rows(), 1); equal(s.rows()[1].item.itemID, 2)
    s.advance(2.1); equal(#s.rows(), 0)
    local frames = #s.frames
    for i = 1, 8 do s.event("CHAT_MSG_MONEY", "You loot 32 Copper") end
    equal(#s.rows(), 1); equal(s.rows()[1].name.text, "2s 56c"); equal(#s.frames, frames)
    s.advance(5); equal(#s.rows(), 0)
    for _, frame in ipairs(s.frames) do assert(not frame.scripts.OnUpdate) end
end)

test("restricted money messages are ignored without parsing or rendering", function()
    local s = setup({ secret = "secret money" })
    s.event("CHAT_MSG_MONEY", "secret money")
    s.event("CHAT_MSG_MONEY", "You loot 0 Copper")
    equal(#s.rows(), 0)
end)

test("money colors follow denomination and accumulated threshold crossings", function()
    local s = setup()
    local function checkColor(row, r, g, b)
        for i, value in ipairs({ r, g, b }) do
            equal(row.name.color[i], value)
            equal(row.border[i], value)
            equal(row.background[i], 0.02 + value * 0.18)
        end
        equal(row.background[4], 0.9)
    end
    s.event("CHAT_MSG_MONEY", "You loot 99 Copper")
    local row = s.rows()[1]
    checkColor(row, 0.8, 0.5, 0.2)
    s.event("CHAT_MSG_MONEY", "You loot 1 Copper")
    equal(s.rows()[1], row); equal(row.name.text, "1s")
    checkColor(row, 0.75, 0.75, 0.8)
    s.event("CHAT_MSG_MONEY", "You loot 99 Silver")
    equal(s.rows()[1], row); equal(row.name.text, "1g")
    checkColor(row, 1, 0.82, 0)
    s.advance(6)
    s.event("CHAT_MSG_MONEY", "You loot 1 Silver, 2 Copper")
    checkColor(s.rows()[1], 0.75, 0.75, 0.8)
    s.advance(6)
    s.event("CHAT_MSG_MONEY", "You loot 1 Gold, 2 Silver, 3 Copper")
    checkColor(s.rows()[1], 1, 0.82, 0)
    s.advance(6)
    s.event("CHAT_MSG_MONEY", "You loot 1 Copper")
    checkColor(s.rows()[1], 0.8, 0.5, 0.2)
end)

test("money accumulates at the top and resets only its own deadline", function()
    local s = setup()
    s.event("CHAT_MSG_MONEY", "You loot 66 Copper")
    local money = s.rows()[1]
    equal(money.name.text, "66c")
    s.advance(1)
    s.loot(2); s.advance(0.1)
    s.advance(3.5)
    assert(money.alpha < 1)
    s.event("CHAT_MSG_MONEY", "You loot 1 Silver, 20 Copper")
    equal(money.name.text, "1s 86c"); equal(money.alpha, 1)
    equal(#s.rows(), 2)
    s.loot(3); s.advance(0.1)
    for _, row in ipairs(s.rows()) do
        if row == money then equal(row.point[5], 0)
        else assert(row.point[5] < 0) end
    end
    s.advance(1.5)
    local oldItemVisible = false
    for _, row in ipairs(s.rows()) do if row.item.itemID == 2 then oldItemVisible = true end end
    assert(not oldItemVisible)
    s.advance(3.3); assert(money.shown)
    s.advance(0.11); assert(not money.shown)
    s.advance(1); equal(#s.rows(), 0)
    s.event("CHAT_MSG_MONEY", "You loot 7 Copper")
    equal(s.rows()[1].name.text, "7c") -- A fresh visible session starts a fresh total.
end)

test("money remains pinned through item overflow and hover while accumulating", function()
    local s = setup()
    s.loot(2); s.advance(0.1)
    s.event("CHAT_MSG_MONEY", "You loot 66 Copper")
    local money
    for _, row in ipairs(s.rows()) do if row.item.kind == "money" then money = row end end
    money.scripts.OnEnter(money)
    local frames = #s.frames
    for id = 3, 12 do s.loot(id); s.advance(0.11) end
    equal(#s.rows(), 6); equal(#s.frames, frames)
    assert(money.shown); equal(money.point[5], 0)
    s.advance(20); equal(#s.rows(), 1)
    s.event("CHAT_MSG_MONEY", "You loot 1 Silver, 20 Copper")
    equal(#s.rows(), 1); equal(money.name.text, "1s 86c")
    money.scripts.OnLeave(money)
    s.advance(4.9); assert(money.shown)
    s.advance(0.2); equal(#s.rows(), 0)
end)

test("minimap opens settings/unlocks; closing locks; new command preserves aliases", function()
    local s = setup()
    equal(SLASH_LOOTLIST1, "/lootlist")
    equal(SLASH_LOOTLIST2, "/lootdisplay")
    equal(SLASH_LOOTLIST3, "/lloot")
    local panel, minimap, grip
    for _, frame in ipairs(s.frames) do
        if frame.name == "LootListSettingsPanel" then panel = frame end
        if frame.name == "LootListMinimapButton" then minimap = frame end
        if frame.name == "LootListResizeHandle" then grip = frame end
    end
    assert(minimap.shown); assert(not panel.shown); assert(not grip.shown)
    for _, frame in ipairs(s.frames) do assert(frame.text ~= "Preview loot list") end
    minimap.scripts.OnClick(minimap)
    assert(panel.shown); assert(grip.shown)
    s.advance(0.11); equal(#s.rows(), 5)
    for _, row in ipairs(s.rows()) do assert(row.item.isPreview) end
    s.advance(10); equal(#s.rows(), 5)
    panel:Hide(); assert(not grip.shown)
    s.advance(5.1); equal(#s.rows(), 0)
    SlashCmdList.LOOTLIST(""); assert(panel.shown); assert(grip.shown)
    s.advance(0.11); equal(#s.rows(), 5)
    SlashCmdList.LOOTLIST("lock"); assert(not panel.shown); assert(not grip.shown)
    SlashCmdList.LOOTLIST("settings"); assert(panel.shown)
    s.advance(0.11); equal(#s.rows(), 5)
end)

test("rarity controls enable junk, disable common, preserve money and persist", function()
    local s = setup()
    local boxes = {}
    for _, frame in ipairs(s.frames) do
        if frame.kind == "CheckButton" and frame.name ~= "LootListGroupEnabledCheck" then boxes[#boxes + 1] = frame end
    end
    equal(#boxes, 6); assert(not boxes[1]:GetChecked()); assert(boxes[2]:GetChecked())
    boxes[1]:SetChecked(true); boxes[1].scripts.OnClick(boxes[1])
    boxes[2]:SetChecked(false); boxes[2].scripts.OnClick(boxes[2])
    s.loot(1); s.loot(2); s.advance(0.1)
    equal(#s.rows(), 1); equal(s.rows()[1].item.itemQuality, 0)
    s.event("CHAT_MSG_MONEY", "You loot 66 Copper"); equal(#s.rows(), 2)
    boxes[1]:SetChecked(false); boxes[1].scripts.OnClick(boxes[1])
    equal(#s.rows(), 1); equal(s.rows()[1].item.kind, "money")
    local saved = LootListDB
    local nextSession = setup({ db = saved })
    assert(not nextSession.addon.IsQualityEnabled(1)); assert(not nextSession.addon.IsQualityEnabled(0))
    nextSession.data[3].quality = 3; nextSession.loot(3); nextSession.advance(0.1)
    equal(#nextSession.rows(), 1)
    nextSession.addon.SetQualityEnabled(3, false); equal(#nextSession.rows(), 0)
end)

test("duration slider applies saved delay to items and money and survives reload", function()
    local s = setup()
    local slider
    for _, frame in ipairs(s.frames) do if frame.name == "LootListDurationSlider" then slider = frame end end
    slider:SetValue(10)
    equal(LootListDB.duration, 10)
    s.loot(2); s.advance(0.1)
    s.event("CHAT_MSG_MONEY", "You loot 66 Copper")
    s.advance(6); equal(#s.rows(), 2)
    s.event("CHAT_MSG_MONEY", "You loot 1 Silver, 20 Copper")
    s.advance(4.1); equal(#s.rows(), 1); equal(s.rows()[1].name.text, "1s 86c")
    s.advance(6); equal(#s.rows(), 0)
    local nextSession = setup({ db = LootListDB })
    equal(nextSession.addon.GetDuration(), 10)
    nextSession.addon.SetDuration(0); equal(nextSession.addon.GetDuration(), 1)
    nextSession.addon.SetDuration(100); equal(nextSession.addon.GetDuration(), 30)
end)

test("opacity slider preserves icons and fading and survives reload", function()
    local s = setup()
    local slider, anchor
    for _, frame in ipairs(s.frames) do
        if frame.name == "LootListOpacitySlider" then slider = frame end
        if frame.name == "LootListAnchor" then anchor = frame end
    end
    equal(anchor.alpha, nil)
    s.loot(2); s.advance(0.1)
    s.event("CHAT_MSG_MONEY", "You loot 99 Copper")
    slider:SetValue(45)
    equal(LootListDB.opacity, 45); equal(anchor.alpha, nil)
    for _, row in ipairs(s.rows()) do
        equal(row.parent, anchor); equal(row.alpha, 1)
        equal(row.icon.alpha, nil)
        equal(row.name.alpha, 0.45); equal(row.details.alpha, 0.45)
        equal(row.background[4], 0.9 * 0.45); equal(row.border[4], 0.65 * 0.45)
    end
    s.advance(4.5)
    assert(s.rows()[1].alpha < 1)
    s.event("CHAT_MSG_MONEY", "You loot 1 Copper")
    equal(s.rows()[1].alpha, 1); equal(s.rows()[1].name.alpha, 0.45)
    equal(s.rows()[1].background[4], 0.9 * 0.45)
    local nextSession = setup({ db = LootListDB })
    equal(nextSession.addon.GetOpacity(), 0.45)
    for _, frame in ipairs(nextSession.frames) do
        if frame.name == "LootListAnchor" then equal(frame.alpha, nil) end
    end
    nextSession.loot(2); nextSession.advance(0.1)
    equal(nextSession.rows()[1].name.alpha, 0.45)
    equal(nextSession.rows()[1].icon.alpha, nil)
    nextSession.addon.SetOpacity(0); equal(nextSession.addon.GetOpacity(), 0.1)
    nextSession.addon.SetOpacity(150); equal(nextSession.addon.GetOpacity(), 1)
    local invalid = setup({ db = { opacity = "invalid" } })
    equal(invalid.addon.GetOpacity(), 1)
end)

test("minimap dragging saves its angle with no permanent update handler", function()
    local s = setup()
    local button
    for _, frame in ipairs(s.frames) do if frame.name == "LootListMinimapButton" then button = frame end end
    button.scripts.OnDragStart(button)
    s.cursor(600, 500); s.advance(0.1)
    equal(LootListDB.minimapAngle, 0)
    button.scripts.OnDragStop(button); assert(not button.scripts.OnUpdate)
    local nextSession = setup({ db = LootListDB })
    for _, frame in ipairs(nextSession.frames) do
        if frame.name == "LootListMinimapButton" then
            equal(frame.point[4], 80); equal(frame.point[5], 0)
        end
    end
end)

test("pending item observes updated rarity settings when metadata arrives", function()
    local s = setup()
    s.ready[2] = false; s.loot(2); s.advance(0.1)
    s.addon.SetQualityEnabled(1, false)
    s.ready[2] = true; s.event("ITEM_DATA_LOAD_RESULT", 2, true)
    equal(#s.rows(), 0)
end)

test("preview filters rare examples and fills from enabled rarities", function()
    local s = setup({ equipped = { [3] = link(3), [16] = link(2) } })
    s.data[3].quality = 3
    s.addon.SetQualityEnabled(3, false)
    SlashCmdList.LOOTLIST("test"); s.advance(0.11)
    equal(#s.rows(), 5)
    for _, row in ipairs(s.rows()) do assert(row.item.itemQuality ~= 3) end
    for quality = 0, 5 do s.addon.SetQualityEnabled(quality, false) end
    equal(#s.rows(), 0)
    local count = 0
    for _, frame in ipairs(s.frames) do if frame.kind == "CheckButton" then count = count + 1 end end
    equal(count, 7)
    equal(LootListDB.qualities[7], nil); equal(LootListDB.qualities[8], nil)
end)

test("mail overflow displays every queued item at the bottom in acquisition order", function()
    local s = setup()
    local frames = #s.frames
    for id = 2, 10 do s.loot(id) end
    s.advance(0.11)
    local function ordered()
        local rows = s.rows()
        table.sort(rows, function(a, b) return a.y > b.y end)
        return rows
    end
    local first = ordered()
    equal(#first, 6)
    for i, row in ipairs(first) do equal(row.item.itemID, i + 1) end
    s.advance(5.1)
    local second = ordered()
    equal(#second, 3)
    for i, row in ipairs(second) do equal(row.item.itemID, i + 7) end
    equal(#s.frames, frames)
    s.advance(5.1); equal(#s.rows(), 0)
end)

test("rarity backgrounds preserve opacity without any glow", function()
    local s = setup()
    s.addon.SetQualityEnabled(0, true)
    for quality = 0, 5 do
        local id = quality + 2
        s.data[id].quality = quality
        s.loot(id); s.advance(0.11)
        local row = s.rows()[1]
        equal(row.background[4], 0.9)
        equal(row.background[1], 0.02 + ITEM_QUALITY_COLORS[quality].r * 0.18)
        equal(row.glowInner, nil); equal(row.glowOuter, nil)
        s.advance(5.1)
    end
    s.event("CHAT_MSG_MONEY", "You loot 1 Gold")
    local row = s.rows()[1]
    equal(row.background[4], 0.9)
    equal(row.background[1], 0.02 + 0.18)
    equal(row.glowInner, nil); equal(row.glowOuter, nil)
end)

test("sample preview includes enabled tiers and refreshes without adding frames or backlog", function()
    local s = setup({ equipped = {} })
    s.addon.SetQualityEnabled(0, true)
    SlashCmdList.LOOTLIST("unlock")
    local count = #s.frames
    SlashCmdList.LOOTLIST("test"); s.advance(0.11)
    equal(#s.rows(), 6)
    SlashCmdList.LOOTLIST("test"); s.advance(0.11)
    equal(#s.rows(), 6); equal(#s.frames, count)
    local qualities = {}
    for _, row in ipairs(s.rows()) do qualities[row.item.itemQuality] = true end
    for quality = 0, 5 do assert(qualities[quality]) end
    SlashCmdList.LOOTLIST("lock"); s.advance(5.1)
    equal(#s.rows(), 0)
end)

test("sample previews defer uncached item metadata and keep real tooltip links", function()
    local s = setup({ equipped = {} })
    s.ready[19019] = false
    SlashCmdList.LOOTLIST("unlock")
    SlashCmdList.LOOTLIST("test"); s.advance(0.11)
    equal(#s.rows(), 4)
    s.ready[19019] = true
    s.event("ITEM_DATA_LOAD_RESULT", 19019, true)
    equal(#s.rows(), 5)
    for _, row in ipairs(s.rows()) do
        if row.item.itemID == 19019 then
            equal(row.item.itemLink, link(19019))
            equal(row.item.itemQuality, 5)
            equal(row.glowInner, nil)
            row.scripts.OnEnter(row); equal(GameTooltip.link, link(19019))
        end
    end
end)

test("rare and epic previews fall back when primary metadata is unavailable", function()
    local s = setup()
    s.ready[5191], s.ready[871] = false, false
    SlashCmdList.LOOTLIST("unlock")
    SlashCmdList.LOOTLIST("test"); s.advance(0.11)
    equal(#s.rows(), 4)
    s.advance(4.1); equal(#s.rows(), 5)
    local rarities = {}
    for _, row in ipairs(s.rows()) do rarities[row.item.itemQuality] = row.item.itemID end
    equal(rarities[3], 13033); equal(rarities[4], 2825)
end)

test("preview validates actual rare and epic quality rather than guessing color", function()
    local s = setup()
    s.data[5191].quality = 2
    s.data[871].quality = 3
    SlashCmdList.LOOTLIST("test"); s.advance(0.11)
    equal(#s.rows(), 5)
    local rarities = {}
    for _, row in ipairs(s.rows()) do rarities[row.item.itemQuality] = row.item.itemID end
    equal(rarities[3], 13033); equal(rarities[4], 2825)
end)

test("epic preview survives unavailable previous examples and tries client-recognized alternatives", function()
    local s = setup()
    s.ready[871], s.ready[14555], s.ready[18832], s.ready[873] = false, false, false, false
    SlashCmdList.LOOTLIST("unlock")
    SlashCmdList.LOOTLIST("test"); s.advance(4.2)
    local epic
    for _, row in ipairs(s.rows()) do if row.item.itemQuality == 4 then epic = row end end
    assert(epic); equal(epic.item.itemID, 2825)
    equal(#s.rows(), 5)
end)

test("previews sort legendary to junk even when legendary metadata arrives last", function()
    local s = setup()
    s.addon.SetQualityEnabled(0, true)
    s.ready[19019] = false
    SlashCmdList.LOOTLIST("unlock")
    SlashCmdList.LOOTLIST("test"); s.advance(0.11)
    equal(#s.rows(), 5)
    s.ready[19019] = true; s.event("ITEM_DATA_LOAD_RESULT", 19019, true)
    s.advance(0.5)
    local rows = s.rows()
    table.sort(rows, function(a, b) return a.y > b.y end)
    equal(#rows, 6)
    for i, row in ipairs(rows) do equal(row.item.itemQuality, 6 - i) end
    s.event("CHAT_MSG_MONEY", "You loot 66 Copper"); s.advance(0.5)
    rows = s.rows(); table.sort(rows, function(a, b) return a.y > b.y end)
    equal(rows[1].item.kind, "money")
    for i = 2, #rows do equal(rows[i].item.itemQuality, 7 - i) end
end)

test("real loot sorts by rarity with stable ties, pinned money and independent timers", function()
    local s = setup()
    s.addon.SetQualityEnabled(0, true)
    local qualities = { 1, 3, 0, 5, 4, 3 }
    for i, quality in ipairs(qualities) do s.data[i + 1].quality = quality end
    s.event("CHAT_MSG_MONEY", "You loot 66 Copper")
    for id = 2, 6 do s.loot(id); s.advance(0.11) end
    s.advance(0.5)
    local rows = s.rows()
    table.sort(rows, function(a, b) return a.y > b.y end)
    equal(rows[1].item.kind, "money")
    local expected = { 5, 4, 3, 1, 0 }
    for i = 2, #rows do equal(rows[i].item.itemQuality, expected[i - 1]) end
    s.advance(6)
    s.loot(3); s.advance(0.11)
    local first = s.rows()[1]
    s.loot(7); s.advance(0.11); s.advance(0.5)
    rows = s.rows(); table.sort(rows, function(a, b) return a.y > b.y end)
    equal(rows[1].item.itemID, 3); equal(rows[2].item.itemID, 7)
    assert(first.expires < rows[2].expires)
end)

test("epic preview picks cached alternative immediately without Staff of Jordan", function()
    local s = setup()
    s.ready[871] = false
    SlashCmdList.LOOTLIST("test"); s.advance(0.11)
    equal(#s.rows(), 5)
    local found
    for _, row in ipairs(s.rows()) do if row.item.itemQuality == 4 then found = row.item.itemID end end
    equal(found, 2825)
end)

test("group preview is separate, clickable, expires and reuses rows", function()
    local s = setup()
    s.loot(2); s.advance(0.11)
    SlashCmdList.LOOTLIST("grouptest")
    equal(#s.rows(), 1); equal(#s.groupRows(), 3)
    local frames = #s.frames
    SlashCmdList.LOOTLIST("grouptest")
    equal(#s.groupRows(), 3); equal(#s.frames, frames)
    local rows = s.groupRows()
    local results = { "Testplayer\nNeed • Roll 97", "Testplayer\nGreed • Roll 84", "Everyone passed" }
    for i, row in ipairs(rows) do
        assert(row.details.text:find("Voting ongoing", 1, true))
        assert(not row.details.text:find("Vendor", 1, true))
        equal(row.buttons[i].text:gsub("|A:.-|a ", ""), ({ "Need", "Greed", "Pass" })[i])
        row.buttons[i].scripts.OnClick()
        equal(row.resultText.text:gsub("|T.-|t ", ""):gsub("|A:.-|a ", ""), results[i])
        assert(row.resultText.shown); assert(not row.name.shown)
        equal(row.details.text, "Test • " .. row.roll.displayName)
        if i < 3 then assert(row.resultText.text:find("|TInterface/TargetingFrame/UI-Classes-Circles", 1, true)) end
        assert(not row.buttons[1].shown)
        row.buttons[i].scripts.OnClick() -- Finished previews cannot vote twice.
    end
    equal(#s.groupRows(), 3); equal(#s.selections, 0)
    s.advance(10.5); equal(#s.groupRows(), 0)
    SlashCmdList.LOOTLIST("grouptest")
    s.advance(61); equal(#s.groupRows(), 0)
end)

test("group rolls respect eligibility and click-time expiry with independent cancellation", function()
    local s = setup()
    s.rolls[11] = { expires = 30, need = false, greed = true }
    s.rolls[12] = { expires = 60, need = true, greed = true }
    s.event("START_LOOT_ROLL", 11, 30000)
    s.event("START_LOOT_ROLL", 12, 60000)
    s.event("START_LOOT_ROLL", 11, 30000)
    equal(#s.groupRows(), 2)
    local first = s.groupRows()[1]
    assert(first.buttons[1].disabled); assert(not first.buttons[2].disabled)
    first.buttons[1].scripts.OnClick(); equal(#s.selections, 0)
    first.buttons[2].scripts.OnClick(); equal(s.selections[1][1], 11); equal(s.selections[1][2], 2)
    s.rolls[11].expires = 0
    first.buttons[3].scripts.OnClick(); equal(#s.selections, 1)
    s.advance(0.3); equal(#s.groupRows(), 2)
    assert(first.details.text:find("Voting ongoing", 1, true)); assert(first.buttons[3].disabled)
    s.groupRows()[2].buttons[1].scripts.OnClick(); equal(s.selections[2][2], 1)
    s.groupRows()[2].buttons[3].scripts.OnClick(); equal(s.selections[3][2], 0)
    SlashCmdList.LOOTLIST("grouptest")
    s.event("CANCEL_LOOT_ROLL", 12); equal(#s.groupRows(), 5)
    s.rolls[13] = { expires = 60, need = true, greed = true }
    s.event("START_LOOT_ROLL", 13, 60000)
    s.event("CANCEL_ALL_LOOT_ROLLS"); equal(#s.groupRows(), 6)
    s.advance(21); equal(#s.groupRows(), 6)
end)

test("restricted group event payloads do not create rows", function()
    local s = setup({ secret = 11 })
    s.event("START_LOOT_ROLL", 11, 60000)
    s.event("START_LOOT_ROLL", 12, 11)
    s.event("START_LOOT_ROLL", nil, 60000)
    equal(#s.groupRows(), 0)
end)

test("group history shows voting progress then authoritative need and greed winners", function()
    local s = setup()
    for i, state in ipairs({ 0, 3 }) do
        local id = 20 + i
        s.rolls[id] = { expires = 60, need = true, greed = true, itemID = i + 2 }
        s.event("START_LOOT_ROLL", id, 60000)
        local drop = { lootListKey = 200 + i, itemHyperlink = link(i + 2), startTime = 1000,
            rollInfos = { { state = state }, { state = 4 } } }
        s.history[i] = drop
        s.event("LOOT_HISTORY_UPDATE_DROP", 100, drop.lootListKey)
        local row = s.groupRows()[i]
        assert(row.details.text:find("Voting ongoing • 1/2", 1, true))
        drop.rollInfos[2].state = 5
        s.event("LOOT_HISTORY_UPDATE_DROP", 100, drop.lootListKey)
        equal(row.details.text, "Voting complete • awaiting result")
        assert(row.buttons[1].disabled)
        row.buttons[1].scripts.OnClick(); equal(#s.selections, 0)
        drop.winner = { playerName = "Winner-Realm", playerClass = "MAGE", state = state, roll = 98 - i }
        s.event("LOOT_HISTORY_UPDATE_DROP", 100, drop.lootListKey)
        equal(row.resultText.text:gsub("|T.-|t ", ""):gsub("|A:.-|a ", ""), "Winner-Realm\n" .. (state == 0 and "Need" or "Greed") .. " • Roll " .. (98 - i))
        assert(row.resultText.text:find("|A:lootroll-toast-icon-" .. (state == 0 and "need" or "greed") .. "-up:18:18|a", 1, true))
        assert(row.resultText.text:find(":256:256:64:127:0:64|t Winner-Realm", 1, true))
        assert(not row.buttons[1].shown)
        s.event("CANCEL_LOOT_ROLL", id)
        assert(row.shown)
    end
    s.advance(10.5); equal(#s.groupRows(), 0)
end)

test("group results survive cancellation before late history and handle all passed", function()
    local s = setup()
    s.rolls[30] = { expires = 60, need = true, greed = true }
    s.event("START_LOOT_ROLL", 30, 60000)
    local row = s.groupRows()[1]
    s.event("CANCEL_LOOT_ROLL", 30)
    s.advance(1)
    s.history[1] = { lootListKey = 301, itemHyperlink = link(2), startTime = 1000, allPassed = true }
    s.event("LOOT_HISTORY_UPDATE_ENCOUNTER", 100)
    equal(row.resultText.text, "Everyone passed")
    assert(not row.buttons[3].shown)
    s.event("CANCEL_ALL_LOOT_ROLLS"); assert(row.shown)
    s.advance(10.5); assert(not row.shown)
end)

test("group history rejects stale and ambiguous same-item results", function()
    local s = setup()
    s.history[1] = { lootListKey = 401, itemHyperlink = link(2), startTime = 900,
        winner = { playerName = "Oldwinner", state = 0, roll = 100 } }
    s.rolls[40] = { expires = 60, need = true, greed = true }
    s.rolls[41] = { expires = 60, need = true, greed = true }
    s.event("START_LOOT_ROLL", 40, 60000)
    assert(not s.groupRows()[1].roll.result)
    s.event("START_LOOT_ROLL", 41, 60000)
    s.history[2] = { lootListKey = 402, itemHyperlink = link(2), startTime = 1000,
        winner = { playerName = "Unknownwhichitem", state = 3, roll = 80 } }
    s.event("LOOT_HISTORY_UPDATE_DROP", 100, 402)
    for _, row in ipairs(s.groupRows()) do assert(not row.roll.result) end
end)

test("restricted group history cannot supply a winner and missing history degrades safely", function()
    local s = setup({ secret = "Hiddenwinner" })
    s.rolls[50] = { expires = 60, need = true, greed = true }
    s.event("START_LOOT_ROLL", 50, 60000)
    s.history[1] = { lootListKey = 501, itemHyperlink = link(2), startTime = 1000,
        winner = { playerName = "Hiddenwinner", state = 0, roll = 100 } }
    s.event("LOOT_HISTORY_UPDATE_DROP", 100, 501)
    assert(not s.groupRows()[1].roll.result)
    local missing = setup({ noHistory = true })
    missing.rolls[51] = { expires = 1, need = true, greed = true }
    missing.event("START_LOOT_ROLL", 51, 1000)
    missing.advance(12)
    equal(missing.groupRows()[1].resultText.text, "Roll ended • result unavailable")
    missing.advance(11); equal(#missing.groupRows(), 0)
end)

test("group mover saves an independent position and restores it after reload", function()
    local s = setup()
    local anchor, mover
    for _, frame in ipairs(s.frames) do
        if frame.name == "LootListGroupAnchor" then anchor = frame end
        if frame.name == "LootListGroupMover" then mover = frame end
    end
    equal(anchor.parent, UIParent)
    assert(not mover.shown)
    SlashCmdList.LOOTLIST("grouptest"); assert(mover.shown)
    mover.scripts.OnDragStart(mover); assert(anchor.moving)
    anchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -240)
    mover.scripts.OnDragStop(mover)
    equal(LootListDB.groupPosition.x, 120); equal(LootListDB.groupPosition.y, -240)
    equal(LootListDB.position, nil)
    local saved = LootListDB
    local nextSession = setup({ db = saved })
    for _, frame in ipairs(nextSession.frames) do
        if frame.name == "LootListGroupAnchor" then
            equal(frame.point[1], "TOPLEFT"); equal(frame.point[2], UIParent)
            equal(frame.point[4], 120); equal(frame.point[5], -240)
        end
    end
end)

test("group mover rejects malformed saved positions", function()
    local s = setup({ db = { groupPosition = { point = "BAD", relativePoint = "TOPLEFT", x = math.huge, y = 0 } } })
    for _, frame in ipairs(s.frames) do
        if frame.name == "LootListGroupAnchor" then
            equal(frame.point[1], "TOPRIGHT"); equal(frame.point[4], -16)
        end
    end
end)

test("missing or restricted winner class keeps the name without a guessed icon", function()
    for _, class in ipairs({ "UNKNOWN", "Hiddenclass" }) do
        local s = setup({ secret = "Hiddenclass" })
        s.rolls[60] = { expires = 60, need = true, greed = true }
        s.event("START_LOOT_ROLL", 60, 60000)
        s.history[1] = { lootListKey = 601, itemHyperlink = link(2), startTime = 1000,
            winner = { playerName = "Winner", playerClass = class, state = 0, roll = 92 } }
        s.event("LOOT_HISTORY_UPDATE_DROP", 100, 601)
        equal(s.groupRows()[1].resultText.text:gsub("|A:.-|a ", ""), "Winner\nNeed • Roll 92")
    end
end)

test("group animations change with voting and stop when pooled", function()
    local s = setup()
    SlashCmdList.LOOTLIST("grouptest")
    local row = s.groupRows()[1]
    assert(row.voteAnimation.playing); assert(row.voteGlow.shown)
    s.advance(1); equal(row.voteAnimation.playCount, 1)
    row.buttons[1].scripts.OnClick()
    assert(not row.voteAnimation.playing); assert(not row.voteGlow.shown)
    assert(row.resultAnimation.playing); assert(row.resultGlow.shown)
    s.advance(1); equal(row.resultAnimation.playCount, 1)
    row.resultAnimation.scripts.OnFinished(); assert(not row.resultGlow.shown)
    s.advance(10); assert(not row.resultAnimation.playing); assert(not row.shown)
    SlashCmdList.LOOTLIST("grouptest")
    for _, reused in ipairs(s.groupRows()) do
        assert(reused.voteAnimation.playing); assert(not reused.resultAnimation.playing)
        assert(not reused.resultGlow.shown)
    end
end)

test("winner sound plays once for each confirmed winner and stays silent for all passed", function()
    local s = setup()
    s.rolls[70] = { expires = 60, need = true, greed = true }
    s.event("START_LOOT_ROLL", 70, 60000)
    equal(#s.sounds, 0)
    s.history[1] = { lootListKey = 701, itemHyperlink = link(2), startTime = 1000,
        winner = { playerName = "Winner", state = 3, roll = 91 } }
    s.event("LOOT_HISTORY_UPDATE_DROP", 100, 701)
    equal(#s.sounds, 1); equal(s.sounds[1], SOUNDKIT.UI_NEED_ROLL_POSITIVE)
    s.event("LOOT_HISTORY_UPDATE_DROP", 100, 701)
    s.event("CANCEL_LOOT_ROLL", 70)
    s.advance(1); equal(#s.sounds, 1)
    SlashCmdList.LOOTLIST("grouptest")
    local rows = s.groupRows()
    rows[2].buttons[3].scripts.OnClick(); equal(#s.sounds, 1)
    rows[3].buttons[1].scripts.OnClick(); equal(#s.sounds, 2)
    rows[3].buttons[1].scripts.OnClick(); equal(#s.sounds, 2)
    local missing = setup({ noSound = true })
    SlashCmdList.LOOTLIST("grouptest")
    missing.groupRows()[1].buttons[1].scripts.OnClick()
    assert(missing.groupRows()[1].roll.result); equal(#missing.sounds, 0)
end)

test("group resize clamps, persists independently and stops when hidden", function()
    local s = setup()
    local anchor, handle
    for _, frame in ipairs(s.frames) do
        if frame.name == "LootListGroupAnchor" then anchor = frame end
        if frame.name == "LootListGroupResizeHandle" then handle = frame end
    end
    assert(not handle.shown)
    SlashCmdList.LOOTLIST("grouptest"); assert(handle.shown)
    handle.scripts.OnDragStart(handle)
    s.cursor(100000, -100000); s.advance(0.1)
    equal(anchor:GetScale(), 1.75)
    handle.scripts.OnDragStop(handle)
    assert(not handle.scripts.OnUpdate)
    equal(LootListDB.groupScale, 1.75); equal(LootListDB.scale, nil)
    equal(LootListDB.groupPosition.point, "TOPLEFT")
    local reloaded = setup({ db = LootListDB })
    for _, frame in ipairs(reloaded.frames) do
        if frame.name == "LootListGroupAnchor" then equal(frame:GetScale(), 1.75) end
        if frame.name == "LootListGroupResizeHandle" then assert(not frame.shown) end
    end
    SlashCmdList.LOOTLIST("grouptest")
    local nextHandle, nextAnchor
    for _, frame in ipairs(reloaded.frames) do
        if frame.name == "LootListGroupAnchor" then nextAnchor = frame end
        if frame.name == "LootListGroupResizeHandle" then nextHandle = frame end
    end
    nextHandle.scripts.OnDragStart(nextHandle)
    reloaded.cursor(-100000, 100000); reloaded.advance(0.1)
    equal(nextAnchor:GetScale(), 0.65)
    reloaded.advance(61)
    assert(not nextHandle.shown); assert(not nextHandle.scripts.OnUpdate)
    equal(LootListDB.groupScale, 0.65)
end)

test("group checkbox disables rows, events and test command immediately and persists", function()
    local s = setup()
    local check, grip
    for _, frame in ipairs(s.frames) do
        if frame.name == "LootListGroupEnabledCheck" then check = frame end
        if frame.name == "LootListGroupResizeHandle" then grip = frame end
    end
    assert(check:GetChecked()); assert(s.addon.IsGroupLootEnabled())
    s.loot(2); s.advance(0.1)
    SlashCmdList.LOOTLIST("grouptest")
    local rows = s.groupRows()
    grip.scripts.OnDragStart(grip)
    check:SetChecked(false); check.scripts.OnClick(check)
    assert(not LootListDB.groupEnabled); equal(#s.groupRows(), 0)
    assert(not grip.shown); assert(not grip.scripts.OnUpdate)
    equal(#s.rows(), 1)
    for _, row in ipairs(rows) do
        assert(not row.voteAnimation.playing); assert(not row.resultAnimation.playing)
        row.buttons[1].scripts.OnClick()
    end
    equal(#s.selections, 0); equal(#s.sounds, 0)
    s.rolls[75] = { expires = 60, need = true, greed = true }
    s.event("START_LOOT_ROLL", 75, 60000)
    SlashCmdList.LOOTLIST("grouptest"); equal(#s.groupRows(), 0)
    s.advance(0.5); equal(#s.groupRows(), 0)
    local nextSession = setup({ db = LootListDB })
    assert(not nextSession.addon.IsGroupLootEnabled())
    for _, frame in ipairs(nextSession.frames) do
        if frame.name == "LootListGroupEnabledCheck" then
            assert(not frame:GetChecked())
            frame:SetChecked(true); frame.scripts.OnClick(frame)
        end
    end
    nextSession.rolls[76] = { expires = 60, need = true, greed = true }
    nextSession.event("START_LOOT_ROLL", 76, 60000)
    equal(#nextSession.groupRows(), 1)
end)

test("rapid group toggles invalidate old timers and preserve the enabled preview", function()
    local s = setup({ db = { groupEnabled = "invalid" } })
    assert(s.addon.IsGroupLootEnabled())
    SlashCmdList.LOOTLIST("grouptest")
    s.addon.SetGroupLootEnabled(false)
    s.addon.SetGroupLootEnabled(true)
    SlashCmdList.LOOTLIST("grouptest")
    s.advance(0.5)
    equal(#s.groupRows(), 3)
    s.groupRows()[1].buttons[1].scripts.OnClick(); equal(#s.sounds, 1)
end)

test("group waits the full client voting duration plus five seconds after a local vote", function()
    local s = setup()
    s.rolls[80] = { expires = 60, need = true, greed = true }
    s.event("START_LOOT_ROLL", 80, 60000)
    local row = s.groupRows()[1]
    row.buttons[1].scripts.OnClick()
    s.rolls[80].expires = 0
    s.event("CANCEL_LOOT_ROLL", 80)
    s.advance(45)
    assert(row.shown); assert(not row.roll.result)
    assert(row.details.text:find("Voting ongoing", 1, true))
    assert(row.voteAnimation.playing)
    s.history[1] = { lootListKey = 801, itemHyperlink = link(2), startTime = 1000,
        winner = { playerName = "Latewinner", state = 0, roll = 96 } }
    s.event("LOOT_HISTORY_UPDATE_DROP", 100, 801)
    assert(row.resultText.text:find("Latewinner", 1, true)); equal(#s.sounds, 1)
end)

test("group result timeout is anchored to roll start and includes the five-second grace", function()
    local s = setup({ noHistory = true })
    s.rolls[81] = { expires = 60, need = true, greed = true }
    s.event("START_LOOT_ROLL", 81, 60000)
    local row = s.groupRows()[1]
    s.event("CANCEL_LOOT_ROLL", 81)
    s.advance(60)
    assert(not row.roll.result)
    assert(row.details.text:find("awaiting result", 1, true))
    s.advance(4.75); assert(not row.roll.result)
    s.advance(0.5); equal(row.resultText.text, "Roll ended • result unavailable")
end)

test("dungeon history records distinct identical drops, updates results and survives reload", function()
    local instance = { id = 36, kind = "party", name = "The Deadmines", difficulty = 1 }
    local s = setup({ instance = instance })
    s.event("PLAYER_ENTERING_WORLD")
    equal(LootListDB.groupHistory.instanceID, 36)
    s.history[1] = { lootListKey = 901, itemHyperlink = link(2), startTime = 1000,
        rollInfos = { { state = 0 }, { state = 4 } } }
    s.history[2] = { lootListKey = 902, itemHyperlink = link(2), startTime = 1001, allPassed = true }
    s.event("LOOT_HISTORY_UPDATE_DROP", 100, 901)
    equal(#LootListDB.groupHistory.entries, 2)
    SlashCmdList.LOOTLIST("history")
    equal(#s.historyRows(), 2)
    equal(s.historyRows()[1].resultText.text, "Everyone passed")
    assert(s.historyRows()[2].resultText.text:find("Voting ongoing • 1/2", 1, true))
    s.history[1].winner = { playerName = "Dungeonwinner", playerClass = "MAGE", state = 0, roll = 95 }
    s.event("LOOT_HISTORY_UPDATE_DROP", 100, 901)
    equal(#LootListDB.groupHistory.entries, 2)
    local winnerRow = s.historyRows()[2]
    assert(winnerRow.resultText.text:find("Dungeonwinner", 1, true))
    assert(winnerRow.resultText.text:find("Need • Roll 95", 1, true))
    winnerRow.scripts.OnEnter(winnerRow); equal(GameTooltip.link, link(2))
    winnerRow.scripts.OnClick(winnerRow); equal(s.inserted(), link(2))
    winnerRow.scripts.OnLeave(winnerRow); assert(not GameTooltip.shown)
    s.advance(90); equal(#LootListDB.groupHistory.entries, 2)
    local nextSession = setup({ instance = instance, db = LootListDB })
    nextSession.event("PLAYER_ENTERING_WORLD")
    SlashCmdList.LOOTLIST("history")
    equal(#nextSession.historyRows(), 2)
    assert(nextSession.historyRows()[2].resultText.text:find("Dungeonwinner", 1, true))
end)

test("instance history clears on exit and on switching dungeon or raid", function()
    local s = setup({ instance = { id = 36, kind = "party", name = "Dungeon", difficulty = 1 } })
    s.event("PLAYER_ENTERING_WORLD")
    s.history[1] = { lootListKey = 910, itemHyperlink = link(2), startTime = 1000, allPassed = true }
    s.event("LOOT_HISTORY_UPDATE_ENCOUNTER", 100)
    equal(#LootListDB.groupHistory.entries, 1)
    local old = LootListDB.groupHistory
    s.advance(5)
    s.setInstance({ id = 409, kind = "raid", name = "Molten Core", difficulty = 1 })
    s.event("ZONE_CHANGED_NEW_AREA")
    assert(LootListDB.groupHistory ~= old)
    equal(#LootListDB.groupHistory.entries, 0)
    s.history[2] = { lootListKey = 911, itemHyperlink = link(3), startTime = 1005,
        winner = { playerName = "Raidwinner", state = 3, roll = 89 } }
    s.event("LOOT_HISTORY_UPDATE_DROP", 100, 911)
    equal(#LootListDB.groupHistory.entries, 1)
    s.setInstance(nil); s.event("PLAYER_ENTERING_WORLD")
    equal(LootListDB.groupHistory, nil)
    equal(#s.historyRows(), 0)
    s.event("LOOT_HISTORY_UPDATE_DROP", 100, 911); equal(LootListDB.groupHistory, nil)
end)

test("history shortcuts and isolated preview work outside instances", function()
    local s = setup()
    s.event("PLAYER_ENTERING_WORLD")
    local panel, minimap, button
    for _, frame in ipairs(s.frames) do
        if frame.name == "LootListHistoryPanel" then panel = frame end
        if frame.name == "LootListMinimapButton" then minimap = frame end
        if frame.name == "LootListHistoryButton" then button = frame end
    end
    assert(not panel.shown)
    minimap.scripts.OnClick(minimap, "RightButton"); assert(panel.shown)
    equal(#s.historyRows(), 0)
    panel:Hide(); button.scripts.OnClick(button); assert(panel.shown)
    SlashCmdList.LOOTLIST("historytest")
    equal(#s.historyRows(), 4); equal(LootListDB.groupHistory, nil); equal(#s.sounds, 0)
    SlashCmdList.LOOTLIST("history"); equal(#s.historyRows(), 0)
    equal(LootListDB.groupHistory, nil)
end)

test("history ignores restricted results and disabled recording, but still cleans up", function()
    local s = setup({ secret = "Hiddenname", instance = { id = 36, kind = "party", name = "Dungeon", difficulty = 1 } })
    s.event("PLAYER_ENTERING_WORLD")
    s.history[1] = { lootListKey = 920, itemHyperlink = link(2), startTime = 1000,
        winner = { playerName = "Hiddenname", state = 0, roll = 99 } }
    s.event("LOOT_HISTORY_UPDATE_DROP", 100, 920)
    equal(LootListDB.groupHistory.entries[1].winner, nil)
    s.addon.SetGroupLootEnabled(false)
    s.history[2] = { lootListKey = 921, itemHyperlink = link(3), startTime = 1000, allPassed = true }
    s.event("LOOT_HISTORY_UPDATE_DROP", 100, 921)
    equal(#LootListDB.groupHistory.entries, 1)
    s.setInstance(nil); s.event("ZONE_CHANGED_NEW_AREA")
    equal(LootListDB.groupHistory, nil)
end)

test("history renders a long list without duplicating rows on repeated updates", function()
    local s = setup({ instance = { id = 409, kind = "raid", name = "Molten Core", difficulty = 1 } })
    s.event("PLAYER_ENTERING_WORLD")
    for i = 1, 35 do
        s.history[i] = { lootListKey = 1000 + i, itemHyperlink = link(2), startTime = 1000 + i,
            winner = { playerName = "Winner" .. i, state = i % 2 == 0 and 0 or 3, roll = 65 + i } }
    end
    s.event("LOOT_HISTORY_UPDATE_ENCOUNTER", 100)
    SlashCmdList.LOOTLIST("history")
    equal(#s.historyRows(), 35)
    assert(s.historyRows()[1].resultText.text:find("Winner35", 1, true))
    local frames = #s.frames
    s.event("LOOT_HISTORY_UPDATE_ENCOUNTER", 100)
    equal(#s.historyRows(), 35); equal(#s.frames, frames)
    equal(#LootListDB.groupHistory.entries, 35)
end)

test("enabled group module suppresses default visuals and input without hiding or unregistering", function()
    local s = setup({ defaultRoll = true })
    equal(s.defaultRoll:GetAlpha(), 0)
    assert(s.defaultRoll.shown)
    assert(not s.defaultRoll:IsMouseEnabled()); assert(not s.defaultButton:IsMouseEnabled())
    s.defaultRoll:RegisterEvent("CANCEL_LOOT_ROLL")
    local hides = 0
    s.defaultRoll:SetScript("OnHide", function() hides = hides + 1 end)
    s.addon.SetGroupLootEnabled(false)
    equal(s.defaultRoll:GetAlpha(), 0.6)
    assert(s.defaultRoll:IsMouseEnabled()); assert(s.defaultButton:IsMouseEnabled())
    assert(not s.defaultHiddenButton:IsMouseEnabled())
    assert(s.defaultRoll.events.CANCEL_LOOT_ROLL); equal(hides, 0)
    s.addon.SetGroupLootEnabled(true)
    equal(s.defaultRoll:GetAlpha(), 0); equal(hides, 0)
end)

test("default group suppression catches late frames and defers protected changes in combat", function()
    local s = setup({ defaultRoll = true, protectedDefault = true, combat = true })
    equal(s.defaultRoll:GetAlpha(), 0.6)
    assert(s.defaultButton:IsMouseEnabled())
    s.setCombat(false); s.event("PLAYER_REGEN_ENABLED")
    equal(s.defaultRoll:GetAlpha(), 0); assert(not s.defaultButton:IsMouseEnabled())
    s.setCombat(true); s.addon.SetGroupLootEnabled(false)
    equal(s.defaultRoll:GetAlpha(), 0)
    s.setCombat(false); s.event("PLAYER_REGEN_ENABLED")
    equal(s.defaultRoll:GetAlpha(), 0.6); assert(s.defaultButton:IsMouseEnabled())
    local late = CreateFrame("Frame", nil, UIParent)
    late:SetAlpha(0.8)
    _G.GroupLootFrame2 = late
    s.addon.SetGroupLootEnabled(true)
    equal(late:GetAlpha(), 0)
    local child = CreateFrame("Button", nil, late)
    assert(child:IsMouseEnabled())
    s.event("START_LOOT_ROLL", 999, 60000); s.advance(0.01)
    assert(not child:IsMouseEnabled())
end)

for _, entry in ipairs(tests) do
    local ok, err = pcall(entry[2])
    if not ok then error("FAIL " .. entry[1] .. ": " .. tostring(err)) end
    passed = passed + 1
    print("PASS " .. entry[1])
end
print(passed .. " tests passed")
