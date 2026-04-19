-- css.lua
-- Маленький CSS-парсер для браузера ZnatokOS.
-- Lua 5.3, работает с DOM от html.lua.
--
-- Поддерживает только визуальные свойства, которые имеет смысл
-- отображать в терминале CC:Tweaked (16-цветная палитра).
--
-- Поддерживаемые свойства:
--   color            -> fg (colors.*)
--   background-color -> bg
--   background       -> bg (упрощённо: берём первый цветовой токен)
--   font-weight      -> bold=true (если bold/700/800/900)
--   font-style       -> italic=true
--   text-decoration  -> underline=true / strike=true
--   display: none    -> hidden=true
--
-- Все остальные свойства тихо игнорируются (не падаем).

local M = {}

-- =========================================================================
-- Палитра CC:Tweaked (именованные цвета -> маска + RGB-референс)
-- =========================================================================

-- Глобал `colors` существует только в CC:Tweaked; для юнит-тестов
-- тестовый файл может подсунуть свой stub.
local _colors = rawget(_G, "colors") or {}

-- Референсные RGB-значения 16 цветов CC:Tweaked (из официальной палитры).
local CC_RGB = {
    white     = {0xF0, 0xF0, 0xF0},
    orange    = {0xF2, 0xB2, 0x33},
    magenta   = {0xE5, 0x7F, 0xD8},
    lightBlue = {0x99, 0xB2, 0xF2},
    yellow    = {0xDE, 0xDE, 0x6C},
    lime      = {0x7F, 0xCC, 0x19},
    pink      = {0xF2, 0xB2, 0xCC},
    gray      = {0x4C, 0x4C, 0x4C},
    lightGray = {0x99, 0x99, 0x99},
    cyan      = {0x4C, 0x99, 0xB2},
    purple    = {0xB2, 0x66, 0xE5},
    blue      = {0x33, 0x66, 0xCC},
    brown     = {0x7F, 0x66, 0x4C},
    green     = {0x57, 0xA6, 0x4E},
    red       = {0xCC, 0x4C, 0x4C},
    black     = {0x11, 0x11, 0x11},
}

-- Возвращает значение colors[name] либо сам name (фолбэк, когда нет globals).
local function cc(name)
    return _colors[name]
end

-- CSS named colors -> ближайший CC-цвет (по смыслу / палитре).
-- Покрываем популярные HTML-цвета. Остальное ляжет через hex-резолвер.
local CSS_NAMES = {
    black     = "black",
    white     = "white",
    red       = "red",
    green     = "green",
    blue      = "blue",
    yellow    = "yellow",
    cyan      = "cyan",
    magenta   = "magenta",
    orange    = "orange",
    pink      = "pink",
    purple    = "purple",
    brown     = "brown",
    gray      = "gray",
    grey      = "gray",
    darkgray  = "gray",
    darkgrey  = "gray",
    lightgray = "lightGray",
    lightgrey = "lightGray",
    silver    = "lightGray",
    lightblue = "lightBlue",
    skyblue   = "lightBlue",
    navy      = "blue",
    darkblue  = "blue",
    darkred   = "red",
    maroon    = "red",
    crimson   = "red",
    darkgreen = "green",
    lime      = "lime",
    olive     = "brown",
    teal      = "cyan",
    aqua      = "cyan",
    violet    = "purple",
    indigo    = "purple",
    gold      = "yellow",
    beige     = "white",
    tan       = "brown",
    khaki     = "yellow",
    salmon    = "pink",
    coral     = "orange",
    tomato    = "red",
    ["hotpink"]  = "pink",
    ["deeppink"] = "magenta",
    transparent  = nil,   -- сознательно: вернёт nil -> свойство не применится
}

-- =========================================================================
-- Цветовые утилиты
-- =========================================================================

