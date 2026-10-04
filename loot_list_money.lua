local _, addon = ...
local units, formats, seenUnits, seenFormats = {}, {}, {}, {}
local UNIT_KEYS = { { "GOLD_AMOUNT", 10000 }, { "SILVER_AMOUNT", 100 }, { "COPPER_AMOUNT", 1 } }
-- Match bonus messages before the broad single-%s format.
local FORMAT_KEYS = { "YOU_LOOT_MONEY_MOD", "YOU_LOOT_MONEY", "LOOT_MONEY_SPLIT",
    "LOOT_MONEY_SPLIT_GUILD", "ERR_AUTOLOOT_MONEY_S" }

local function public(value)
    return not issecretvalue or not issecretvalue(value)
end

local function patternFor(format)
    local parts, index = {}, 1
    while index <= #format do
        local tail = format:sub(index)
        local token = tail:match("^%%%d+%$[sd]") or tail:match("^%%[sd]")
        if token then
            parts[#parts + 1] = token:sub(-1) == "d" and "(%d[%d,%.]*)" or "(.-)"
            index = index + #token
        else
            parts[#parts + 1] = tail:sub(1, 1):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
            index = index + 1
        end
    end
    return table.concat(parts)
end

local function addUnit(format, multiplier)
    if not public(format) or type(format) ~= "string" or seenUnits[format] or #units >= 64 then return end
    seenUnits[format] = true
    -- Blizzard's plural escape can expand to multiple localized unit names.
    local prefix, variants, suffix = format:match("^(.-)|4(.-);(.*)$")
    if variants then
        for variant in variants:gmatch("[^:]+") do addUnit(prefix .. variant .. suffix, multiplier) end
    else
        units[#units + 1] = { pattern = patternFor(format), multiplier = multiplier }
    end
end

local function refresh()
    for _, unit in ipairs(UNIT_KEYS) do addUnit(_G[unit[1]], unit[2]) end
    for _, key in ipairs(FORMAT_KEYS) do
        local format = _G[key]
        if public(format) and type(format) == "string" and not seenFormats[format] and #formats < 32 then
            seenFormats[format] = true
            formats[#formats + 1] = { pattern = "^" .. patternFor(format) .. "$",
                bonus = key == "YOU_LOOT_MONEY_MOD" }
        end
    end
end

local function amountFromText(text)
    text = text:gsub("|cn[%w_]+:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local amount = 0
    -- Coin textures identify denominations regardless of client language.
    local textureAmount, textures = 0, false
    for number, texture in text:gmatch("(%d[%d,%.]*)%s*|T([^|]+)|t") do
        local path = texture:lower()
        local multiplier = path:find("gold", 1, true) and 10000
            or path:find("silver", 1, true) and 100
            or path:find("copper", 1, true) and 1
        if multiplier then
            textureAmount = textureAmount + tonumber((number:gsub("[,%.]", ""))) * multiplier
            textures = true
        end
    end
    if textures then return textureAmount end
    -- Match each unit once: original and addon-translated formats can coexist.
    local used = {}
    for _, unit in ipairs(units) do
        if not used[unit.multiplier] then
            local number = text:match(unit.pattern)
            if number then
                amount = amount + tonumber((number:gsub("[,%.]", ""))) * unit.multiplier
                used[unit.multiplier] = true
            end
        end
    end
    return amount
end

function addon.InitializeMoney()
    refresh()
end

function addon.ParseMoney(message)
    if not public(message) or type(message) ~= "string" then return end
    refresh()
    for _, format in ipairs(formats) do
        local captures = { message:match(format.pattern) }
        if captures[1] then
            local amount = amountFromText(captures[1])
            -- The bonus is collected; guild deposits in other formats are not.
            if format.bonus and captures[2] then amount = amount + amountFromText(captures[2]) end
            if amount > 0 then return amount end
        end
    end
end
