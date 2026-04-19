-- lib/palette.lua — динамическое расширение палитры CC:Tweaked.
--
-- CC даёт 16 цветов (colors.white .. colors.black), но через term.setPaletteColor(c, r,g,b)
-- слоты можно переопределить. На странице обычно не более 8-10 уникальных цветов,
-- так что мы можем подменить 8 "редких" слотов (brown, purple, cyan и т.п.) на
-- реальные цвета страницы, сохранив базовые (white, black, red, green, blue, yellow, gray, lightGray).
--
-- Экспорты:
--   palette.init(term)            — запомнить оригинальные цвета (для restore)
--   palette.restore(term)         — вернуть оригинал
--   palette.mapColors(rgbList, term) → {rgbHex -> ccSlot}
--                                 — применяет setPaletteColor и возвращает маппинг
--   palette.extractFromCss(rulesList, domRoot) → array of {r,g,b,hex}
--                                 — собрать все color/bg значения со страницы

local M = {}

-- Слоты, которые мы МОЖЕМ переопределить (они реже нужны в chrome OS).
-- Оставляем нетронутыми: white, black, red, green, blue, yellow, gray, lightGray.
local DYNAMIC_SLOTS = nil
local function getDynamicSlots()
    if DYNAMIC_SLOTS then return DYNAMIC_SLOTS end
    local c = _G.colors or {}
    DYNAMIC_SLOTS = {
        c.orange, c.magenta, c.lightBlue, c.lime,
        c.pink, c.cyan, c.purple, c.brown,
    }
    return DYNAMIC_SLOTS
end

-- Оригинальные значения палитры (для восстановления).
local originals = {}
local initialized = false

function M.init(termApi)
    termApi = termApi or term
    if initialized then return end
    if not termApi.getPaletteColor then return end
    for _, slot in ipairs(getDynamicSlots()) do
        if slot then
            local r, g, b = termApi.getPaletteColor(slot)
            originals[slot] = { r, g, b }
        end
    end
    initialized = true
end

function M.restore(termApi)
    termApi = termApi or term
    if not termApi.setPaletteColor then return end
    for slot, rgb in pairs(originals) do
        pcall(termApi.setPaletteColor, slot, rgb[1], rgb[2], rgb[3])
    end
end

-- Парсит CSS-значение цвета в {r,g,b} (0..1) или nil. Поддерживает #rgb/#rrggbb/rgb().
local function parseColor(v)
    if type(v) ~= "string" then return nil end
    v = v:match("^%s*(.-)%s*$")
    -- #rgb
    local r, g, b = v:match("^#(%x)(%x)(%x)$")
    if r then
        r = tonumber(r, 16) * 17
        g = tonumber(g, 16) * 17
        b = tonumber(b, 16) * 17
        return { r = r / 255, g = g / 255, b = b / 255, hex = string.format("%02x%02x%02x", r, g, b) }
    end
    -- #rrggbb
    r, g, b = v:match("^#(%x%x)(%x%x)(%x%x)$")
    if r then
        r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
        return { r = r / 255, g = g / 255, b = b / 255, hex = string.format("%02x%02x%02x", r, g, b) }
    end
    -- rgb(n,n,n)
    r, g, b = v:match("^rgb%s*%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)$")
    if r then
        r, g, b = tonumber(r), tonumber(g), tonumber(b)
        return { r = r / 255, g = g / 255, b = b / 255, hex = string.format("%02x%02x%02x", r, g, b) }
    end
    return nil
end

-- Сбор всех hex-цветов из CSS-правил + inline styles DOM. Возвращает массив
-- уникальных {r,g,b,hex} с подсчётом использований (для приоритезации).
function M.extractFromCss(rulesList, domRoot)
    local seen = {}
    local out = {}
    local function add(col)
        if not col then return end
        local e = seen[col.hex]
        if e then e.count = e.count + 1; return end
        e = { r = col.r, g = col.g, b = col.b, hex = col.hex, count = 1 }
        seen[col.hex] = e
        out[#out + 1] = e
    end

    -- Проход по rulesList
    for _, rule in ipairs(rulesList or {}) do
        local d = rule.declarations or {}
        for _, prop in ipairs({ "color", "background-color", "background", "border-color" }) do
            if d[prop] then add(parseColor(d[prop])) end
        end
    end

    -- Проход по inline styles в DOM (рекурсивно)
    local function walk(node)
        if type(node) ~= "table" then return end
        if node.attrs and node.attrs.style then
            for kv in node.attrs.style:gmatch("[^;]+") do
                local k, v = kv:match("^%s*([%w%-]+)%s*:%s*(.+)%s*$")
                if k and v then
                    if k == "color" or k == "background" or k == "background-color" or k == "border-color" then
                        add(parseColor(v))
                    end
                end
            end
        end
        if node.children then
            for _, ch in ipairs(node.children) do walk(ch) end
        end
    end
    walk(domRoot)

    -- Сортируем по убыванию использований
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end

-- Применить палитру страницы: переопределить до 8 динамических слотов
-- под реальные цвета страницы. Возвращает {hex -> ccSlot} для css.rgbToCC override.
function M.mapColors(rgbList, termApi)
    termApi = termApi or term
    M.init(termApi)
    M.restore(termApi)
    if not termApi.setPaletteColor then return {} end

    local slots = getDynamicSlots()
    local mapping = {}
    local n = math.min(#rgbList, #slots)
    for i = 1, n do
        local c = rgbList[i]
        local slot = slots[i]
        if slot then
            pcall(termApi.setPaletteColor, slot, c.r, c.g, c.b)
            mapping[c.hex] = slot
        end
    end
    return mapping
end

-- Хелпер: вызывать из css-пайплайна страницы вместо rgbToCC.
-- mapping — результат mapColors. Если в mapping нет цвета — fallback к стандартному.
function M.makeLookup(mapping)
    return function(r, g, b)
        local hex = string.format("%02x%02x%02x", r, g, b)
        return mapping[hex]  -- может быть nil; caller сделает fallback
    end
end

return M