-- HEX -> r, g, b (0..255). Поддерживает #rgb и #rrggbb. Иначе — nil.
function M.hexToRgb(hex)
    if type(hex) ~= "string" then return nil end
    local h = hex:gsub("^#", "")
    if #h == 3 then
        local r = tonumber(h:sub(1, 1) .. h:sub(1, 1), 16)
        local g = tonumber(h:sub(2, 2) .. h:sub(2, 2), 16)
        local b = tonumber(h:sub(3, 3) .. h:sub(3, 3), 16)
        if r and g and b then return r, g, b end
        return nil
    elseif #h == 6 then
        local r = tonumber(h:sub(1, 2), 16)
        local g = tonumber(h:sub(3, 4), 16)
        local b = tonumber(h:sub(5, 6), 16)
        if r and g and b then return r, g, b end
        return nil
    end
    return nil
end

-- Ближайший CC-цвет (маска colors.*) по евклидову расстоянию в RGB.
function M.rgbToCC(r, g, b)
    local best_name, best_d = nil, math.huge
    for name, ref in pairs(CC_RGB) do
        local dr, dg, db = r - ref[1], g - ref[2], b - ref[3]
        local d = dr * dr + dg * dg + db * db
        if d < best_d then
            best_d, best_name = d, name
        end
    end
    return cc(best_name)
end

