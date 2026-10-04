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
        "SetTexCoord", "SetJustifyH", "SetWordWrap", "SetShadowOffset", "SetAllPoints",
        "SetColorTexture", "ClearAllPoints", "StopMovingOrSizing", "EnableMouse", "SetFrameLevel",
        "SetHighlightTexture", "SetBlendMode", "SetDesaturated", "SetMinMaxValues", "SetValueStep", "SetObeyStepOnDrag" }) do methods[name] = function() end end
    function methods:SetScale(value) self.scale = value end
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
    function methods:Show() self.shown = true end
    function methods:Hide()
        local wasShown = self.shown
        self.shown = false
        if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function methods:SetScript(event, fn) self.scripts[event] = fn end
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:StartMoving() self.moving = true end
    local function object(kind, name, parent)
        local obj = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, events = {} }, { __index = methods })
        frames[#frames + 1] = obj
        return obj
    end
    function methods:CreateTexture() return object("Texture") end
    function methods:CreateFontString() return object("FontString") end
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
    assert(loadfile("loot_list_ui.lua"))("Loot_list", addon)
    assert(loadfile("loot_list_settings.lua"))("Loot_list", addon)
    assert(loadfile("loot_list_money.lua"))("Loot_list", addon)
    assert(loadfile("loot_list.lua"))("Loot_list", addon)
    local show = addon.ShowItem
    addon.ShowItem = function(item) displayed[#displayed + 1] = item; show(item) end
    local eventFrame
    for _, frame in ipairs(frames) do
        if frame.events.ADDON_LOADED then eventFrame = frame end
    end
    local function event(name, ...) eventFrame.scripts.OnEvent(eventFrame, name, ...) end
    event("ADDON_LOADED", "Loot_list")
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
        displayed = displayed, rows = rows, frames = frames,
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
    for _, frame in ipairs(s.frames) do if frame.kind == "CheckButton" then boxes[#boxes + 1] = frame end end
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
    equal(count, 6)
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

for _, entry in ipairs(tests) do
    local ok, err = pcall(entry[2])
    if not ok then error("FAIL " .. entry[1] .. ": " .. tostring(err)) end
    passed = passed + 1
    print("PASS " .. entry[1])
end
print(passed .. " tests passed")