-- Универсальный резолвер цветового значения в CC-маску.
-- Принимает: "red", "#f00", "#ff0000", "rgb(255,0,0)".
-- Возвращает CC-маску или nil.
local function resolve_color(value)
    if not value or value == "" then return nil end
    local v = value:lower():gsub("^%s+", ""):gsub("%s+$", "")

    -- hex
    if v:sub(1, 1) == "#" then
        local r, g, b = M.hexToRgb(v)
        if r then return M.rgbToCC(r, g, b) end
        return nil
    end

    -- rgb(...) / rgba(...)
    local r, g, b = v:match("^rgba?%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
    if r then
        return M.rgbToCC(tonumber(r), tonumber(g), tonumber(b))
    end

    -- имя
    local mapped = CSS_NAMES[v]
    if mapped then return cc(mapped) end

    return nil
end

-- =========================================================================
-- Inline-парсер: "color: red; font-weight: bold"
-- =========================================================================

-- Разбирает строку декларации на {prop=value} без нормализации в CC.
local function split_decls(body)
    local out = {}
    if not body then return out end
    for decl in body:gmatch("[^;]+") do
        local prop, val = decl:match("^%s*([%w%-]+)%s*:%s*(.-)%s*$")
        if prop and val and val ~= "" then
            out[prop:lower()] = val
        end
    end
    return out
end

-- Применяет одну декларацию к таблице стиля (с нормализацией в CC).
local function apply_decl(style, prop, val)
    if not val then return end
    local v = val:gsub("^%s+", ""):gsub("%s+$", "")
    local vl = v:lower()

    if prop == "color" then
        local c = resolve_color(v)
        if c ~= nil then style.fg = c end

    elseif prop == "background-color" then
        local c = resolve_color(v)
        if c ~= nil then style.bg = c end

    elseif prop == "background" then
        -- Сокращённая форма: берём первый токен, который парсится как цвет.
        for token in v:gmatch("%S+") do
            local c = resolve_color(token)
            if c ~= nil then style.bg = c; break end
        end

    elseif prop == "font-weight" then
        if vl == "bold" or vl == "bolder"
            or vl == "700" or vl == "800" or vl == "900" then
            style.bold = true
        elseif vl == "normal" or vl == "lighter"
            or vl == "100" or vl == "200" or vl == "300"
            or vl == "400" or vl == "500" or vl == "600" then
            style.bold = false
        end

    elseif prop == "font-style" then
        if vl == "italic" or vl == "oblique" then
            style.italic = true
        elseif vl == "normal" then
            style.italic = false
        end

    elseif prop == "text-decoration" or prop == "text-decoration-line" then
        -- Может быть несколько токенов: "underline line-through".
        if vl:find("underline", 1, true) then style.underline = true end
        if vl:find("line%-through") or vl:find("strike", 1, true) then
            style.strike = true
        end
        if vl == "none" then
            style.underline = false
            style.strike = false
        end

    elseif prop == "display" then
        if vl == "none" then style.hidden = true end
    end
    -- Остальные свойства — молча игнорируем.
end

-- Публичный парсер инлайн-стиля.
-- Возвращает таблицу вида {fg=..., bg=..., bold=..., ...}.
function M.parseInline(styleString)
    local style = {}
    if not styleString or styleString == "" then return style end
    local decls = split_decls(styleString)
    for prop, val in pairs(decls) do
        apply_decl(style, prop, val)
    end
    return style
end

-- =========================================================================
-- Парсер <style>-блоков
-- =========================================================================

-- Возвращает массив правил: {{selectors={...}, declarations={fg=..., ...}}, ...}
function M.parseStyleBlock(cssText)
    local rules = {}
    if not cssText or cssText == "" then return rules end

    -- 1) Убираем комментарии /* ... */
    local text = cssText:gsub("/%*.-%*/", "")

    -- 2) Простейший проход по блокам "selectors { body }".
    -- Не поддерживаем вложенные {} (CSS до nesting-уровня).
    local i, n = 1, #text
    while i <= n do
        -- Ищем '{'.
        local open = text:find("{", i, true)
        if not open then break end
        local close = text:find("}", open + 1, true)
        if not close then break end

        local sel_part = text:sub(i, open - 1)
        local body     = text:sub(open + 1, close - 1)
        i = close + 1

        -- Пропускаем @-rules: @media, @import, @font-face, @keyframes и т.п.
        local sel_trim = sel_part:gsub("^%s+", ""):gsub("%s+$", "")
        if sel_trim:sub(1, 1) == "@" then
            -- Для @media/@keyframes мы уже ушли за первую '}', но тело
            -- группового правила может быть вложенным — тогда следующий
            -- проход съест остатки как "мусорные" селекторы и отбросит их,
            -- когда они окажутся пустыми/невалидными. Для простоты: скип.
        else
            -- Разбиваем селекторы по запятой.
            local selectors = {}
            for s in sel_trim:gmatch("[^,]+") do
                local t = s:gsub("^%s+", ""):gsub("%s+$", "")
                if t ~= "" then selectors[#selectors + 1] = t end
            end

            -- Парсим декларации.
            local style = {}
            local decls = split_decls(body)
            for prop, val in pairs(decls) do
                apply_decl(style, prop, val)
            end

            if #selectors > 0 and next(style) ~= nil then
                rules[#rules + 1] = {
                    selectors    = selectors,
                    declarations = style,
                }
            end
        end
    end

    return rules
end

-- =========================================================================
-- Селекторы
-- =========================================================================

-- Разбирает одиночный compound-селектор "tag.class#id" на компоненты.
local function parse_compound(sel)
    local tag, classes, id = nil, {}, nil
    local rest = sel

    -- Универсальный селектор '*' — отдельно.
    if rest == "*" then return { any = true } end

    -- Tag (если есть) в начале.
    local t_end = 1
    while t_end <= #rest do
        local c = rest:sub(t_end, t_end)
        if c == "." or c == "#" then break end
        t_end = t_end + 1
    end
    if t_end > 1 then
        tag = rest:sub(1, t_end - 1):lower()
    end
    rest = rest:sub(t_end)

    -- Далее последовательности .class и #id.
    while #rest > 0 do
        local c = rest:sub(1, 1)
        if c == "." then
            local m = rest:match("^%.([%w%-_]+)")
            if not m then break end
            classes[#classes + 1] = m
            rest = rest:sub(1 + #m + 1)
        elseif c == "#" then
            local m = rest:match("^#([%w%-_]+)")
            if not m then break end
            id = m
            rest = rest:sub(1 + #m + 1)
        else
            break
        end
    end

    return { tag = tag, classes = classes, id = id }
end

-- Проверяет, матчит ли узел один compound-селектор.
local function match_compound(node, compound)
    if not node or node.kind ~= "elem" then return false end
    if compound.any then return true end

    if compound.tag and node.tag ~= compound.tag then return false end

    local attrs = node.attrs or {}

    if compound.id then
        if attrs.id ~= compound.id then return false end
    end

    if compound.classes and #compound.classes > 0 then
        local cl = attrs.class or ""
        -- Собираем класс-множество один раз.
        local set = {}
        for w in cl:gmatch("%S+") do set[w] = true end
        for _, want in ipairs(compound.classes) do
            if not set[want] then return false end
        end
    end

    return true
end

-- Публичная функция: selectorMatch(node, selector [, ancestors]).
-- Поддерживает:
--   tag, .class, #id, tag.class, tag#id, *,
--   "a b" (descendant), "a > b" (child).
-- ancestors — массив от корня к родителю (не включая сам node).
function M.selectorMatch(node, selector, ancestors)
    if not node or node.kind ~= "elem" then return false end
    if not selector or selector == "" then return false end

    -- Нормализуем пробелы вокруг '>'.
    local sel = selector:gsub("%s*>%s*", " > "):gsub("%s+", " ")
    sel = sel:gsub("^%s+", ""):gsub("%s+$", "")

    -- Разбиваем на токены: compound-селекторы и комбинаторы.
    local tokens = {}
    for tok in sel:gmatch("%S+") do tokens[#tokens + 1] = tok end
    if #tokens == 0 then return false end

    -- Последний токен должен совпадать с самим node.
    local last = tokens[#tokens]
    if not match_compound(node, parse_compound(last)) then return false end

    if #tokens == 1 then return true end

    -- Обрабатываем цепочку справа налево.
    ancestors = ancestors or {}
    local a_idx = #ancestors   -- текущий кандидат-предок
    local k = #tokens - 1
    while k >= 1 do
        local tok = tokens[k]
        if tok == ">" then
            -- Прямой родитель: должен совпасть с предыдущим compound.
            local parent_sel = tokens[k - 1]
            if not parent_sel then return false end
            local pc = parse_compound(parent_sel)
            local parent = ancestors[a_idx]
            if not parent or not match_compound(parent, pc) then
                return false
            end
            a_idx = a_idx - 1
            k = k - 2
        else
            -- Descendant: ищем любого предка, подходящего под tok.
            local pc = parse_compound(tok)
            local found = false
            while a_idx >= 1 do
                if match_compound(ancestors[a_idx], pc) then
                    a_idx = a_idx - 1
                    found = true
                    break
                end
                a_idx = a_idx - 1
            end
            if not found then return false end
            k = k - 1
        end
    end

    return true
end

-- =========================================================================
-- Применение правил к DOM
-- =========================================================================

-- Свойства, которые наследуются от родителя.
local INHERITED = {
    fg = true, bold = true, italic = true,
    underline = true, strike = true,
}

-- Копирует только наследуемые поля из src в новый стиль.
local function inherit_from(src)
    local out = {}
    if not src then return out end
    for k, _ in pairs(INHERITED) do
        if src[k] ~= nil then out[k] = src[k] end
    end
    return out
end

-- Сливает src в dst (перекрывая поля).
local function merge(dst, src)
    if not src then return dst end
    for k, v in pairs(src) do dst[k] = v end
    return dst
end

-- Обход дерева с применением правил и инлайн-стиля.
-- rulesList: массив правил из parseStyleBlock.
-- inheritFromParent: начальный стиль (для корневого вызова обычно nil).
function M.apply(domRoot, rulesList, inheritFromParent)
    if not domRoot then return end
    rulesList = rulesList or {}

    local function walk(node, ancestors, inherited)
        if node.kind ~= "elem" then return end

        -- Шаг 1: базовый стиль из наследуемых полей родителя.
        local style = inherit_from(inherited)

        -- Шаг 2: применяем правила, чьи селекторы матчат.
        for _, rule in ipairs(rulesList) do
            local matched = false
            for _, sel in ipairs(rule.selectors) do
                if M.selectorMatch(node, sel, ancestors) then
                    matched = true
                    break
                end
            end
            if matched then merge(style, rule.declarations) end
        end

        -- Шаг 3: инлайн-стиль имеет наивысший приоритет.
        local inline_src = node.attrs and node.attrs.style
        if inline_src and inline_src ~= "" then
            merge(style, M.parseInline(inline_src))
        end

        -- Сохраняем computed style.
        node.style = style

        -- Рекурсия в детей, если не скрыт.
        if node.children then
            ancestors[#ancestors + 1] = node
            for _, ch in ipairs(node.children) do
                walk(ch, ancestors, style)
            end
            ancestors[#ancestors] = nil
        end
    end

    walk(domRoot, {}, inheritFromParent)
end

return M
